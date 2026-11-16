# Third-party software

PDF Light's original application code is licensed under MIT. That license does not replace the licenses of bundled dependencies.

| Component | Pinned version | License / upstream |
| --- | --- | --- |
| CPython | 3.12.14 | [PSF License](https://docs.python.org/3/license.html) |
| pypdf | 6.21.4 | [BSD-3-Clause](https://github.com/py-pdf/pypdf/blob/main/LICENSE) |
| Pillow | 13.0.0 | [HPND and bundled codec notices](https://github.com/python-pillow/Pillow/blob/main/LICENSE) |
| pypdfium2 | 5.13.0 | [Apache-2.0 / BSD-3-Clause options and PDFium notices](https://github.com/pypdfium2-team/pypdfium2/blob/main/LICENSES/README.md) |
| PDFium | Version shipped by pypdfium2 5.13.0 | BSD-style license and third-party notices included by the distribution |

The build copies the **actual license files from the installed distributions** into `PDF Light.app/Contents/Resources/Licenses`. Pillow and PDFium include additional third-party notices; keep those directories intact when redistributing the app. Builds fail if a required license directory is missing.

Swift's system frameworks are provided by macOS. Build tools such as uv and Ruff are not bundled into the application. The app icon and synthetic demonstration artwork were created for PDF Light and are covered by the project license.
