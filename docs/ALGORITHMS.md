# Optimization and its boundaries

The governing rule is: retain the original, make candidates, and reject changes that fail the implemented checks. These checks are useful evidence, not proof of complete PDF equivalence.

## Candidate selection

Each candidate is produced independently from the original. Strategies are tried in this order:

| Strategy | Path rounding step limit | Photo handling |
| --- | --- | --- |
| Lossless | None | Unchanged |
| Balanced, first pass | 0.05 pt in page space | Unchanged |
| Balanced, second pass | 0.1 pt in page space | Unchanged |
| Compact, first photo pass | 0.1 pt | JPEG quality 85, maximum dimension 2400 px |
| Compact, second photo pass | 0.1 pt | JPEG quality 78, maximum dimension 1800 px |

Lossless mode tries only the first strategy; Balanced tries the first three; Compact tries all five. Only a candidate smaller than the current best is checked. The search stops after an accepted result reaches the target. The returned result is therefore not a global minimum. If no size benefit is achieved and no mask repair was necessary, the original bytes are copied instead. A compatibility repair may justify a larger result.

pypdf clones the document, recompresses content streams and plain Flate streams at zlib level 9, and deduplicates/removes unreferenced objects. Other filters and predictor settings are not indiscriminately rewritten. This is a new serialization; it is not byte-preserving or signature-preserving.

## Vector precision

Pixel snapping in a design tool controls editing coordinates. A PDF can still contain long decimals after unit conversion, nested transforms, vector generation, and export. That does not establish that a designer outlined text or placed objects carelessly.

A lexical parser treats literal strings, hex strings and comments as opaque. Only operands of path construction operators `m`, `l`, `c`, `v`, `y`, and `re` are candidates. Text sections are excluded. Content streams with inline images or lexical errors are skipped. Font/glyph streams and nested Form XObjects are not traversed for this optimization.

The worker tracks `q`, `Q` and `cm`, and accounts for `/UserUnit`. It chooses a short decimal step from 1/2/5 times a power of ten, bounded by the requested page-space tolerance divided by the transform's maximum absolute row sum. A coordinate is replaced only when its spelling becomes shorter. Paths whose transform changes mid-path are conservatively skipped where detected. Rounding can alter geometry slightly; it never reduces the vertex count or simplifies curves. The second rendering check constrains the accepted result further.

For an ordinary point, rounding error is at most half the selected step per axis before transformation. Rectangle far edges combine origin and dimension rounding; the advertised tolerance is the conservative full step. This is a numerical bound for recognized operands, not a guarantee of perceptual equivalence at arbitrary zoom or print resolution.

## Redundant mask repair

Some exports use a soft alpha mask that is fully opaque across an entire page. It should have no visible effect but can interact badly with native rendering. PDF Light only considers a mask when:

- `/S` is `/Alpha`, and the transfer function is absent or `/Identity`.
- Its group is a transparency Form with an identity matrix and no nonempty resources.
- The content is a simple filled rectangle (or its four axis-aligned corners), optionally preceded by a solid color setting.
- The rectangle exactly matches the group `/BBox`.
- Under the active axis-aligned transform, it covers the page's MediaBox.

The worker creates a separate graphics-state entry with `/SMask /None` and redirects that invocation, retaining the state's other properties. It does not flatten transparency or remove arbitrary masks. Partial, luminosity, artistic, transformed/sheared, and more complex masks are left alone. The original/result comparison must still pass. This repair is optional, including in Lossless mode.

## Photos

Compact mode only considers direct DCT/JPEG image streams with DeviceRGB or DeviceGray, 8 bits per component, and at least 80 KB of compressed data. Images with masks, custom decode settings or stencil-image flags are excluded, as are streams used as image masks. Pillow recompresses eligible images with 4:4:4 JPEG and optional downsampling. A replacement must save at least 10% of that stream's bytes.

Other formats, ICC-based images, CMYK JPEGs, and masked photographs are currently skipped. There is no target-DPI estimation based on placed image size. Compact mode is for screens and may visibly change photos.

## Validation

Every checked candidate must have the same page count, page dimensions, extracted text (PDFium), and per-page annotation count. Each page is rasterized by PDFium at a maximum of 1200 pixels on its longest side, never upscaled beyond one pixel per PDF point. RGB absolute differences are measured:

| Check | Vector/data candidate | Candidate with changed images |
| --- | --- | --- |
| Maximum page mean channel difference (0–255) | 1.0 | 3.0 |
| Fraction of pixels with luminance difference ≥49 | 0.008 | 0.025 |

CoreGraphics independently renders the selected result. Its images are resized to match the reference, reduced to at most 400×400, blurred with radius 1, and compared. Mean channel difference above 8 flags a page. Rendering disagreement is shown as a review warning, not silently presented as a passing native check.

This does **not** fully validate bookmarks, tags, form field values/actions, attachment contents, accessibility, overprinting, fonts, color profiles or archival/press standards. Matching extracted text is weaker than validating reading order and font semantics. Annotation counts do not prove annotation equivalence. Review sensitive documents in their intended viewer, at the intended zoom and output conditions.
