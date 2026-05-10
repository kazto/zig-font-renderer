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
  - Reject point-matched or transformed components that are not yet supported.

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
  - Preserve explicit rejection for point-matched composite components.

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

## Completion Criteria

- [x] A visible SVG can be generated from a TrueType font with simple glyphs.
- [x] Composite glyphs with XY offsets can be expanded into visible component paths.
- [x] Composite glyphs with scale or matrix transforms can be emitted as transformed paths.
- [x] SVG output has practical pixel dimensions.
- [x] SVG output is sized from actual rendered glyph bounds.
- [x] High-level API is available for one-call SVG rendering.
- [x] SVG output can be styled with fill, background, and margin controls.
- [x] CFF charstrings can be reached and basic Type 2 operators can be converted to SVG path commands.
- [x] Generated SVG contains path elements.
- [x] Existing parser and shaper tests still pass.
- [x] CFF subroutines, CFF2, and full typography remain explicitly deferred.
