# Business Logic Model - Unit 3: SVG Rendering & CLI

## Scope

The current increment renders shaped text as SVG paths for simple TrueType `glyf` outlines.

## Flow

1. Parse a font with `Face`.
2. Shape UTF-8 text with `ShapeEngine`.
3. Resolve each glyph ID to a `glyf` byte range through `loca`.
4. Decode simple glyph contours.
5. Convert contour points to SVG path commands.
6. Place each glyph at the shaped glyph `x_offset`.
7. For supported composite glyphs, recursively render component glyphs with XY offsets.
8. Combine glyph header bounds into shaped text bounds.
9. Scale raw FUnit path coordinates into a pixel-sized SVG group transform.
10. Write a complete SVG document.

## Deferred Logic

- Point-matched composite glyph expansion.
- Scaled or matrix-transformed composite glyph expansion.
- CFF outline rendering.
- GPOS/GSUB shaping.
- Fill rules beyond standard SVG path fill behavior.
- Advanced sizing controls beyond `--font-size`.
