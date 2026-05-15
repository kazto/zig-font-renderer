# Logical Components - Unit 3: SVG Rendering & CLI

## Components

- `SvgRenderer`: Public SVG document generator.
- `renderToSvg`: High-level API for file loading, parsing, shaping, and SVG rendering.
- `RenderToSvgOptions`: High-level API configuration.
- `RenderOptions`: Public renderer sizing and basic styling options.
- `validateSvgColor`: Internal SVG attribute value guard for fill and background.
- `appendGlyphPath`: Internal glyph-to-path converter.
- `appendCompositeGlyphPaths`: Internal composite glyph expander for XY-offset, transformed, and point-matched components.
- `appendGlyphTransformedPoints`: Internal point collector used to resolve composite point-matched placement.
- `cff_outline.appendGlyphPath`: CFF Type 2 outline-to-SVG path converter.
- `cff_types`: Shared CFF error, transform, INDEX, context, and Type 2 state definitions.
- `cff_index`: CFF INDEX and DICT operand parsing helpers.
- `cff_context`: CFF Top DICT, Private DICT, FDArray, and FDSelect resolution.
- `type2_charstring`: Type 2 charstring execution and SVG path emission.
- `glyphRange`: Internal `loca` resolver and CFF/CFF2 unsupported-outline detector.
- `textBounds`: Internal shaped text bounds calculator.
- `glyphBounds`: Internal glyph header bounds reader.
- `Transform`: Internal affine transform for shaped placement and composite component transforms.
- `readF2Dot14`: Internal decoder for composite glyph scale fields.
- CLI `--output`: File-writing path for generated SVG.
- CLI `--font-size`: Pixel size control for generated SVG.
- CLI `--margin`: Margin control for generated SVG.
- CLI `--fill`: Glyph fill color control.
- CLI `--background`: Optional SVG background color control.

## Integration

- Uses `ShapeEngine.shapeText`.
- Uses `Face.requireTable` for `head`, `loca`, and `glyf`.
- Uses `Face.getTable` to route `CFF ` outlines to `src/cff_outline.zig` and detect unsupported `CFF2` outline tables before `glyf`-specific rendering.
- Exposed through `src/root.zig`.
