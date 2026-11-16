# PDF Light 1.2.0

A small update for anyone who wants to support the project.

- Add an optional **Say thanks** heart button at the bottom of the app and in the PDF Light menu.
- Translate the button and its explanatory tooltip into all seven languages.
- Open the author’s PayPal donation page in the default browser when clicked. No payment is initiated by the app.
- Add support links to the English/Russian READMEs and GitHub sponsor button.

All features remain free. PDF optimization, local processing and original-file protection are unchanged.

**Requirements:** Apple Silicon, macOS 14 or newer. Download the macOS archive, unzip it and replace your previous PDF Light.app. Python and dependencies are bundled.

**Signing:** ad-hoc signed, not Apple-notarized. macOS may require explicit approval on first launch; see the README.

Release archives include SHA-256 checksums. Source remains available under MIT.

Validation: 13 regression/localization tests passed, along with Swift/Python style checks and the standalone build checks. The button, translated tooltips and app menu were checked in the UI; clicking opened the supplied PayPal page.
