# Code Generation Summary - Unit 2: Shaping Engine

## Generated At

2026-05-09T01:58:13Z

## Scope

Implemented Unit 2 shaping increments for basic cmap shaping, legacy `kern`, initial GSUB/GPOS layout handling, caller-provided OpenType Layout script/language/feature selection, coarse automatic script/language tag inference, conservative default feature policy, Arabic joining-form positional GSUB gating, first-strong Bidi paragraph direction, RTL visual ordering with preserved LTR word/phrase and formatted numeric run order, RTL paired-bracket mirroring, mixed RTL run reordering, Indic pre-base matra visual reordering, script-aware Brahmic initial repha-sequence visual reordering, explicit top-to-bottom vertical layout, optional vertical metric lookup, and optional vertical origin lookup.

## Application Code

- Created `src/shaper.zig`
  - Defines `ShapeEngine`, `ShapedGlyph`, `ShapedText`, and `ShapeError`.
  - Implements `shapeText` for UTF-8 validation, glyph lookup, horizontal positioning, and total advance accumulation.
  - Implements legacy `kern` table version 0 horizontal format 0 pair adjustment.
  - Implements initial GSUB Single Substitution and Ligature Substitution.
  - Implements initial GPOS Single Adjustment and Pair Adjustment.
  - Adds `ShapeOptions` and `shapeTextWithOptions` for caller-selected script, language, and feature tags.
  - Infers a coarse OpenType script tag from input Unicode ranges when callers do not provide one, while preserving explicit caller tags.
  - Infers a coarse OpenType language tag for selected Unicode ranges when callers do not provide one, while preserving explicit caller tags.
  - Applies conservative default OpenType features when callers do not provide feature tags, while preserving explicit caller tags.
  - Classifies Arabic joining forms and applies `isol`/`init`/`medi`/`fina` GSUB single substitutions only to matching glyph positions.
  - Adds `ShapeDirection`, first-strong automatic paragraph direction, automatic RTL visual ordering with strong LTR word/phrase preservation through bounded neutral connectors plus ASCII and Arabic-Indic formatted numeric-run preservation, mixed RTL run reordering in LTR paragraphs, explicit top-to-bottom vertical layout, optional vertical metric lookup from `vhea`/`vmtx`, and optional vertical origin lookup from `VORG`.
  - Mirrors ASCII, common, and extended Unicode paired brackets inside RTL visual runs by resolving mirrored codepoints through cmap, with original-glyph fallback when the font lacks the mirrored glyph.
  - Reorders common Indic pre-base matras before the preceding consonant base after GSUB/GPOS while preserving per-glyph placement deltas, including expanded Telugu/Kannada/Malayalam coverage.
  - Reorders leading same-script Brahmic ra + virama sequences after the following consonant base when GSUB leaves the sequence decomposed.
  - Shares ScriptList/LangSys/FeatureList lookup index collection between GSUB and GPOS.
  - Validates OpenType Layout offset slices before dereferencing them.
  - Preserves legacy `kern` fallback when GPOS is absent or does not apply an adjustment.
  - Adds invalid UTF-8, coverage/class definition, GSUB, GPOS adjustment detection, OpenType Layout lookup selection, checked slicing, and kern format 0 lookup test coverage.

- Modified `src/root.zig`
  - Re-exports Unit 2 shaping types and `ShapeOptions`.

- Modified `src/main.zig`
  - Routes `--text` glyph display through `ShapeEngine`.
  - Displays cluster, codepoint, glyph ID, x offset, x advance, kern adjustment, left side bearing, and total advance.

## Verification

- Command: `zig fmt src/shaper.zig src/root.zig src/main.zig`
- Result: Passed
- Command: `zig build test`
- Result: Passed
- Command: `zig build`
- Result: Passed
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text Aあ`
- Result: Passed
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text AV`
- Result: Passed; displayed legacy kern adjustment `-131` for the `A`/`V` pair.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text AV --quiet`
- Result: Passed; displayed legacy kern adjustment `-131` after GSUB/GPOS integration.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text fi --quiet`
- Result: Passed; exercised GSUB/GPOS shaping path with a real font.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text AV --output /tmp/zig-font-renderer-gpos-av.svg --font-size 96`
- Result: Passed; SVG generation still works with GSUB/GPOS shaping path.
- Command: `wc -c /tmp/zig-font-renderer-gpos-av.svg`
- Result: `523 /tmp/zig-font-renderer-gpos-av.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text fi --quiet`
- Result: Passed after adding OpenType Layout selection.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text AV --output /tmp/zig-font-renderer-shape-options-av.svg --font-size 96`
- Result: Passed after adding OpenType Layout selection.
- Command: `wc -c /tmp/zig-font-renderer-shape-options-av.svg`
- Result: `523 /tmp/zig-font-renderer-shape-options-av.svg`
- Command: `zig build run -- --font /usr/share/fonts/opentype/ipafont-gothic/ipag.ttf --text かな --quiet`
- Result: Passed after adding automatic script tag inference and fallback.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text İstanbul --quiet`
- Result: Passed after adding automatic language tag inference and fallback.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text fi --quiet`
- Result: Passed after adding default feature policy.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text שלום --quiet`
- Result: Passed after adding RTL-only visual ordering.
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf --text سلام --output /tmp/zig-font-renderer-arabic-joining.svg --font-size 96`
- Result: Passed after adding Arabic joining-form GSUB feature gating.
- Command: `wc -c /tmp/zig-font-renderer-arabic-joining.svg`
- Result: `4076 /tmp/zig-font-renderer-arabic-joining.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf --text سلام123 --output /tmp/zig-font-renderer-rtl-digits.svg --font-size 96`
- Result: Passed after preserving weak LTR numeric run order inside RTL visual ordering.
- Command: `wc -c /tmp/zig-font-renderer-rtl-digits.svg`
- Result: `5976 /tmp/zig-font-renderer-rtl-digits.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf --text कि --output /tmp/zig-font-renderer-devanagari-prebase.svg --font-size 96`
- Result: Passed after adding Indic pre-base matra visual reordering.
- Command: `wc -c /tmp/zig-font-renderer-devanagari-prebase.svg`
- Result: `1702 /tmp/zig-font-renderer-devanagari-prebase.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf --text र्क --quiet`
- Result: Passed after adding Devanagari repha-sequence visual reordering. The real font applies GSUB repha substitution before the fallback visual reordering path.
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf --text र्क --output /tmp/zig-font-renderer-devanagari-repha.svg --font-size 96`
- Result: Passed.
- Command: `wc -c /tmp/zig-font-renderer-devanagari-repha.svg`
- Result: `1337 /tmp/zig-font-renderer-devanagari-repha.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf --text 'אב(12)' --output /tmp/zig-font-renderer-bidi-mirror.svg --font-size 96`
- Result: Passed after adding RTL paired punctuation mirroring.
- Command: `wc -c /tmp/zig-font-renderer-bidi-mirror.svg`
- Result: `1748 /tmp/zig-font-renderer-bidi-mirror.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf --text 'אב⟨12⟩' --output /tmp/zig-font-renderer-bidi-extended-mirror.svg --font-size 96`
- Result: Passed after broadening paired-bracket mirroring.
- Command: `wc -c /tmp/zig-font-renderer-bidi-extended-mirror.svg`
- Result: `1650 /tmp/zig-font-renderer-bidi-extended-mirror.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf --text 'אב1,234.56ג' --output /tmp/zig-font-renderer-rtl-number-separators.svg --font-size 96`
- Result: Passed after preserving numeric separators inside RTL numeric runs.
- Command: `wc -c /tmp/zig-font-renderer-rtl-number-separators.svg`
- Result: `2787 /tmp/zig-font-renderer-rtl-number-separators.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansBengali-Regular.ttf --text 'র্কি' --output /tmp/zig-font-renderer-bengali-repha-prebase.svg --font-size 96`
- Result: Passed after broadening Indic fallback reordering.
- Command: `wc -c /tmp/zig-font-renderer-bengali-repha-prebase.svg`
- Result: `2791 /tmp/zig-font-renderer-bengali-repha-prebase.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansTelugu-Regular.ttf --text 'కె' --output /tmp/zig-font-renderer-telugu-prebase.svg --font-size 96`
- Result: Passed after broadening pre-base matra coverage.
- Command: `wc -c /tmp/zig-font-renderer-telugu-prebase.svg`
- Result: `2265 /tmp/zig-font-renderer-telugu-prebase.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf --text 'אב ABC ג' --output /tmp/zig-font-renderer-bidi-first-strong-rtl.svg --font-size 96`
- Result: Passed after adding first-strong RTL paragraph handling with LTR run preservation.
- Command: `wc -c /tmp/zig-font-renderer-bidi-first-strong-rtl.svg`
- Result: `2036 /tmp/zig-font-renderer-bidi-first-strong-rtl.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf --text 'ABC אב' --output /tmp/zig-font-renderer-bidi-first-strong-ltr.svg --font-size 96`
- Result: Passed after keeping LTR-first mixed text in LTR paragraph handling.
- Command: `wc -c /tmp/zig-font-renderer-bidi-first-strong-ltr.svg`
- Result: `1597 /tmp/zig-font-renderer-bidi-first-strong-ltr.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf --text 'אב A-B C ג' --output /tmp/zig-font-renderer-bidi-ltr-connectors.svg --font-size 96`
- Result: Passed after preserving LTR phrase connectors inside RTL visual paragraphs.
- Command: `wc -c /tmp/zig-font-renderer-bidi-ltr-connectors.svg`
- Result: `2123 /tmp/zig-font-renderer-bidi-ltr-connectors.svg`

## Known Limitations

- Full Unicode Bidi algorithm coverage beyond the current first-strong/run-level heuristic plus paired-bracket mirroring and full Indic syllable shaping/reordering beyond the implemented visual reorderings are not implemented.
