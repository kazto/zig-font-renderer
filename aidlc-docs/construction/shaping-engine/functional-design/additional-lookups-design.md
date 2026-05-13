# Functional Design - Unit 2 Extension: Additional GSUB/GPOS Lookups

This document defines the functional design for GPOS Type 5/6 and GSUB Type 3/5 lookups, extending the current OpenType Layout support in the Shaping Engine.

## Domain Entities

### GPOS Type 5: Mark-to-Ligature Attachment
- **MarkAnchor**: Anchor on the mark glyph.
- **LigatureAnchor**: Multiple anchors on the ligature glyph, one per component (e.g., for 'f' and 'i' parts of an 'fi' ligature).
- **ComponentCount**: Number of components in the ligature.

### GPOS Type 6: Mark-to-Mark Attachment
- **Mark1Anchor**: Anchor on the "base" mark (the one already attached to a base).
- **Mark2Anchor**: Anchor on the "attaching" mark (the one being positioned).

### GSUB Type 3: Alternate Substitution
- **AlternateSet**: A list of possible replacement glyph IDs for a single input glyph.

### GSUB Type 5: Contextual Substitution
- Similar to GSUB Type 6 (Chained Contextual) but without backtrack and lookahead sequences. Focuses only on the input sequence and its class/coverage/glyph ID matching.

## Business Rules

### Mark-to-Ligature Positioning (GPOS Type 5)
- Similar to Mark-to-Base, but the ligature has an array of anchor points corresponding to its components.
- The mark attaches to a specific component of the ligature.
- Usually, multiple marks can attach to different components of the same ligature.
- Current implementation supports tested anchor positioning and defers more robust component index selection for real-world ligature streams.

### Mark-to-Mark Positioning (GPOS Type 6)
- Positions a mark relative to another mark.
- Used for stacking diacritics (e.g., an accent above another accent).
- The "base" mark must have been positioned by a previous lookup (usually Mark-to-Base).

### Alternate Substitution (GSUB Type 3)
- Replaces one glyph ID with one of its alternates.
- Since our engine is currently deterministic and doesn't take "alternate index" as input, it will default to the first alternate provided in the set unless otherwise specified in future extensions.

### Contextual Substitution (GSUB Type 5)
- Matches an input sequence using glyph IDs (Format 1), classes (Format 2), or coverages (Format 3).
- Applies sub-lookups to specific positions in the matched sequence.
- Shares the same matching engine logic as Type 6 (Chained), just with empty backtrack/lookahead.
- Contextual sub-lookups replace the affected glyph stream suffix, so substitutions that change glyph count are reflected.

## Logic Model

### Mark-to-Mark Algorithm
1. Identify a glyph as a "Mark2" (attaching mark).
2. Look back in the glyph stream to find the nearest preceding "Mark1" (base mark).
3. Align `Mark1Anchor` and `Mark2Anchor`.
4. Adjust `Mark2` offsets and zero its advance.

### Alternate Substitution Algorithm
1. Identify glyph ID in `AlternateSet`.
2. Replace with the first glyph ID in the set (default behavior).
