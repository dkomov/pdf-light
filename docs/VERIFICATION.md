# Verification records

## 1.3.0

Local release preparation on 2026-11-16, Apple Silicon macOS:

- The 13 Python tests, lint/format checks, standalone build, isolated dependency imports, native localization self-test and deep signature verification passed.
- System appearance was the initial default. Light and Dark switches updated a loaded result immediately while retaining the PDF's page colors and optimization results.
- All seven languages localized the appearance picker while preserving its selection. Dark persisted after quitting and reopening the app. System appearance was restored at the end. Live changes to the operating system's global theme were not exercised.
- The synthetic demo was optimized and saved through the native dialog. The thanks button remained at the lower left and Save a copy at the lower right, with Show in Finder between them after saving.
- Screenshots show actual synthetic-demo results. The initial 1.3.0 cover used illustrative figures. A subsequent documentation correction replaced them with the measured prototype result, 12.01 MB → 8.39 MB; exact byte counts are in STORY.md.

## 1.1.0

Local release preparation, 2026-11-16, Apple Silicon macOS. This record describes observed checks, not a certification of all PDF features.

- 13 automated Python tests passed, including seven-language error checks and PDF transformation regressions.
- Python lint/format checks and Swift formatting lint passed.
- The native self-test passed preferred-language matching and decimal separator cases.
- A standalone app was built with public uv-managed CPython 3.12.14 and the pinned libraries. Isolated imports and deep code-signature verification passed.
- The bundle was copied to a separate path and ran with an empty inherited environment except PATH. Its bundled worker and native renderer processed the demo; bundle signature verification still passed afterwards.
- All seven UI languages were inspected with a completed result. Long labels and CJK text fit the window at its default size. Language switching updated a loaded result without a restart; System language was restored afterwards.
- A fresh launch of the final bundle opened the demo, accepted a comma target value, optimized the document, and saved a separate copy through the native dialog.
- The generated one-page demo changed from 122,253 to 46,021 bytes with a 0.1 MB target in Balanced mode. Extracted text, PDFium comparison and native rendering checks passed. This deliberately vector-heavy synthetic example is not a general performance benchmark.

The public source contains no original user PDFs. Tests generate their own samples. The screenshot artwork comes from `scripts/make_demo.py`.

GitHub-hosted CI results are available on the repository's Actions page after publication. Local checks alone do not establish that a remote workflow has passed. The distributed build is ad-hoc signed, not Apple-notarized. Minimum-supported macOS 14 and Intel hardware have not both been tested; Intel is unsupported.
