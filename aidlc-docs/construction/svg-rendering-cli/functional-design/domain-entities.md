# Domain Entities - Unit 3: SVG Rendering & CLI

## SvgRenderer

Public renderer entry point that converts a parsed `Face` and UTF-8 text into an owned SVG document buffer.

## Point

Internal decoded TrueType point:

- `x`
- `y`
- `on_curve`

## GlyphRange

Internal byte range into the `glyf` table, resolved from `loca`.

## Composite Component

Internal component record in a composite TrueType glyph. The current implementation supports component glyph ID plus XY offset placement.

## SVG Document

UTF-8 text buffer containing `<svg>`, one `<g>`, and one `<path>` per rendered simple glyph.
