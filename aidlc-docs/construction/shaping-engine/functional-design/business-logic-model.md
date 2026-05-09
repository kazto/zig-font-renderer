# Business Logic Model - Unit 2: Shaping Engine

## Scope

The current increment implements basic left-to-right text shaping using data exposed by Unit 1.

## Flow

1. Accept UTF-8 input text and a parsed `Face`.
2. Validate UTF-8.
3. Iterate Unicode codepoints in input order.
4. Resolve each codepoint to a glyph ID and horizontal metrics through `Face.getGlyphInfo`.
5. Emit `ShapedGlyph` records with cluster indexes and horizontal pen positions.
6. Apply supported legacy pair kerning from the `kern` table.
7. Recompute horizontal offsets and total advance in raw FUnits.

## Deferred Logic

- GSUB substitutions, including ligatures.
- GPOS positioning.
- Bidirectional text handling.
- Script-specific shaping.
- Vertical writing mode.
