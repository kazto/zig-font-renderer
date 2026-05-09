# Logical Components - Unit 3: SVG Rendering & CLI

## Components

- `SvgRenderer`: Public SVG document generator.
- `RenderOptions`: Public renderer sizing options.
- `appendGlyphPath`: Internal glyph-to-path converter.
- `appendCompositeGlyphPaths`: Internal composite glyph expander for XY-offset components.
- `glyphRange`: Internal `loca` resolver.
- CLI `--output`: File-writing path for generated SVG.
- CLI `--font-size`: Pixel size control for generated SVG.

## Integration

- Uses `ShapeEngine.shapeText`.
- Uses `Face.requireTable` for `head`, `loca`, and `glyf`.
- Exposed through `src/root.zig`.
