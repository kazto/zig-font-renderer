# Domain Entities - Unit 2: Shaping Engine

## ShapeEngine

Stateless entry point for transforming UTF-8 text and a parsed `Face` into positioned glyph records.

## ShapedGlyph

- `codepoint`: Unicode scalar value from the input.
- `glyph_id`: Glyph ID returned by the font cmap.
- `cluster`: Input codepoint index for traceability.
- `x_offset`: Horizontal pen position before drawing this glyph.
- `y_offset`: Vertical offset, currently always 0.
- `x_advance`: Horizontal advance in raw FUnits.
- `y_advance`: Vertical advance, currently always 0.
- `advance_width`: Original horizontal metric from the font.
- `lsb`: Left side bearing from the font.
- `kern_adjustment`: Legacy `kern` pair adjustment applied to this glyph's advance.

## ShapedText

Owns a slice of shaped glyph records and the total horizontal advance.
