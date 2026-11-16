"""Build a standalone arm64 macOS app using an explicit, relocatable Python runtime."""

import argparse
import platform
import plistlib
import shutil
import subprocess
from pathlib import Path

VERSION = "1.3.0"
LANGUAGES = ["en", "ru", "de", "fr", "es", "ja", "zh-Hans"]


def copy_licenses(runtime, resources, root):
    licenses = resources / "Licenses"
    licenses.mkdir(exist_ok=True)
    stdlib = runtime / "lib/python3.12"
    shutil.copy2(stdlib / "LICENSE.txt", licenses / "Python.txt")
    for pattern, name in [
        ("pypdf-*.dist-info", "pypdf"),
        ("pillow-*.dist-info", "Pillow"),
        ("pypdfium2-*.dist-info", "PDFium"),
    ]:
        metadata = next((stdlib / "site-packages").glob(pattern), None)
        source = metadata / "licenses" if metadata else root / "Licenses" / name
        if not source.exists():
            raise RuntimeError(f"Missing third-party license: {name}")
        shutil.copytree(source, licenses / name, dirs_exist_ok=True)
    shutil.copy2(root / "LICENSE", resources / "LICENSE")
    shutil.copy2(root / "THIRD_PARTY_NOTICES.md", resources / "THIRD_PARTY_NOTICES.md")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--output", type=Path, default=Path("dist/PDF Light.app"))
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("This release builds on Apple Silicon macOS only.")
    root = Path(__file__).resolve().parent
    runtime = args.runtime
    if runtime is None:
        prefix_file = root / ".runtime/prefix.txt"
        if not prefix_file.exists():
            parser.error("Run scripts/prepare_runtime.py first, or supply --runtime.")
        runtime = Path(prefix_file.read_text().strip())
    runtime = runtime.resolve()
    app = args.output.resolve()
    if app.suffix != ".app":
        parser.error("--output must end with .app")
    if app.exists():
        info = app / "Contents/Info.plist"
        existing = plistlib.loads(info.read_bytes()) if info.exists() else {}
        if existing.get("CFBundleIdentifier") not in (
            "com.dkomov.pdflight",
            "local.pdflight.desktop",
        ):
            parser.error("Refusing to replace an unrelated directory or application.")
        shutil.rmtree(app)
    contents = app / "Contents"
    macos, resources = contents / "MacOS", contents / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    subprocess.run(
        [
            "swiftc",
            "-swift-version",
            "5",
            "-O",
            "-target",
            "arm64-apple-macos14.0",
            "-module-cache-path",
            str(root / "build/module-cache"),
            "-framework",
            "AppKit",
            "-framework",
            "PDFKit",
            "-framework",
            "Quartz",
            "-framework",
            "ImageIO",
            str(root / "src/Localization.swift"),
            str(root / "src/main.swift"),
            "-o",
            str(macos / "PDFLight"),
        ],
        check=True,
    )
    python = resources / "Python"
    (python / "bin").mkdir(parents=True)
    (python / "lib").mkdir()
    shutil.copy2(runtime / "bin/python3.12", python / "bin/python3.12")
    # python-build-standalone may link the interpreter against a sibling libpython.
    for library in (runtime / "lib").glob("*.dylib"):
        shutil.copy2(library, python / "lib" / library.name, follow_symlinks=True)
    ignore = shutil.ignore_patterns(
        "site-packages",
        "__pycache__",
        "*.pyc",
        "test",
        "tests",
        "idlelib",
        "tkinter",
        "turtledemo",
        "ensurepip",
        "config-*",
    )
    stdlib = runtime / "lib/python3.12"
    shutil.copytree(stdlib, python / "lib/python3.12", ignore=ignore)
    packages = python / "lib/python3.12/site-packages"
    packages.mkdir()
    for name in ["pypdf", "PIL", "pypdfium2", "pypdfium2_raw", "pypdfium2_cfg"]:
        shutil.copytree(
            stdlib / "site-packages" / name,
            packages / name,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )
    shutil.copy2(root / "src/optimizer.py", resources / "optimizer.py")
    shutil.copytree(root / "locales", resources / "locales")
    shutil.copy2(root / "AppIcon.icns", resources / "AppIcon.icns")
    copy_licenses(runtime, resources, root)
    info = {
        "CFBundleName": "PDF Light",
        "CFBundleDisplayName": "PDF Light",
        "CFBundleIdentifier": "com.dkomov.pdflight",
        "CFBundleExecutable": "PDFLight",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "4",
        "CFBundleShortVersionString": VERSION,
        "LSMinimumSystemVersion": "14.0",
        "NSHighResolutionCapable": True,
        "CFBundleIconFile": "AppIcon",
        "NSPrincipalClass": "NSApplication",
        "CFBundleDevelopmentRegion": "en",
        "CFBundleLocalizations": LANGUAGES,
        "CFBundleAllowMixedLocalizations": True,
        "CFBundleDocumentTypes": [
            {
                "CFBundleTypeName": "PDF document",
                "CFBundleTypeRole": "Viewer",
                "LSHandlerRank": "Alternate",
                "LSItemContentTypes": ["com.adobe.pdf"],
            }
        ],
        "NSHumanReadableCopyright": "Copyright © 2026 dkomov. MIT license. Third-party notices included.",
    }
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump(info, stream)
    (contents / "PkgInfo").write_text("APPL????")
    for cache in python.rglob("__pycache__"):
        shutil.rmtree(cache)
    for path in sorted(python.rglob("*")):
        if path.is_file() and (path.suffix in (".so", ".dylib") or path.name == "python3.12"):
            subprocess.run(
                ["codesign", "--force", "--sign", "-", str(path)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    subprocess.run([str(macos / "PDFLight"), "--localization-self-test"], check=True)
    # No inherited PYTHONPATH and no bytecode writes into the signed bundle.
    subprocess.run(
        [
            str(python / "bin/python3.12"),
            "-I",
            "-B",
            "-c",
            "import pypdf, PIL, pypdfium2; print('Bundled dependencies: passed')",
        ],
        check=True,
    )
    print(app)


if __name__ == "__main__":
    main()
