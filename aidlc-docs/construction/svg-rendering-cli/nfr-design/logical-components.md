# Logical Components - Unit 3: SVG Rendering & CLI

## Components

- `SvgRenderer`: Public SVG document generator.
- `renderToSvg`: High-level API for file loading, parsing, shaping, and SVG rendering.
- `RenderToSvgOptions`: High-level API configuration.
- `RenderOptions`: Public renderer sizing options.
- `appendGlyphPath`: Internal glyph-to-path converter.
- `appendCompositeGlyphPaths`: Internal composite glyph expander for XY-offset components.
- `glyphRange`: Internal `loca` resolver.
- `textBounds`: Internal shaped text bounds calculator.
- `glyphBounds`: Internal glyph header bounds reader.
- CLI `--output`: File-writing path for generated SVG.
- CLI `--font-size`: Pixel size control for generated SVG.

## Integration

- Uses `ShapeEngine.shapeText`.
- Uses `Face.requireTable` for `head`, `loca`, and `glyf`.
- Exposed through `src/root.zig`.
