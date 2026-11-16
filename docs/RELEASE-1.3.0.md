# PDF Light 1.3.0

- Add dark and light appearance with **System theme** as the default. The picker in the preview header switches instantly and remembers your choice.
- Keep PDF pages in their original colors; only the app interface and viewer surround change appearance.
- Move **Say thanks** into a regular button at the lower left of the result panel, opposite **Save a copy** on the same baseline.
- Translate appearance controls into all seven languages.
- Document the requirements for Developer ID signing and Apple notarization.
- Refresh the GitHub cover with an explicitly illustrative 13.8 MB → 8.5 MB example, alongside genuine light/dark app screenshots.

**Validation:** 13 Python tests, Python and Swift style checks, standalone build and signature verification. Manual checks covered light/dark switching with a loaded PDF, all seven UI languages, saved theme preference after restart, and saving a separate PDF copy. PDF page colors remained unchanged.

**Requirements:** Apple Silicon, macOS 14 or newer. Unzip the macOS archive and replace your previous PDF Light.app.

**Signing:** this release is still ad-hoc signed, not Apple-notarized. No paid Apple enrollment or certificate issuance is included in this update.

Source remains MIT licensed. SHA-256 checksums accompany the release assets.
