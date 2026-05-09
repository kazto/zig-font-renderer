# Logical Components - Unit 2: Shaping Engine

## Components

- `ShapeEngine`: Public shaping entry point.
- `ShapedGlyph`: Per-glyph positioned output record.
- `ShapedText`: Owned shaping result.
- `ShapeError`: Combined shaping, parser, and allocation error set.

## Integration

- Uses `Face.getGlyphInfo` from Unit 1.
- Exposed through `src/root.zig`.
- Consumed by the CLI text inspection path in `src/main.zig`.
