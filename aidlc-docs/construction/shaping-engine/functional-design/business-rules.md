# Business Rules - Unit 2: Shaping Engine

## Implemented Rules

- Input text must be valid UTF-8.
- Each Unicode codepoint maps independently through the current `Face` cmap lookup.
- Missing codepoints inherit Unit 1 behavior and become glyph ID 0.
- `x_offset` is the cumulative pen position before the glyph.
- `x_advance` is the glyph horizontal advance width in raw FUnits.
- If a legacy horizontal `kern` format 0 pair exists, the pair value is added to the left glyph's `x_advance`.
- `kern_adjustment` records the pair adjustment applied to the glyph.
- GSUB Single Substitution and Ligature Substitution may replace glyph IDs before positioning.
- GPOS Single Adjustment and Pair Adjustment may modify glyph offsets and advances.
- GPOS Mark-to-Base Attachment (Type 4) aligns mark anchors with base anchors and zeroes mark advances.
- GPOS Mark-to-Ligature Attachment (Type 5) aligns mark anchors with ligature component anchors and zeroes mark advances.
- GPOS Mark-to-Mark Attachment (Type 6) aligns stacked mark anchors and zeroes attaching mark advances.
- GSUB Alternate Substitution (Type 3) replaces covered glyphs with the first alternate glyph.
- GSUB Contextual Substitution (Type 5 Format 3) applies lookups to input sequences based on coverage context.
- GSUB Chained Contextual Substitution (Type 6 Format 3) applies lookups to input sequences based on surrounding coverage-based backtrack and lookahead glyphs.
- Callers may constrain OpenType Layout lookup application with explicit script, language, and feature tags.
- When no script tag is provided, the shaping engine infers a coarse OpenType script tag from the first supported Unicode script range in the input and falls back to DFLT/latn if that script is absent from the font.
- When no language tag is provided, the shaping engine infers a coarse OpenType language tag for selected scripts/languages and falls back to the default LangSys if that language is absent from the font.
- Legacy `kern` remains a fallback when GPOS is absent or does not apply an adjustment.
- Cluster indexes follow input codepoint order.

## Deferred Rules

- Complex script reordering is not applied.
- Feature default policy beyond caller-provided tags is not applied.
- Bidirectional text and vertical layout are not applied.
