# Contributing to PDF Light

Small, focused improvements are welcome: reproducible PDF bugs, clearer UI, translations, documentation, and careful compression changes.

Before starting a larger feature, open an issue to agree on its scope. See [Development](docs/DEVELOPMENT.md) for setup and validation, and [Algorithms](docs/ALGORITHMS.md) before changing the worker.

## Issues

Describe your macOS version, Mac architecture, app version, compression mode, target, repair setting, expected result, and actual result. A small synthetic PDF that reproduces the behavior is much more useful than a screenshot alone. Do not upload confidential documents or logs containing private paths. Report security issues as described in [SECURITY.md](SECURITY.md).

## Pull requests

- Keep a pull request focused on one coherent change. Explain the trigger, resulting behavior, and checks performed.
- Follow the existing Swift and Python formatting; run tests and linters.
- For algorithm changes, include a generated regression fixture and before/after rendering evidence. Do not relax a safety threshold simply to make a failing fixture pass.
- For UI changes, check English, German/French, Russian, Japanese and Chinese, and the minimum window size. Preserve accessibility labels and keyboard use.
- Keep user-visible prose in the catalogs. Preserve placeholders in every language.
- Do not commit build output, virtual environments, local PDF documents, secrets, or personal data.

Use English commit messages with a consistent [Conventional Commits](https://www.conventionalcommits.org/) style, for example `fix: preserve masked images in compact mode` or `docs: explain target size limits`. Prefer clear messages over a large number of tiny commits. Do not rewrite shared history without coordination.

By contributing, you agree that your contribution is provided under this project's MIT license. Third-party material must have a compatible license and attribution. AI-assisted changes are welcome, but contributors remain responsible for understanding, testing, and reviewing them. State material limitations honestly.
