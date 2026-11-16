# Security policy

## Supported versions

Security fixes target the latest published release. Older local prototypes are not maintained separately.

## Reporting

Please do not post exploit details or confidential PDFs in a public issue. If the repository's **Security → Report a vulnerability** option is available, use it. Otherwise contact the maintainer through the contact options on [dkomov's public profile](https://github.com/dkomov) to arrange a private report. A harmless synthetic reproducer is preferred.

Include affected versions, platform, impact, reproduction steps and any proposed mitigation. This volunteer project does not promise a response time or offer a bug bounty.

## Boundaries

PDF Light operates locally and has no document upload, analytics, update telemetry, or service credentials. Dependency setup and GitHub release downloads use the network; document processing does not.

The app is not App Sandbox-confined. It invokes native PDF parsers and image decoders with the current user's privileges, so it is not a safe environment for deliberately hostile documents. Visual checks detect certain rendering changes; they are not malware inspection, sanitization, or proof that PDF JavaScript and attachments are absent.

Input paths, output paths and technical diagnostics may appear in local reports. Temporary files are not encrypted or securely erased by the app, and a crash can leave them behind. The output can retain original metadata and attachments. Do not treat optimization as redaction or privacy scrubbing.

The initial distributed app is ad-hoc signed and is not notarized by Apple. The build verifies bundle integrity, but ad-hoc signing does not establish developer identity. Review source, download from this repository's releases, and verify published checksums. Never disable macOS security protections globally to run the app.

## Maintenance

Pinned dependencies and SHA-pinned GitHub Actions are reviewed through pull requests. CI receives read-only repository permissions and does not publish releases or receive signing credentials. No secrets or credentials belong in the source tree.
