import io
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import optimizer as opt
from pypdf import PdfWriter, PdfReader
from pypdf.generic import (ArrayObject, BooleanObject, ContentStream, DecodedStreamObject,
                          DictionaryObject, FloatObject, NameObject, NumberObject)
from PIL import Image


def arr(values): return ArrayObject([FloatObject(x) for x in values])


def document(data, width=100, height=100):
    w=PdfWriter(); p=w.add_blank_page(width=width,height=height)
    stream=DecodedStreamObject();stream.set_data(data)
    p[NameObject('/Contents')]=w._add_object(stream)
    p[NameObject('/Resources')]=DictionaryObject()
    return w,p


def mask_state(w,rect=(0,0,100,100), extra=b'', subtype='/Alpha'):
    x0,y0,x1,y1=rect
    g=DecodedStreamObject();g.set_data(f'0 g {x0} {y0} {x1-x0} {y1-y0} re f'.encode()+extra)
    g.update({NameObject('/Subtype'):NameObject('/Form'),NameObject('/BBox'):arr(rect),
              NameObject('/Resources'):DictionaryObject(),
              NameObject('/Group'):DictionaryObject({NameObject('/S'):NameObject('/Transparency')})})
    return DictionaryObject({NameObject('/SMask'):DictionaryObject({NameObject('/S'):NameObject(subtype),NameObject('/G'):w._add_object(g)})})


class SafetyTests(unittest.TestCase):
    def test_strings_comments_and_text_are_opaque(self):
        data=b'q\n% 1.234 5.678 m\nBT (1.234 5.678 m\n\\(nested\\)) Tj [1.234 (5.678 l)] TJ ET\n1.234 5.678 m 9.876 3.456 l S Q'
        w,p=document(data); n,m=opt.rewrite_page(p,w,.1,False)
        out=p.get_contents().get_data()
        self.assertGreater(n,0)
        self.assertIn(b'(1.234 5.678 m\n\\(nested\\))',out)
        self.assertIn(b'[1.234 (5.678 l)]',out)
        self.assertIn(b'% 1.234 5.678 m',out)
        self.assertIn(b'1.2 5.7 m',out)

    def test_inline_images_are_skipped(self):
        data=b'1.234 2.345 m BI /W 1 /H 1 ID abc EI 8.987 3.456 l'
        w,p=document(data); self.assertEqual(opt.rewrite_page(p,w,.1,True),(0,0))
        self.assertEqual(p.get_contents().get_data(),data)

    def test_scaled_geometry_bound(self):
        w,p=document(b'q 100 0 0 100 0 0 cm 1.23456 2.34567 m 3.45678 4.56789 l S Q')
        opt.rewrite_page(p,w,.1,False)
        ops=p.get_contents().operations
        coords=[float(n) for a,o in ops if o in (b'm',b'l') for n in a]
        for a,b in zip(coords,[1.23456,2.34567,3.45678,4.56789]):
            self.assertLessEqual(abs(a-b)*100,.050001)

    def test_full_mask_only(self):
        for rect,subtype,expect in [((0,0,100,100),'/Alpha',1),((0,0,50,50),'/Alpha',0),((0,0,100,100),'/Luminosity',0)]:
            w,p=document(b'q /Mask gs 0 0 100 100 re f Q')
            state=mask_state(w,rect,subtype=subtype)
            p['/Resources'][NameObject('/ExtGState')]=DictionaryObject({NameObject('/Mask'):w._add_object(state)})
            _,n=opt.rewrite_page(p,w,0,True)
            self.assertEqual(n,expect)

    def test_scaled_mask_coverage(self):
        w,p=document(b'q .1 0 0 .1 0 0 cm /Mask gs Q')
        state=mask_state(w,(0,0,1000,1000))
        p['/Resources'][NameObject('/ExtGState')]=DictionaryObject({NameObject('/Mask'):w._add_object(state)})
        self.assertEqual(opt.rewrite_page(p,w,0,True)[1],1)

    def test_nontrivial_mask_is_preserved(self):
        w,p=document(b'/Mask gs')
        state=mask_state(w,extra=b' .5 g 0 0 20 20 re f')
        self.assertIsNone(opt.opaque_mask_rect(state,w))

    def test_other_state_properties_preserved(self):
        w,p=document(b'/Mask gs')
        state=mask_state(w);state[NameObject('/ca')]=FloatObject(.5)
        p['/Resources'][NameObject('/ExtGState')]=DictionaryObject({NameObject('/Mask'):w._add_object(state)})
        opt.rewrite_page(p,w,0,True)
        new=p['/Resources']['/ExtGState']['/PDFLightMask1'].get_object()
        self.assertEqual(new['/ca'],.5);self.assertEqual(new['/SMask'],'/None')

    def test_image_alpha_mask_not_recompressed(self):
        w,p=document(b'')
        buffer=io.BytesIO();Image.effect_noise((1000,1000),100).save(buffer,format='JPEG',quality=95)
        mask=DecodedStreamObject();mask._data=buffer.getvalue()
        mask.update({NameObject('/Subtype'):NameObject('/Image'),NameObject('/Filter'):NameObject('/DCTDecode'),NameObject('/ColorSpace'):NameObject('/DeviceGray'),NameObject('/BitsPerComponent'):NumberObject(8)})
        mask_ref=w._add_object(mask)
        parent=DictionaryObject({NameObject('/SMask'):mask_ref});w._add_object(parent)
        old=mask._data;opt.compress_images(w,78,1800)
        self.assertEqual(old,mask._data)

    def test_rotation_crop_and_annotations_preserved(self):
        with tempfile.TemporaryDirectory() as d:
            source=Path(d)/'in.pdf';out=Path(d)/'out.pdf'
            w,p=document(b'0 g 20.1234 20.3456 m 60.5678 50.9876 l S')
            p.rotate(90);p.cropbox.lower_left=(10,10)
            w.write(source);opt.make_candidate(source,out,.05,True)
            a,b=PdfReader(source),PdfReader(out)
            self.assertEqual(a.pages[0].rotation,b.pages[0].rotation)
            self.assertEqual(a.pages[0].cropbox,b.pages[0].cropbox)
            self.assertTrue(opt.visual_check(source,out,False)['ok'])


if __name__=='__main__': unittest.main()
