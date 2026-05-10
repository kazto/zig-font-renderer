# Business Rules - Unit 3: SVG Rendering & CLI

## Implemented Rules

- `--output <svg-file>` writes SVG only when `--text` is also supplied.
- SVG generation uses the current shaped glyph sequence.
- Simple TrueType contours produce SVG `M`, `L`, `Q`, and `Z` path commands.
- Consecutive off-curve quadratic points use the implied midpoint rule.
- Empty glyph ranges produce no path.
- Composite glyphs are expanded when their components use XY offsets.
- Composite glyphs with uniform scale, separate XY scale, or 2x2 transforms are emitted by transforming path coordinates.
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
- CLI metadata output is suppressed when `--output` is used.
- `renderToSvg` owns file loading and returns an allocated SVG buffer owned by the caller.
- CLI SVG output must use the same high-level API exposed to library users.
- CFF `CharStrings` INDEX data can be resolved by glyph ID.
- CFF Top DICT `Private` and Private DICT `Subrs` offsets are resolved for local subroutines.
- Basic Type 2 `rmoveto`, `hmoveto`, `vmoveto`, `rlineto`, `hlineto`, `vlineto`, `rrcurveto`, and `endchar` operators emit SVG path commands.
- Type 2 `callsubr` and `callgsubr` expand local/global CFF subroutines with bounded recursion.
- Type 2 `hintmask` and `cntrmask` bytes are skipped according to the active stem hint count.
- Common Type 2 compact curve operators `hhcurveto`, `vvcurveto`, `hvcurveto`, `vhcurveto`, `rcurveline`, and `rlinecurve` emit SVG path commands.
- Unsupported Type 2 operators return `UnsupportedCffOperator`.

## Deferred Rules

- Point-matched composite components return `UnsupportedCompositeGlyph`.
- CFF2 outlines are not rendered.
