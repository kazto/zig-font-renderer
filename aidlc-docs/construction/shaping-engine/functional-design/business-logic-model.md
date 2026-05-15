# Business Logic Model - Unit 2: Shaping Engine

## Scope

The current increment implements horizontal text shaping using data exposed by Unit 1, including RTL-only visual ordering at the tested scope.

## Flow

1. Accept UTF-8 input text and a parsed `Face`.
2. Validate UTF-8.
3. Iterate Unicode codepoints in input order.
4. Resolve each codepoint to a glyph ID and horizontal metrics through `Face.getGlyphInfo`.
5. Emit `ShapedGlyph` records with cluster indexes and horizontal metrics.
6. Apply supported GSUB substitutions and GPOS positioning.
7. Apply supported legacy pair kerning from the `kern` table when GPOS did not position the glyphs.
8. Recompute horizontal offsets and total advance in raw FUnits.
9. For RTL-only input or explicit RTL direction, mirror glyph offsets and reverse the shaped glyph sequence for visual output.

## Deferred Logic

- Full mixed-direction Unicode Bidi handling.
- Complex script reordering.
- Vertical writing mode.
