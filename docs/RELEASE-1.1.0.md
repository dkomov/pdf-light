# PDF Light 1.1.0

The first public release of a small, local PDF optimizer for macOS.

- Native drag and drop, original/result preview, target size and Save a copy.
- Lossless data compression, bounded vector-coordinate optimization, and optional JPEG compression for screens.
- Conservative repair of redundant full-page opaque masks; text, page appearance and macOS rendering checks.
- Automatic system-language selection and instant switching between English, Russian, German, French, Spanish, Japanese and Simplified Chinese.
- MIT-licensed source, build instructions, architecture and algorithm documentation, project story, contribution guidelines and regression tests.

**Requirements:** Apple Silicon, macOS 14 or newer. Python and dependencies are bundled. No document uploads or account required.

**Installation:** unzip the macOS archive and move PDF Light.app to Applications. This build is ad-hoc signed and **not Apple-notarized**; macOS may ask for explicit approval to open it. Source builds are supported. See the README for instructions.

**Validation:** 13 local automated tests, Swift/Python style checks, native localization self-test, standalone/relocation checks, and seven-language UI review. A generated demo was optimized and saved through the app. See docs/VERIFICATION.md for scope and limitations.

Target size is not guaranteed. Checks are heuristic and do not certify PDF/A, PDF/X, print output or interactive features. Keep the original and review important results in their intended viewer.

Verify downloaded files against SHA256SUMS.txt. Third-party license notices are included in the app. No private PDFs are included in source or release assets.
