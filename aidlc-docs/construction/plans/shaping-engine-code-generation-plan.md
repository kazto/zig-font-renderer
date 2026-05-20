# Code Generation Plan - Unit 2: GSUB/GPOS Shaping Extension

This plan covers the implementation of OpenType Layout features (GSUB and GPOS) in the Shaping Engine. It prioritizes common features like ligatures and kerning over complete OpenType spec coverage.

## Unit Context

- **Unit**: Shaping Engine (Unit 2 Extension)
- **Primary story**: US-3 - カーニングと合字のサポート
- **Dependencies**: Unit 1 `Face`
- **Application code paths**:
  - `src/shaper.zig`
  - `src/shaper_indic.zig`

## Execution Checklist

- [x] Step 1: Define OpenType Layout Common Table formats
  - Define `ScriptList`, `FeatureList`, and `LookupList` structures.
  - Implement parsing for `Coverage` and `ClassDefinition` tables.
  - Add `TableTags` for `GSUB` and `GPOS`.

- [x] Step 2: Implement GSUB Basic Engine
  - Implement `GSUB` header parsing.
  - Implement `Script`, `LangSys`, and `Feature` lookup.
  - Implement `Lookup` dispatching.
  - Implement GSUB Lookup Type 1: Single Substitution.

- [x] Step 3: Implement GPOS Basic Engine
  - Implement `GPOS` header parsing.
  - Implement ValueRecord decoding.
  - Implement GPOS Lookup Type 1: Single Adjustment.
  - Implement GPOS Lookup Type 2: Pair Adjustment (Format 1 and 2).

- [x] Step 4: Integrate GSUB/GPOS into `ShapeEngine.shapeText`
  - Update `shapeText` to load GSUB/GPOS tables.
  - Apply GSUB substitutions before GPOS adjustments.
  - Handle glyph record updates (substitution might change glyph IDs).
  - Apply GPOS offsets and advances to `ShapedGlyph`.

- [x] Step 5: Add GSUB Lookup Type 4: Ligature Substitution
  - Implement ligature substitution (e.g., 'f' + 'i' -> 'fi').
  - Handle glyph clustering for ligatures.

- [x] Step 6: Verification
  - Add unit tests for GSUB Single/Ligature substitution.
  - Add unit tests for GPOS Single/Pair adjustment.
  - Run `zig build test`.
  - Verify with a font that supports GSUB/GPOS (e.g., DejaVuSans).

- [x] Step 7: Hardening and fallback preservation
  - Validate OpenType Layout offset slices before dereferencing them.
  - Preserve legacy `kern` fallback when a GPOS table exists but no GPOS adjustment is applied.
  - Add focused tests for checked slicing and GPOS adjustment detection.

- [x] Step 8: Add Arabic joining-form GSUB feature gating
  - Classify Arabic glyphs into isolated, initial, medial, and final joining forms.
  - Treat transparent Arabic marks as non-breaking for joining decisions.
  - Apply `isol`, `init`, `medi`, and `fina` GSUB single substitutions only to glyphs matching the corresponding joining form.
  - Continue applying non-positional Arabic features through the existing GSUB lookup path.
  - Verify with synthetic GSUB data and a real Arabic font SVG smoke test.

- [x] Step 9: Preserve weak LTR numeric runs inside RTL visual ordering
  - Split RTL visual runs into directional groups.
  - Preserve ASCII and Arabic-Indic digit sequence order inside RTL runs.
  - Continue mirroring RTL glyph groups across the run span.
  - Reuse the same grouping for RTL-only and mixed-direction visual ordering.
  - Verify with unit tests and a real Arabic text plus digits SVG smoke test.

- [x] Step 10: Add Indic pre-base matra visual reordering
  - Detect common Indic pre-base matra codepoints.
  - Move pre-base matras before the preceding consonant base in visual glyph order.
  - Recompute horizontal offsets after reordering while preserving per-glyph placement deltas.
  - Keep post-base matras in logical/visual order.
  - Verify with unit tests and a real Devanagari font SVG smoke test.

- [x] Step 11: Add Devanagari initial repha-sequence visual reordering
  - Detect leading Devanagari ra + virama glyph sequences that remain after GSUB/GPOS.
  - Move the sequence after the following consonant base in visual glyph order.
  - Preserve placement deltas and recompute horizontal offsets after reordering.
  - Verify with unit tests covering plain repha movement and interaction with pre-base matras.

- [x] Step 12: Add RTL paired punctuation mirroring
  - Mirror common paired punctuation codepoints inside RTL visual runs.
  - Resolve mirrored codepoints through cmap so rendered glyph IDs change, not only metadata.
  - Apply mirroring before RTL visual reordering for RTL-only and mixed-direction RTL runs.
  - Verify with focused unit tests and a real Hebrew SVG smoke test.

- [x] Step 13: Broaden RTL paired-bracket mirroring coverage
  - Expand mirroring from ASCII/common punctuation to a broader Unicode paired-bracket set.
  - Keep original glyphs when the font cmap does not contain the mirrored codepoint.
  - Verify with focused unit tests and real-font smoke tests for ASCII and extended bracket input.

- [x] Step 14: Preserve numeric separators inside RTL numeric runs
  - Treat decimal, grouping, date/time, sign, and percent separators as weak LTR when attached to digits.
  - Keep formatted numeric strings in logical reading order inside RTL visual runs.
  - Keep standalone neutral punctuation with surrounding RTL run content.
  - Verify with focused unit tests and a real Hebrew font SVG smoke test.

- [x] Step 15: Broaden Indic fallback reordering coverage
  - Generalize initial ra + virama repha fallback movement across supported Brahmic scripts instead of Devanagari only.
  - Keep repha movement script-aware so cross-script glyph streams are not reordered accidentally.
  - Expand pre-base matra detection for Telugu, Kannada, and Malayalam vowel signs.
  - Verify with focused unit tests and real Bengali/Telugu font SVG smoke tests.

- [x] Step 16: Add first-strong Bidi paragraph direction and LTR run preservation
  - Resolve automatic paragraph direction from the first strong codepoint.
  - Preserve strong LTR word order inside RTL visual paragraphs.
  - Keep existing numeric separator preservation and paired-bracket mirroring inside RTL runs.
  - Verify with focused unit tests and real Hebrew mixed-direction SVG smoke tests.

- [x] Step 17: Preserve LTR phrase connectors inside RTL paragraphs
  - Treat neutral phrase connectors as LTR only when bounded by strong/weak LTR content.
  - Preserve LTR phrases such as `A-B C` inside RTL visual paragraphs.
  - Keep standalone neutral punctuation with surrounding RTL run content.
  - Verify with focused unit tests and a real Hebrew mixed-direction SVG smoke test.

## Completion Criteria

- [x] `GSUB` and `GPOS` tables are successfully detected and parsed.
- [x] Single glyph substitutions (GSUB Type 1) are applied.
- [x] Ligature substitutions (GSUB Type 4) are applied, correctly merging multiple glyphs.
- [x] Single glyph adjustments (GPOS Type 1) are applied.
- [x] Pair adjustments (GPOS Type 2) are applied, correctly adjusting advances between glyphs.
- [x] `ShapedGlyph` records reflect substitutions and adjustments.
- [x] Legacy `kern` table still works as a fallback if GPOS is missing or produces no adjustment.
- [x] Arabic positional GSUB features are gated by computed joining form.
- [x] RTL numeric runs preserve their internal LTR order in visual output.
- [x] RTL numeric runs preserve attached numeric separators and signs in visual output.
- [x] Automatic paragraph direction follows the first strong codepoint at the tested scope.
- [x] Strong LTR words preserve internal order inside RTL visual paragraphs at the tested scope.
- [x] LTR phrase connectors preserve internal LTR phrase order inside RTL visual paragraphs at the tested scope.
- [x] Common paired punctuation glyphs mirror inside RTL visual runs at the tested scope.
- [x] Extended Unicode paired brackets mirror inside RTL visual runs when the font provides mirrored glyphs.
- [x] Missing mirrored glyphs fall back to the original glyph instead of failing shaping.
- [x] Indic pre-base matras can render before their base consonants at the tested scope.
- [x] Leading Devanagari ra + virama sequences can move after the consonant base at the tested scope.
- [x] Leading ra + virama repha fallback movement is script-aware across supported Brahmic scripts at the tested scope.
- [x] Existing parser and SVG rendering tests pass.
