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

## Completion Criteria

- [x] A visible SVG can be generated from a TrueType font with simple glyphs.
- [x] Composite glyphs with XY offsets can be expanded into visible component paths.
- [x] Generated SVG contains path elements.
- [x] Existing parser and shaper tests still pass.
- [x] CFF and full typography remain explicitly deferred.
