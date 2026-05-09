# Business Rules - Unit 2: Shaping Engine

## Implemented Rules

- Input text must be valid UTF-8.
- Each Unicode codepoint maps independently through the current `Face` cmap lookup.
- Missing codepoints inherit Unit 1 behavior and become glyph ID 0.
- `x_offset` is the cumulative pen position before the glyph.
- `x_advance` is the glyph horizontal advance width in raw FUnits.
- If a legacy horizontal `kern` format 0 pair exists, the pair value is added to the left glyph's `x_advance`.
- `kern_adjustment` records the pair adjustment applied to the glyph.
- `y_offset` and `y_advance` remain 0 in this increment.
- Cluster indexes follow input codepoint order.

## Deferred Rules

- Ligature clusters may span multiple input codepoints after GSUB support is added.
- GPOS pair positioning may further modify offsets and advances after GPOS support is added.
- Complex script reordering is not applied.
