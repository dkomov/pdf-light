"""Bundle a relocatable CPython runtime and native executable into a macOS app."""
from pathlib import Path
import argparse
import os
import plistlib
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--runtime', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).parent
app = args.output.resolve()
contents = app/'Contents'
macos, resources = contents/'MacOS', contents/'Resources'
macos.mkdir(parents=True, exist_ok=True)
resources.mkdir(exist_ok=True)
subprocess.run(['swiftc','-swift-version','5','-O','-target','arm64-apple-macos14.0',
                '-module-cache-path',str(root/'build/module-cache'),'-framework','AppKit',
                '-framework','PDFKit','-framework','Quartz','-framework','ImageIO',
                str(root/'src/main.swift'),'-o',str(macos/'PDFLight')],check=True)
python = resources/'Python'
(python/'bin').mkdir(parents=True, exist_ok=True)
shutil.copy2(args.runtime/'bin/python3.12',python/'bin/python3.12')
stdlib = args.runtime/'lib/python3.12'
ignore = shutil.ignore_patterns('site-packages','__pycache__','*.pyc','test','tests','idlelib','tkinter','turtledemo','ensurepip','config-*')
shutil.copytree(stdlib,python/'lib/python3.12',dirs_exist_ok=True,ignore=ignore)
packages = python/'lib/python3.12/site-packages'
packages.mkdir(exist_ok=True)
for package in ['pypdf','PIL','pypdfium2','pypdfium2_raw','pypdfium2_cfg']:
    shutil.copytree(stdlib/'site-packages'/package,packages/package,dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
shutil.copy2(root/'src/optimizer.py',resources/'optimizer.py')
licenses = resources/'Licenses'; licenses.mkdir(exist_ok=True)
shutil.copy2(stdlib/'LICENSE.txt',licenses/'Python.txt')
for pattern, name in [('pypdf-*.dist-info','pypdf'),('pillow-*.dist-info','Pillow'),('pypdfium2-*.dist-info','PDFium')]:
    metadata = next((stdlib/'site-packages').glob(pattern), None)
    source = metadata/'licenses' if metadata else root/'Licenses'/name
    if source.exists():
        shutil.copytree(source,licenses/name,dirs_exist_ok=True)
    else:
        raise RuntimeError(f'Missing license for {name}')
info = {
    'CFBundleName':'PDF Light','CFBundleDisplayName':'PDF Light',
    'CFBundleIdentifier':'local.pdflight.desktop','CFBundleExecutable':'PDFLight',
    'CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0',
    'LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,
    'CFBundleIconFile':'AppIcon','NSPrincipalClass':'NSApplication',
    'CFBundleDocumentTypes':[{'CFBundleTypeName':'PDF document','CFBundleTypeRole':'Viewer',
                            'LSHandlerRank':'Alternate','LSItemContentTypes':['com.adobe.pdf']}],
    'NSHumanReadableCopyright':'PDF Light — personal local utility. Third-party licenses in Resources/Licenses.'
}
with (contents/'Info.plist').open('wb') as out: plistlib.dump(info,out)
(contents/'PkgInfo').write_text('APPL????')
icon = root/'build/AppIcon.icns'
if icon.exists(): shutil.copy2(icon,resources/'AppIcon.icns')
for cache in python.rglob('__pycache__'):
    shutil.rmtree(cache)
# Ad-hoc signatures make a locally built bundle consistent. No Apple notarization is claimed.
for path in sorted(python.rglob('*')):
    if path.is_file() and (path.suffix in ('.so','.dylib') or path.name=='python3.12'):
        subprocess.run(['codesign','--force','--sign','-',str(path)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(app)
