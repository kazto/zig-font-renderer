# Logical Components - Unit 2: Shaping Engine

## Components

- `ShapeEngine`: Public shaping entry point.
- `ShapedGlyph`: Per-glyph positioned output record.
- `ShapedText`: Owned shaping result.
- `ShapeError`: Combined shaping, parser, and allocation error set.
- Legacy kern reader: Internal helper that reads `kern` version 0 horizontal format 0 subtables.

## Integration

- Uses `Face.getGlyphInfo` from Unit 1.
- Uses `Face.getTable("kern")` from Unit 1 when available.
- Exposed through `src/root.zig`.
- Consumed by the CLI text inspection path in `src/main.zig`.
