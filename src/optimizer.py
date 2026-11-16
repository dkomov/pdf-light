#!/usr/bin/env python3
"""Local PDF optimization engine. Never writes to the source document."""
import argparse
import io
import json
import logging
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import zlib

from pypdf import PdfReader, PdfWriter
from pypdf.generic import (ContentStream, DictionaryObject, NameObject,
                          NumberObject, StreamObject)
from PIL import Image, ImageChops, ImageStat
import pypdfium2 as pdfium

logging.getLogger('pypdf').setLevel(logging.ERROR)
NUMBER = re.compile(rb'[+-]?(?:\d+\.?\d*|\.\d+)\Z')
SPACE = b'\x00\t\n\x0c\r '
DELIMS = SPACE + b'()<>[]{}/%'
IDENTITY = (1., 0., 0., 1., 0., 0.)
PATH_ARITY = {b'm': 2, b'l': 2, b'c': 6, b'v': 4, b'y': 4, b're': 4}


def emit(kind, **values):
    print(json.dumps({'type': kind, **values}, ensure_ascii=False), flush=True)


def tokens(data):
    """Yield lexical tokens with byte ranges; strings/comments remain opaque."""
    i, size = 0, len(data)
    while i < size:
        c = data[i]
        if c in SPACE:
            i += 1
            continue
        start = i
        if c == 37:
            while i < size and data[i] not in b'\r\n':
                i += 1
            continue
        if c == 40:
            i += 1
            depth = 1
            while i < size and depth:
                if data[i] == 92:
                    i += 2
                else:
                    if data[i] == 40:
                        depth += 1
                    elif data[i] == 41:
                        depth -= 1
                    i += 1
            if depth:
                raise ValueError('Незакрытая строка PDF.')
            yield ('value', start, i, data[start:i])
            continue
        if c == 60 and data[i:i+2] != b'<<':
            end = data.find(b'>', i+1)
            if end < 0:
                raise ValueError('Повреждённая строка PDF.')
            i = end+1
            yield ('value', start, i, data[start:i])
            continue
        if c in b'[]{}<>' or c == 41:
            i += 2 if data[i:i+2] in (b'<<', b'>>') else 1
            yield ('value', start, i, data[start:i])
            continue
        if c == 47:
            i += 1
            while i < size and data[i] not in DELIMS:
                i += 1
            yield ('name', start, i, data[start:i])
            continue
        i += 1
        while i < size and data[i] not in DELIMS:
            i += 1
        value = data[start:i]
        yield ('number' if NUMBER.fullmatch(value) else 'operator', start, i, value)


def operations(data):
    pending = []
    for tok in tokens(data):
        if tok[0] == 'operator':
            if tok[3] == b'BI':
                # Inline images can contain arbitrary operator-looking bytes.
                raise NotImplementedError('inline image')
            yield pending, tok
            pending = []
        else:
            pending.append(tok)


def concatenate(ctm, matrix):
    a, b, c, d, e, f = ctm
    A, B, C, D, E, F = matrix
    return (a*A+c*B, b*A+d*B, a*C+c*D, b*C+d*D,
            a*E+c*F+e, b*E+d*F+f)


def transform(ctm, x, y):
    a, b, c, d, e, f = ctm
    return (a*x+c*y+e, b*x+d*y+f)


def opaque_mask_rect(state, reader):
    """Accept only a demonstrably solid rectangular alpha mask, never artwork."""
    mask = state.get('/SMask')
    if mask is None or str(mask) == '/None':
        return None
    mask = mask.get_object()
    if not isinstance(mask, dict) or mask.get('/S') != '/Alpha':
        return None
    if mask.get('/TR', '/Identity') != '/Identity':
        return None
    group = mask.get('/G')
    if not group:
        return None
    group = group.get_object()
    if group.get('/Subtype') != '/Form':
        return None
    if tuple(map(float, group.get('/Matrix', IDENTITY))) != IDENTITY:
        return None
    if group.get('/Resources') and len(group['/Resources']):
        return None
    if not group.get('/Group') or group['/Group'].get('/S') != '/Transparency':
        return None
    try:
        ops = ContentStream(group, reader).operations
        points, rect, filled = [], None, False
        for args, op in ops:
            if filled:
                return None
            if op in (b'g', b'rg', b'k'):
                if points or rect:
                    return None
            elif op == b're' and len(args) == 4 and not points and rect is None:
                x, y, w, h = map(float, args)
                if w <= 0 or h <= 0:
                    return None
                rect = (x, y, x+w, y+h)
            elif op == b'm' and len(args) == 2 and not points and rect is None:
                points.append(tuple(map(float, args)))
            elif op == b'l' and len(args) == 2 and points and len(points) < 5:
                points.append(tuple(map(float, args)))
            elif op == b'h' and points:
                pass
            elif op in (b'f', b'f*'):
                filled = True
            else:
                return None
        if not filled:
            return None
        if points:
            if len(points) == 5 and points[0] == points[-1]:
                points.pop()
            if len(points) != 4:
                return None
            xs, ys = sorted(set(p[0] for p in points)), sorted(set(p[1] for p in points))
            if len(xs) != 2 or len(ys) != 2 or len(set(points)) != 4:
                return None
            if any(a[0] != b[0] and a[1] != b[1]
                   for a, b in zip(points, points[1:]+points[:1])):
                return None
            rect = (xs[0], ys[0], xs[1], ys[1])
        if rect is None or tuple(map(float, group.get('/BBox', []))) != rect:
            return None
        return rect
    except Exception:
        return None


def covers_page(rect, ctm, box):
    if abs(ctm[1]) > 1e-9 or abs(ctm[2]) > 1e-9:
        return False
    x0, y0 = transform(ctm, rect[0], rect[1])
    x1, y1 = transform(ctm, rect[2], rect[3])
    return (min(x0,x1) <= float(box.left)+1e-6 and
            min(y0,y1) <= float(box.bottom)+1e-6 and
            max(x0,x1) >= float(box.right)-1e-6 and
            max(y0,y1) >= float(box.top)-1e-6)


def decimal_step(limit):
    """A short decimal step bounded by the requested physical tolerance."""
    if not math.isfinite(limit) or limit <= 0:
        return None
    base = 10 ** math.floor(math.log10(limit))
    return max(x*base for x in (1, 2, 5, 10) if x*base <= limit*(1+1e-9))


def rewrite_page(page, writer, precision, repair):
    contents = page.get_contents()
    if contents is None:
        return 0, 0
    data = contents.get_data()
    try:
        # Parse first, before mutating any resources.
        ops = list(operations(data))
    except (NotImplementedError, ValueError):
        return 0, 0
    ctm, stack, in_text, replacements = IDENTITY, [], False, []
    rounded, repaired, path_ctm = 0, 0, None
    unit = float(page.get('/UserUnit', 1))
    resources = DictionaryObject(page['/Resources'])
    states = DictionaryObject(resources.get('/ExtGState', DictionaryObject()).get_object())
    new_states = False
    for args, token in ops:
        op = token[3]
        numeric = all(t[0] == 'number' for t in args)
        if op == b'q':
            stack.append(ctm)
        elif op == b'Q':
            if not stack:
                # An invalid graphics stack is not safe to optimize.
                return 0, 0
            ctm = stack.pop()
        elif op == b'cm' and numeric and len(args) == 6:
            ctm = concatenate(ctm, tuple(float(t[3]) for t in args))
        elif op == b'BT':
            in_text = True
        elif op == b'ET':
            in_text = False
        elif op == b'gs' and len(args) == 1 and args[0][0] == 'name' and repair:
            name = args[0][3].decode('latin1')
            if name in states:
                state = states[name].get_object()
                rect = opaque_mask_rect(state, writer)
                if rect and covers_page(rect, ctm, page.mediabox):
                    fixed = DictionaryObject(state)
                    fixed[NameObject('/SMask')] = NameObject('/None')
                    n = repaired+1
                    newname = f'/PDFLightMask{n}'
                    while newname in states:
                        n += 1
                        newname = f'/PDFLightMask{n}'
                    states[NameObject(newname)] = writer._add_object(fixed)
                    replacements.append((args[0][1], args[0][2], newname.encode()))
                    repaired += 1
                    new_states = True
        elif op in PATH_ARITY and numeric and len(args) == PATH_ARITY[op] and not in_text:
            if op in (b'm', b're'):
                path_ctm = ctm
            if not precision or ctm != path_ctm:
                continue
            norm = max(abs(ctm[0])+abs(ctm[2]), abs(ctm[1])+abs(ctm[3])) * unit
            if norm < 1e-12:
                continue
            step = decimal_step(precision/norm)
            if not step or step < 1e-6:
                continue
            for t in args:
                value = float(t[3])
                if not math.isfinite(value):
                    continue
                v = round(value/step)*step
                txt = f'{v:.6f}'.rstrip('0').rstrip('.')
                if txt in ('-0', ''):
                    txt = '0'
                encoded = txt.encode()
                # Never increase the lexical size of a coordinate.
                if len(encoded) < len(t[3]) and encoded != t[3]:
                    replacements.append((t[1], t[2], encoded))
                    rounded += 1
        elif op in (b'S', b's', b'f', b'F', b'f*', b'B', b'B*', b'b', b'b*', b'n'):
            path_ctm = None
    if new_states:
        resources[NameObject('/ExtGState')] = states
        page[NameObject('/Resources')] = resources
    if replacements:
        result, pos = [], 0
        for start, end, value in sorted(replacements):
            result += [data[pos:start], value]
            pos = end
        result.append(data[pos:])
        contents.set_data(b''.join(result))
        page.replace_contents(contents)
    return rounded, repaired


def compress_images(writer, quality, max_dimension):
    count = 0
    masks = set()
    for parent in writer._objects:
        if isinstance(parent, dict):
            for key in ('/SMask', '/Mask'):
                value = parent.get(key)
                if value is not None and hasattr(value, 'get_object'):
                    resolved = value.get_object()
                    if isinstance(resolved, StreamObject):
                        masks.add(id(resolved))
    for obj in writer._objects:
        if not isinstance(obj, StreamObject) or obj.get('/Subtype') != '/Image':
            continue
        if id(obj) in masks:
            continue
        if (obj.get('/Filter') != '/DCTDecode' or obj.get('/ColorSpace') not in ('/DeviceRGB','/DeviceGray')
                or obj.get('/BitsPerComponent') != 8 or any(k in obj for k in ('/SMask','/Mask','/Decode','/ImageMask'))):
            continue
        if len(obj._data) < 80_000:
            continue
        try:
            im = Image.open(io.BytesIO(obj._data))
            im.load()
            if im.mode not in ('RGB', 'L'):
                continue
            im.thumbnail((max_dimension, max_dimension), Image.Resampling.LANCZOS)
            buffer = io.BytesIO()
            im.save(buffer, format='JPEG', quality=quality, optimize=True, subsampling=0)
            encoded = buffer.getvalue()
            if len(encoded) < len(obj._data)*0.9:
                obj._data = encoded
                obj[NameObject('/Width')] = NumberObject(im.width)
                obj[NameObject('/Height')] = NumberObject(im.height)
                obj.pop('/DecodeParms', None)
                count += 1
        except (OSError, ValueError, Image.DecompressionBombError):
            continue
    return count


def make_candidate(source, destination, precision, repair, image_options=None):
    writer = PdfWriter(clone_from=str(source))
    rounded, masks, changed_pages = 0, 0, []
    for i, page in enumerate(writer.pages):
        n, m = rewrite_page(page, writer, precision, repair)
        rounded += n
        masks += m
        if m:
            changed_pages.append(i+1)
        if (i+1) % 8 == 0:
            emit('progress', message=f'Обработка страниц: {i+1} из {len(writer.pages)}')
    images = compress_images(writer, *image_options) if image_options else 0
    # Recompress only plain Flate streams; keep predictors and all other filters intact.
    for obj in writer._objects:
        if isinstance(obj, StreamObject) and obj.get('/Filter') == '/FlateDecode':
            try:
                compressed = zlib.compress(zlib.decompress(obj._data), 9)
                if len(compressed) < len(obj._data):
                    obj._data = compressed
            except zlib.error:
                pass
    for page in writer.pages:
        page.compress_content_streams(level=9)
    writer.compress_identical_objects(remove_duplicates=True, remove_unreferenced=True)
    writer.write(str(destination))
    return {'coordinates': rounded, 'masks': masks, 'mask_pages': changed_pages,
            'images': images, 'precision': precision}


def visual_check(original, candidate, allow_images, reference_dir=None):
    before, after = pdfium.PdfDocument(str(original)), pdfium.PdfDocument(str(candidate))
    if len(before) != len(after):
        raise ValueError('После обработки изменилось число страниц.')
    worst, bad = 0., []
    try:
        for i in range(len(before)):
            p, q = before[i], after[i]
            if p.get_size() != q.get_size():
                raise ValueError('После обработки изменились размеры страницы.')
            tp, tq = p.get_textpage(), q.get_textpage()
            if tp.get_text_range() != tq.get_text_range():
                raise ValueError('Проверка обнаружила изменение текста.')
            tp.close(); tq.close()
            scale = min(1., 1200/max(p.get_size()))
            bp, bq = p.render(scale=scale), q.render(scale=scale)
            ip, iq = bp.to_pil().convert('RGB'), bq.to_pil().convert('RGB')
            d = ImageChops.difference(ip, iq)
            mean = sum(ImageStat.Stat(d).mean)/3
            hist = d.convert('L').histogram()
            strong = sum(hist[49:])/(ip.width*ip.height)
            worst = max(worst, mean)
            if mean > (3.0 if allow_images else 1.0) or strong > (0.025 if allow_images else 0.008):
                bad.append(i+1)
            if reference_dir:
                iq.save(Path(reference_dir)/f'page-{i+1}.png')
            bp.close(); bq.close(); p.close(); q.close()
            if (i+1) % 5 == 0:
                emit('progress', message=f'Сравнение внешнего вида: {i+1} из {len(before)}')
        # Keep annotations and interactive forms; copy-based rewrite should preserve them.
        a, b = PdfReader(original), PdfReader(candidate)
        for p, q in zip(a.pages, b.pages):
            if len(p.get('/Annots', [])) != len(q.get('/Annots', [])):
                raise ValueError('Проверка обнаружила изменение аннотаций.')
        return {'ok': not bad, 'bad_pages': bad, 'mean_difference': worst}
    finally:
        before.close(); after.close()


def native_check(helper, candidate, references, work):
    native = Path(work)/'native'
    native.mkdir(exist_ok=True)
    process = subprocess.run([helper, '--render-check', str(candidate), str(native)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
    if process.returncode:
        return {'checked': False, 'bad_pages': [], 'reason': 'Проверка движком macOS недоступна.'}
    problems = []
    for reference in sorted(Path(references).glob('page-*.png')):
        rendered = native/reference.name
        if not rendered.exists():
            return {'checked': False, 'bad_pages': [], 'reason': 'Не все страницы отрисованы macOS.'}
        a, b = Image.open(reference).convert('RGB'), Image.open(rendered).convert('RGB')
        # Ignore ordinary antialiasing differences between PDF engines.
        b = b.resize(a.size, Image.Resampling.LANCZOS)
        a.thumbnail((400,400)); b = b.resize(a.size, Image.Resampling.LANCZOS)
        from PIL import ImageFilter
        d = ImageChops.difference(a.filter(ImageFilter.GaussianBlur(1)),
                                  b.filter(ImageFilter.GaussianBlur(1)))
        mean = sum(ImageStat.Stat(d).mean)/3
        if mean > 8:
            problems.append(int(reference.stem.split('-')[-1]))
    return {'checked': True, 'bad_pages': problems}


def optimize(args):
    source, output = Path(args.input).resolve(), Path(args.output).resolve()
    if source == output:
        raise ValueError('Оригинал и результат должны быть разными файлами.')
    if output.exists():
        raise ValueError('Файл результата уже существует. Выберите другое имя.')
    if not math.isfinite(args.target) or not .1 <= args.target <= 10000:
        raise ValueError('Укажите размер от 0,1 до 10 000 МБ.')
    emit('progress', message='Проверяю структуру PDF…')
    reader = PdfReader(source)
    if reader.is_encrypted:
        raise ValueError('PDF защищён. Сначала сохраните незашифрованную копию.')
    if not len(reader.pages):
        raise ValueError('В PDF нет страниц.')
    fields = reader.get_fields() or {}
    if any(str(field.get('/FT')) == '/Sig' and field.get('/V') for field in fields.values()):
        raise ValueError('В PDF есть цифровая подпись. Оптимизация сделает её недействительной.')
    original_size = source.stat().st_size
    target = int(args.target*1_000_000)
    modes = [(0., None, 'Сжатие без изменения графики')]
    if args.mode != 'lossless':
        modes += [(.05, None, 'Бережная оптимизация вектора'),
                  (.1, None, 'Оптимизация точности контуров')]
    if args.mode == 'compact':
        modes += [(.1, (85,2400), 'Сжатие фотографий для экрана'),
                  (.1, (78,1800), 'Уменьшение крупных фотографий')]
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='pdf-light-', dir=output.parent) as directory:
        work = Path(directory)
        best, best_size, best_meta = None, math.inf, None
        for n, (precision, image_options, label) in enumerate(modes):
            emit('progress', message=label+'…')
            candidate = work/f'candidate-{n}.pdf'
            meta = make_candidate(source, candidate, precision, args.repair, image_options)
            size = candidate.stat().st_size
            if size >= best_size:
                continue
            emit('progress', message='Проверяю текст и внешний вид…')
            check = visual_check(source, candidate, bool(meta['images']))
            if not check['ok']:
                emit('progress', message='Этот вариант меняет внешний вид — пропускаю.')
                continue
            best, best_size, best_meta = candidate, size, meta
            if size <= target:
                break
        if best is None:
            raise ValueError('Не удалось получить вариант, прошедший проверку. Оригинал сохранён.')
        # Do not enlarge a document unless a compatibility repair was necessary.
        if best_size >= original_size and best_meta['masks'] == 0:
            best, best_size = source, original_size
            best_meta = {'coordinates':0,'masks':0,'mask_pages':[],'images':0,'precision':0}
        refs = work/'reference'
        refs.mkdir()
        visual_check(source, best, bool(best_meta['images']), refs)
        native = {'checked': False, 'bad_pages': []}
        if args.native_helper:
            emit('progress', message='Проверяю отображение в macOS…')
            native = native_check(args.native_helper, best, refs, work)
        # UI works with a private result; the user chooses the final destination.
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open('xb') as destination, best.open('rb') as src:
            shutil.copyfileobj(src, destination)
        preview = output.with_suffix('.png')
        shutil.copyfile(refs/'page-1.png', preview)
        result = {'input': str(source), 'output': str(output), 'preview': str(preview),
                  'original_bytes': original_size, 'output_bytes': best_size,
                  'pages': len(reader.pages), 'target_bytes': target,
                  'target_met': best_size <= target, 'native': native, **best_meta}
        output.with_suffix('.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
        emit('result', **result)


def main():
    def cancel(signum, frame):
        # Raise through TemporaryDirectory so cancelled jobs remove intermediate PDFs.
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, cancel)
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--target', type=float, default=9)
    parser.add_argument('--mode', choices=['lossless','balanced','compact'], default='balanced')
    parser.add_argument('--repair', action='store_true')
    parser.add_argument('--native-helper')
    args = parser.parse_args()
    try:
        optimize(args)
    except KeyboardInterrupt:
        emit('error', message='Обработка отменена.')
        return 130
    except Exception as error:
        emit('error', message=str(error) or 'Не удалось обработать PDF.')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
