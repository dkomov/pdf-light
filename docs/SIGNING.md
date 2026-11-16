# Developer ID signing and Apple notarization

PDF Light currently ships with an ad-hoc signature. That verifies bundle integrity locally but does not establish the developer identity that Gatekeeper expects for normal distribution. Source availability and the MIT license do not replace signing.

## What the maintainer needs

1. An Apple Account with two-factor authentication and active [Apple Developer Program membership](https://developer.apple.com/help/account/membership/program-enrollment). As of November 2026, Apple lists an annual fee of USD 99, in local currency where available. Check the actual local price and applicable taxes at enrollment. Enrollment and payment are performed by the account owner.
2. A **Developer ID Application** certificate and its private key in the signing Mac’s keychain. See [Apple’s certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates). The Application certificate is the relevant one for an app distributed as ZIP/DMG; an Installer certificate is additionally needed if distributing a signed installer package.
3. Xcode’s signing and notarization tools plus credentials for the notary service. Store those in Keychain or an appropriate secret store, never in the repository or chat.

The Mac App Store is not required. Developer ID and notarization support direct downloads, including GitHub Releases.

## Work required for this app

The current builder always ad-hoc signs; it has not yet been validated with a Developer ID identity. Before switching release distribution:

- Extend the signing stage to sign nested executables, Python extensions and dynamic libraries with the same Developer ID identity, from the inside out, then sign the enclosing app. Use secure timestamps and enable Hardened Runtime where required. Do not use `--deep` as a replacement for explicitly signing nested code.
- Test the bundled CPython/PDFium/Pillow stack under Hardened Runtime. Start without broad runtime exceptions; add only an entitlement demonstrated to be necessary. Do not assume the current ad-hoc smoke test proves hardened-runtime compatibility.
- Verify the signature and run a complete optimization, native rendering, cancellation, saving, theme changes and PayPal-link opening in the signed app.
- Submit an archive with `xcrun notarytool submit ... --keychain-profile ... --wait`. A successful upload is not acceptance: inspect the returned status and resolve every rejection using its log.
- After acceptance, attach the ticket with `xcrun stapler staple 'PDF Light.app'` and validate it with `xcrun stapler validate`. Staple the app before creating the final ZIP; the ticket cannot be stapled directly to a ZIP.
- Repackage, publish new checksums, and test the downloaded/quarantined artifact on a clean Mac. Validate Gatekeeper assessment and offline opening with the stapled ticket. Never reuse checksums from the pre-stapling archive.

See Apple’s [notarization overview](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Successful signing and notarization remove the unidentified-developer obstacle; macOS can still show the ordinary confirmation that an app was downloaded from the internet. Each changed release must be signed and submitted again. Do not disable Gatekeeper globally.
