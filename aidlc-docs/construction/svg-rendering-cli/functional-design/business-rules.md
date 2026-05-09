# Business Rules - Unit 3: SVG Rendering & CLI

## Implemented Rules

- `--output <svg-file>` writes SVG only when `--text` is also supplied.
- SVG generation uses the current shaped glyph sequence.
- Simple TrueType contours produce SVG `M`, `L`, `Q`, and `Z` path commands.
- Consecutive off-curve quadratic points use the implied midpoint rule.
- Empty glyph ranges produce no path.
- Composite glyphs are expanded when their components use XY offsets.
- Composite recursion is bounded to prevent malformed fonts from causing unbounded expansion.
- `--font-size` must be a positive finite number.
- SVG output includes `width`, `height`, and a pixel-space `viewBox`.
- CLI metadata output is suppressed when `--output` is used.

## Deferred Rules

- Point-matched composite components return `UnsupportedCompositeGlyph`.
- Scaled or matrix-transformed composite components return `UnsupportedCompositeGlyph`.
- CFF fonts are not rendered.
- Custom margins and style controls are not exposed through CLI.
