# Development and releases

## Prerequisites

- Apple Silicon Mac, macOS 14 or newer.
- Apple's Command Line Tools (`xcode-select --install`) or Xcode, providing Swift, SDKs, and codesign.
- [uv](https://docs.astral.sh/uv/getting-started/installation/).
- Internet access during dependency setup. Running the packaged app is offline.

Clone the repository, then run commands from its root:

```sh
git clone https://github.com/dkomov/pdf-light.git
cd pdf-light
uv run --python 3.12.14 --no-project python scripts/prepare_runtime.py
uv run --python 3.12.14 --no-project python build_app.py
open 'dist/PDF Light.app'
```

`prepare_runtime.py` downloads a project-local managed CPython using uv, installs the versions in `requirements.txt`, and records its prefix in `.runtime/prefix.txt`. `build_app.py` reads that prefix, compiles Swift, copies the runtime/libraries/catalogs/licenses, ad-hoc signs the result, and verifies the bundle and its isolated imports. You may supply `--runtime /absolute/prefix` and `--output '/path/PDF Light.app'` explicitly. An existing recognized PDF Light bundle at the output path is replaced.

Versions of direct Python dependencies are pinned. This is a repeatable source build, **not a claim of byte-for-byte reproducible binaries**: SDKs, compiler, uv-managed Python distributions, signing and timestamps can differ. Record these versions when making releases. The project deliberately has no `.env.example`: it has no API keys or service configuration.

## Tests and style

```sh
uv venv --python 3.12.14
uv pip install -r requirements-dev.txt
uv run --no-project python -B -m unittest discover -s tests -v
uv run --no-project ruff check .
uv run --no-project ruff format --check .
xcrun swift-format lint --strict src/*.swift
'dist/PDF Light.app/Contents/MacOS/PDFLight' --localization-self-test
```

To format edits, run `ruff check --fix .`, `ruff format .`, and `xcrun swift-format format -i src/*.swift`. CI tests the worker on Linux and builds the native app on an arm64 macOS runner. Native UI interactions are currently manually verified, not covered by automated UI tests.

Tests use generated PDFs. They cover string/comment boundaries, inline images, transformed geometry, alpha-mask boundaries and other graphics-state properties, image masks, rotated/cropped pages, matching translation keys/placeholders, and localized worker errors. Add a regression test when changing those boundaries.

## Integration check

```sh
uv run --no-project python scripts/make_demo.py build/demo.pdf
uv run --no-project python src/optimizer.py \
  --input build/demo.pdf --output build/demo-result.pdf \
  --target 0.1 --mode balanced --repair \
  --native-helper 'dist/PDF Light.app/Contents/MacOS/PDFLight'
```

The demo is original vector artwork with live text, intentionally overprecise coordinates, and no private data. Its generator refuses to overwrite an existing output. The worker writes a PDF plus adjacent JSON and PNG; use an unused output basename. Test other modes, targets that cannot be reached, cancellation, failed files, and Save a copy. Visually compare every page of representative documents; passing automated checks is not enough for algorithm changes.

## Release checklist

1. Update version in `build_app.py`, the About panel in `src/main.swift`, bundle build number, and `CHANGELOG.md`.
2. Review dependency changes and their licenses; build from a clean runtime. `build_app.py` fails if required license files are missing.
3. Run tests, style checks, native self-test, and end-to-end integration checks. Check all seven UI languages, including long labels, error states, and comma input.
4. Copy the `.app` to a different path. Run its bundled Python with `-I -B` and a clean environment; optimize the generated demo. Verify `codesign --verify --deep --strict` afterwards. Bytecode must not modify a signed bundle.
5. Archive with macOS `ditto -c -k --sequesterRsrc --keepParent 'dist/PDF Light.app' dist/PDF-Light-<version>-macOS-arm64.zip`. Record `shasum -a 256` in `SHA256SUMS.txt`.
6. Tag the tested commit and create a GitHub release containing the archive, checksum, changes, platform requirements, and explicit signing/notarization status. Never include a private PDF, environment directory, credential, or diagnostic report containing user paths.
7. Verify the remote source, workflow results, download contents, and checksum before announcing the release.

Developer ID signing and Apple notarization require the maintainer's credentials and are not automated by this repository. Do not commit certificates, tokens, provisioning data, or passwords.
