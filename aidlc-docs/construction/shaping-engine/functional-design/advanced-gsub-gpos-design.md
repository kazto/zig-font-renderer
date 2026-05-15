# Functional Design - Unit 2 Extension: Advanced GSUB/GPOS

This document defines the functional design for advanced OpenType Layout lookups in the Shaping Engine, focusing on mark attachment and contextual substitutions.

## Domain Entities

### GPOS Type 4: Mark-to-Base Attachment
- **MarkAnchor**: A point on a mark glyph (e.g., accent) used for attachment.
- **BaseAnchor**: A point on a base glyph (e.g., letter) used for attachment.
- **MarkClass**: A grouping of marks that share attachment points on bases.
- **AnchorTable**: Defines X and Y coordinates (raw FUnits) for an anchor point.

### GSUB Type 6: Chained Contextual Substitution
- **BacktrackSequence**: Glyphs that must precede the input sequence.
- **InputSequence**: Glyphs to be substituted if the context matches.
- **LookaheadSequence**: Glyphs that must follow the input sequence.
- **SubstitutionLookup**: The lookup to apply to the input sequence upon a match.

## Business Rules

### Mark-to-Base Positioning (GPOS Type 4)
- A mark glyph is positioned relative to a preceding base glyph.
- The base glyph's anchor point and the mark glyph's anchor point are aligned in coordinate space.
- The mark glyph's `x_offset` and `y_offset` are adjusted such that its anchor matches the base's anchor.
- The mark glyph's `x_advance` is typically set to zero so it doesn't affect subsequent glyph placement (it "attaches" to the base).
- Attachment only occurs if both the base and the mark have anchors defined for the same MarkClass.

### Chained Contextual Substitution (GSUB Type 6)
- Current implementation supports glyph-based Format 1, class-based Format 2, and coverage-based Format 3.
- Backtrack sequences are checked in reverse order (closest to input first).
- Lookahead sequences are checked in forward order.
- If a match is found, one or more lookups are applied to the input sequence.
- Substitutions can change glyph IDs, update glyph stream length, and may trigger further lookups through recursive application.

## Logic Model

### Mark-to-Base Algorithm
1. Identify a glyph as a "Mark" using the lookup's `MarkCoverage`.
2. Look back in the shaped glyph stream to find the nearest "Base" glyph (skipping other marks if necessary).
3. Retrieve the `MarkAnchor` for the mark glyph.
4. Retrieve the `BaseAnchor` for the base glyph corresponding to the mark's class.
5. Calculate the relative offset: `offset = BaseAnchor - MarkAnchor`.
6. Apply the offset to the mark glyph's `x_offset` and `y_offset`.
7. Zero out the mark's `x_advance`.

### Chained Contextual Algorithm
1. For each position in the glyph stream:
2. Check if the current glyph matches the first element of an `InputSequence`.
3. If yes, check if subsequent glyphs match the rest of the `InputSequence`.
4. Check if preceding glyphs match the `BacktrackSequence`.
5. Check if following glyphs match the `LookaheadSequence`.
6. If all match, apply the specified `SubstLookupRecord` (which contains an index into the `LookupList`).
