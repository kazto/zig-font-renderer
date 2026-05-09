# Domain Entities - Unit 3: SVG Rendering & CLI

## SvgRenderer

Public renderer entry point that converts a parsed `Face` and UTF-8 text into an owned SVG document buffer.

## RenderToSvgOptions

High-level API options:

- `render`: SVG render options.
- `max_font_bytes`: maximum font file size to load.

## RenderOptions

Renderer options for visible output sizing and basic styling:

- `font_size_px`
- `margin_px`
- `fill`
- `background`

## Point

Internal decoded TrueType point:

- `x`
- `y`
- `on_curve`

## GlyphRange

Internal byte range into the `glyf` table, resolved from `loca`.

## Bounds

Internal FUnit bounding box:

- `min_x`
- `min_y`
- `max_x`
- `max_y`

## Composite Component

Internal component record in a composite TrueType glyph. The current implementation supports component glyph ID, XY offset placement, uniform scale, separate XY scale, and 2x2 transforms.

## Transform

Internal affine transform used to compose shaped glyph placement and composite component transforms before writing SVG path coordinates.

## SVG Document

UTF-8 text buffer containing `<svg>`, an optional background `<rect>`, one scaled `<g>`, and one `<path>` per rendered simple glyph.
