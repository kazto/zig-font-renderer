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
- Legacy `kern` remains a fallback when GPOS is absent or does not apply an adjustment.
- Cluster indexes follow input codepoint order.

## Deferred Rules

- Complex script reordering is not applied.
- Full OpenType script/language/feature selection is not applied.
- Bidirectional text and vertical layout are not applied.
