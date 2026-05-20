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
- When no feature tags are provided, the shaping engine applies a conservative default feature policy for common shaping features, with Arabic and Indic-specific additions.
- When direction is automatic, the first strong codepoint determines the paragraph direction.
- RTL visual ordering preserves the internal order of strong LTR words/phrases plus ASCII and Arabic-Indic formatted numeric runs.
- Mixed strong LTR/RTL text with an LTR first strong codepoint reverses RTL runs inside the LTR paragraph and preserves internal formatted numeric run order inside those RTL runs.
- Numeric separators, signs, and percent marks remain weak LTR only when attached to neighboring digits; standalone neutral punctuation remains part of the RTL run.
- Neutral phrase connectors remain LTR only when bounded by LTR letters or digits; standalone neutral punctuation remains part of the RTL run.
- ASCII, common, and extended paired brackets inside RTL visual runs are mirrored by resolving the mirrored codepoint through the font cmap; if the mirrored codepoint maps to glyph ID 0, the original glyph is preserved.
- Common Indic pre-base matras move before the preceding consonant base in visual order after GSUB/GPOS positioning; post-base matras remain in place.
- Leading same-script Brahmic ra + virama sequences that remain decomposed after GSUB/GPOS move after the following consonant base in visual order.
- When direction is explicitly top-to-bottom, shaped glyphs stack on the vertical axis while preserving cross-axis positioning from GPOS.
- Legacy `kern` remains a fallback when GPOS is absent or does not apply an adjustment.
- Cluster indexes follow input codepoint order.

## Deferred Rules

- Full Indic syllable reordering beyond pre-base matra and Devanagari repha-sequence visual movement is not applied.
- Full mixed-direction Unicode Bidi beyond the current first-strong/run-level heuristic is not applied.
