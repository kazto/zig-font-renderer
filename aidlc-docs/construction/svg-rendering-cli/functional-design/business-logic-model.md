# Business Logic Model - Unit 3: SVG Rendering & CLI

## Scope

The current increment renders shaped text as SVG paths for TrueType `glyf` outlines, CFF Type 2 outlines, and CFF2 Type 2 outlines at the tested scope.

## Flow

1. Parse a font with `Face`.
2. Shape UTF-8 text with `ShapeEngine`.
3. Resolve each glyph ID to a `glyf` byte range through `loca`.
4. Decode simple glyph contours or supported CFF/CFF2 Type 2 charstrings.
5. Convert contour points to SVG path commands.
6. Place each glyph at the shaped glyph `x_offset` and `y_offset`.
7. For supported composite glyphs, recursively render component glyphs with XY offsets, affine transforms, or point-matched placement.
8. Normalize design-space variation coordinates through `fvar` and optional `avar` data when callers provide axis-tagged coordinates or an `fvar` named instance index.
9. For CFF2 `blend`, compute Variation Store region weights from normalized coordinates when callers provide them directly, through design-space coordinates, or through an instance index.
10. Combine glyph header bounds into shaped text bounds.
11. Scale raw FUnit path coordinates into a pixel-sized SVG group transform.
12. Write a complete SVG document.

## High-Level API Flow

1. Read font bytes from a font path.
2. Parse `Face`.
3. Parse optional CLI variation axis coordinates or named instance selection into `RenderOptions`.
4. Render text to SVG with `SvgRenderer`.
5. Return an owned SVG buffer to the caller.

## Deferred Logic

- Uncommon CFF Type 2 operators.
- Complex script reordering.
- Bidirectional text handling.
- Vertical layout.
- Fill rules beyond standard SVG path fill behavior.
