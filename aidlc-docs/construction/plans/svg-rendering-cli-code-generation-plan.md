# Code Generation Plan - Unit 3: SVG Rendering & CLI

This plan covers the first visual SVG increment. It prioritizes visible output over complete font technology coverage.

## Unit Context

- **Unit**: SVG Rendering & CLI
- **Primary story**: US-4 - テキストのアウトライン出力 (SVG Path)
- **Related story**: US-5 - CLIインターフェースの提供
- **Dependencies**: Unit 1 `Face`, Unit 2 `ShapeEngine`
- **Application code paths**:
  - `src/svg_renderer.zig`
  - `src/root.zig`
  - `src/main.zig`

## Execution Checklist

- [x] Step 1: Add SVG renderer module
  - Define `SvgRenderer` and `SvgError`.
  - Render shaped text to an SVG document string.

- [x] Step 2: Extract simple TrueType outlines
  - Read `head.indexToLocFormat`.
  - Read `loca` offsets.
  - Read simple `glyf` contours.
  - Decode flags, x coordinates, y coordinates, on-curve points, and quadratic off-curve points.

- [x] Step 3: Generate SVG paths
  - Emit `M`, `L`, `Q`, and `Z` path commands.
  - Use shaped glyph `x_offset` for placement.
  - Use SVG group transform to display font Y-up coordinates.

- [x] Step 4: Add CLI output option
  - Add `--output <svg-file>`.
  - Write SVG when both `--text` and `--output` are supplied.

- [x] Step 5: Verification
  - Run `zig build test`.
  - Run `zig build`.
  - Generate `/tmp/zig-font-renderer-av.svg` from DejaVuSans and text `AV`.

- [x] Step 6: Add composite glyph expansion
  - Decode component records in composite TrueType glyphs.
  - Support XY offset component placement.
  - Recursively emit component paths with bounded recursion.
  - Initially rejected point-matched or transformed components that were not yet supported.

- [x] Step 7: Add SVG sizing controls
  - Add renderer `RenderOptions`.
  - Emit SVG `width`, `height`, and pixel-space `viewBox`.
  - Add CLI `--font-size <px>`.
  - Suppress metadata output when writing SVG files.

- [x] Step 8: Add bounds-based SVG layout
  - Read glyph header bounds from `glyf`.
  - Combine shaped glyph bounds into text bounds.
  - Use bounds to compute SVG width, height, and baseline translation.
  - Preserve advance width in output bounds where it exceeds visible outline bounds.

- [x] Step 9: Add high-level render API
  - Add `renderToSvg(allocator, font_path, text, options)`.
  - Add `RenderToSvgOptions`.
  - Re-export high-level API from `src/root.zig`.
  - Route CLI SVG output through the high-level API.

- [x] Step 10: Add SVG styling controls
  - Add renderer `fill` and optional `background` options.
  - Add CLI `--margin <px>`, `--fill <color>`, and `--background <color>`.
  - Validate margin values as finite non-negative numbers.
  - Reject SVG color strings that can break attribute syntax.

- [x] Step 11: Add transformed composite glyph rendering
  - Decode composite glyph F2Dot14 scale values.
  - Support uniform scale, separate XY scale, and 2x2 component transforms.
  - Compose nested component transforms before emitting path coordinates.
  - Preserve explicit rejection for point-matched composite components until point attachment is implemented.

- [x] Step 12: Add explicit CFF outline unsupported handling
  - Detect `CFF ` and `CFF2` tables when `glyf` is absent.
  - Return `UnsupportedCffOutlines` instead of generic missing-table errors.
  - Keep CFF charstring outline decoding deferred.

- [x] Step 13: Add CFF charstring foundation
  - Parse CFF INDEX structures.
  - Read Top DICT `CharStrings` offset.
  - Retrieve per-glyph Type 2 charstrings by glyph ID.
  - Emit SVG for basic Type 2 moveto, lineto, and rrcurveto operators.
  - Return `UnsupportedCffOperator` for subroutines and advanced Type 2 operators.

- [x] Step 14: Add CFF subroutine expansion
  - Read Top DICT `Private` data.
  - Read Private DICT local `Subrs` offset.
  - Expand Type 2 `callsubr` and `callgsubr` with standard subroutine bias.
  - Bound subroutine recursion depth.
  - Verify visible SVG output from an OTF/CFF font.

- [x] Step 15: Add common advanced Type 2 operators
  - Skip Type 2 hint masks while preserving charstring stream alignment.
  - Support `hhcurveto`, `vvcurveto`, `hvcurveto`, and `vhcurveto`.
  - Support `rcurveline` and `rlinecurve`.
  - Verify multiple CFF glyphs from an OTF font render to visible SVG.

- [x] Step 16: Add Type 2 flex operators
  - Decode escaped Type 2 `hflex`, `flex`, `hflex1`, and `flex1` operators.
  - Emit each flex operator as two SVG cubic curves.
  - Preserve explicit unsupported errors for remaining escaped operators.
  - Verify CFF and TrueType SVG generation still succeeds.

- [x] Step 17: Add Type 2 calculation and stack operators
  - Decode common escaped Type 2 arithmetic, boolean, storage, conditional, and stack manipulation operators.
  - Preserve deterministic behavior for `random` and integer-only evaluation for calculation operators.
  - Keep non-calculation escaped operators explicitly unsupported.
  - Verify CFF and TrueType SVG generation still succeeds.

- [x] Step 18: Add CID-keyed CFF local subroutine selection
  - Read Top DICT `FDArray` and `FDSelect` offsets.
  - Support FDSelect formats 0 and 3.
  - Resolve glyph-specific Font DICT `Private` and local `Subrs` offsets.
  - Verify CFF and TrueType SVG generation still succeeds.

- [x] Step 19: Add point-matched composite glyph rendering
  - Reuse simple glyph point decoding for component point collection.
  - Track accumulated parent component points while expanding composites.
  - Align component point indexes to referenced parent point indexes before path emission.

- [x] Step 20: Add initial CFF2 outline rendering path
  - Accept `CFF2` as an outline-bearing table when `glyf`/`CFF ` are absent.
  - Parse CFF2 header, Top DICT, CFF2 INDEX structures, global subrs, CharStrings, FDArray, FDSelect, and Private Subrs at the non-variation scope.
  - Reuse the Type 2 executor for CFF2 charstrings and close top-level paths at charstring EOF.
  - Keep CFF2 variation `blend` processing explicitly unsupported.
  - Verify existing CFF1 SVG output still succeeds.

- [x] Step 21: Add CFF2 default-instance blend handling
  - Read the CFF2 Top DICT Variation Store offset.
  - Parse Item Variation Store metadata enough to obtain the variation region count.
  - Handle Type 2 `blend` by preserving default operands and dropping variation deltas for default-instance rendering.
  - Keep non-default variation interpolation deferred.
  - Verify existing CFF1 SVG output still succeeds.

- [x] Step 22: Add CFF2 variation blend interpolation core
  - Parse Variation Region List F2DOT14 start/peak/end coordinates.
  - Compute region weights from caller-provided normalized coordinates.
  - Apply weighted deltas for Type 2 `blend` operands before drawing commands consume them.
  - Expose normalized CFF2 variation coordinates through `RenderOptions` for high-level SVG rendering.
  - Keep named instance selection deferred.

- [x] Step 23: Add fvar/avar variation coordinate normalization
  - Parse `fvar` variation axes with min/default/max design-space values.
  - Normalize caller-provided design-space coordinates by axis tag.
  - Apply optional `avar` segment-map interpolation after default `fvar` normalization.
  - Expose design-space variation coordinates through `Face.normalizedVariationCoords` and `RenderOptions.variation_coords`.
  - Keep named instance selection deferred.

- [x] Step 24: Add explicit TTC face index selection
  - Preserve `Face.init` default first-face behavior for existing callers.
  - Add explicit parser API for selecting a TTC face by zero-based index.
  - Add CLI and high-level SVG rendering options for selecting non-first TTC faces.
  - Reject out-of-range face indexes with a specific parser error.
  - Verify real TTC SVG output using a non-zero face index.

## Completion Criteria

- [x] A visible SVG can be generated from a TrueType font with simple glyphs.
- [x] Composite glyphs with XY offsets can be expanded into visible component paths.
- [x] Composite glyphs with scale or matrix transforms can be emitted as transformed paths.
- [x] Point-matched composite glyph components can align referenced component and parent points.
- [x] SVG output has practical pixel dimensions.
- [x] SVG output is sized from actual rendered glyph bounds.
- [x] High-level API is available for one-call SVG rendering.
- [x] SVG output can be styled with fill, background, and margin controls.
- [x] CFF charstrings can be reached and basic Type 2 operators can be converted to SVG path commands.
- [x] CFF subroutine-backed glyphs can be expanded for basic Type 2 outlines.
- [x] CID-keyed CFF glyphs can select glyph-specific local subroutines via FDSelect.
- [x] Non-variation CFF2 charstrings can be reached and converted through the SVG outline path.
- [x] CFF2 `blend` charstrings can render at the default instance by ignoring variation deltas.
- [x] CFF2 `blend` charstrings can apply weighted non-default deltas when normalized variation coordinates are provided.
- [x] Design-space variation coordinates can be normalized through `fvar` and optional `avar` data for CFF2 rendering callers.
- [x] Non-first TTC faces can be selected explicitly for parser and SVG rendering paths.
- [x] Common CFF Type 2 curve operators and hint masks are handled.
- [x] Type 2 flex operators are emitted as cubic SVG paths.
- [x] Type 2 calculation and stack operators can feed subsequent drawing operands.
- [x] Generated SVG contains path elements.
- [x] Existing parser and shaper tests still pass.
- [x] CFF2 named instance selection and full typography remain explicitly deferred.
