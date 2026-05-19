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
8. Reorder common Indic pre-base matras before the preceding consonant base.
9. Reorder leading decomposed same-script Brahmic ra + virama sequences after the following consonant base.
10. Recompute horizontal offsets after Indic visual reordering.
11. Recompute total advance in raw FUnits.
12. For RTL-only input, explicit RTL direction, or mixed RTL runs, resolve ASCII, common, and extended paired brackets to mirrored glyph IDs when the font provides the mirrored codepoint.
13. For RTL-only input or explicit RTL direction, mirror glyph offsets and reverse the shaped glyph sequence for visual output, preserving formatted numeric run order.

## Deferred Logic

- Full mixed-direction Unicode Bidi handling beyond the current heuristic.
- Full Indic syllable shaping/reordering beyond pre-base matra and Devanagari repha-sequence visual movement.
