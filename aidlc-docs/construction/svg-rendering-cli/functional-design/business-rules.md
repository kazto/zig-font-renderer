# Business Rules - Unit 3: SVG Rendering & CLI

## Implemented Rules

- `--output <svg-file>` writes SVG only when `--text` is also supplied.
- SVG generation uses the current shaped glyph sequence.
- Simple TrueType contours produce SVG `M`, `L`, `Q`, and `Z` path commands.
- Consecutive off-curve quadratic points use the implied midpoint rule.
- Empty glyph ranges produce no path.
- Composite glyphs are expanded when their components use XY offsets.
- Composite glyphs with uniform scale, separate XY scale, or 2x2 transforms are emitted by transforming path coordinates.
- Point-matched composite glyph components align the referenced component point with an already accumulated parent component point.
- Nested composite glyph transforms are composed before path emission.
- Composite recursion is bounded to prevent malformed fonts from causing unbounded expansion.
- `--font-size` must be a positive finite number.
- `--margin` must be a finite non-negative number.
- SVG output includes `width`, `height`, and a pixel-space `viewBox`.
- SVG output dimensions are derived from actual glyph bounds plus margin.
- SVG fill color defaults to `black`.
- Optional SVG background emits a full-size `<rect>` before glyph paths.
- SVG color values must be non-empty and limited to characters safe for attribute values.
- Text advance remains included in horizontal bounds when advance exceeds visible outline bounds.
- `--direction` can select `auto`, `ltr`, `rtl`, or `ttb` shaping direction.
- Automatic direction handling keeps pure RTL text in RTL visual order and reverses contiguous strong RTL runs within mixed strong LTR/RTL text when the paragraph resolves to LTR.
- Top-to-bottom direction stacks glyphs on the vertical axis while preserving cross-axis positioning from shaping.
- CLI metadata output is suppressed when `--output` is used.
- `renderToSvg` owns file loading and returns an allocated SVG buffer owned by the caller.
- CLI SVG output must use the same high-level API exposed to library users.
- CFF `CharStrings` INDEX data can be resolved by glyph ID.
- CFF Top DICT `Private` and Private DICT `Subrs` offsets are resolved for local subroutines.
- CID-keyed CFF glyphs resolve glyph-specific Font DICT local subroutines through `FDArray` and `FDSelect`.
- Basic Type 2 `rmoveto`, `hmoveto`, `vmoveto`, `rlineto`, `hlineto`, `vlineto`, `rrcurveto`, and `endchar` operators emit SVG path commands.
- Type 2 `callsubr` and `callgsubr` expand local/global CFF subroutines with bounded recursion.
- Type 2 `hintmask` and `cntrmask` bytes are skipped according to the active stem hint count.
- Type 2 escaped `hstem3` and `vstem3` operators contribute to the active stem hint count used by `hintmask` and `cntrmask`.
- Type 2 escaped `setcurrentpoint` updates the current point without emitting a path segment.
- Type 2 `closepath` closes the active contour without forcing a synthetic new move command.
- Type 2 escaped `callothersubr` and `pop` preserve compatibility operands for subsequent drawing commands.
- Common Type 2 compact curve operators `hhcurveto`, `vvcurveto`, `hvcurveto`, `vhcurveto`, `rcurveline`, and `rlinecurve` emit SVG path commands.
- Type 2 escaped flex operators `hflex`, `flex`, `hflex1`, and `flex1` emit two SVG cubic path commands.
- Type 2 escaped calculation and stack operators update the operand stack for subsequent path commands.
- `fvar` variation axes normalize caller-provided design-space coordinates against min/default/max axis values.
- `avar` segment maps adjust normalized variation coordinates when the font provides axis variation mapping data.
- CFF2 `blend` keeps default operands when no normalized variation coordinates are provided.
- CFF2 `blend` applies weighted region deltas when callers provide normalized CFF2 variation coordinates.
- CFF2 `blend` applies weighted region deltas when callers provide design-space variation coordinates that can be normalized through `fvar`/`avar`.
- Unsupported Type 2 operators return `UnsupportedCffOperator`.

## Deferred Rules

- CFF2 named instance selection is not applied.
