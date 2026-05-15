# Code Generation Plan - Unit 2 Extension: Additional GSUB/GPOS Lookups

This plan covers the implementation of GPOS Type 5 (Mark-to-Ligature), GPOS Type 6 (Mark-to-Mark), GSUB Type 3 (Alternate Substitution), and GSUB Type 5 (Contextual Substitution) in the Shaping Engine.

## Unit Context

- **Unit**: Shaping Engine (Unit 2 Extension)
- **Primary story**: US-3 - カーニングと合字のサポート (Extended for mark stacking and alternates)
- **Dependencies**: Unit 1 `Face`, Unit 2 Advanced Layout
- **Application code paths**:
  - `src/shaper.zig`

## Execution Checklist

- [x] Step 1: Implement GSUB Type 3: Alternate Substitution
  - [x] Implement `AlternateSet` parsing.
  - [x] Implement substitution logic (default to first alternate).
  - [x] Add unit test for alternate replacement.

- [x] Step 2: Implement GSUB Type 5: Contextual Substitution
  - [x] Refactor `applyChainedContextualFormat3` matching logic to be reusable.
  - [x] Implement Type 5 Format 3 (coverage-based).
  - [x] Implement Type 5 Format 1 (glyph sequence) and Format 2 (class-based).
  - [x] Add dedicated unit tests for Type 5 contextual substitution.
  - [x] Handle contextual sub-lookups that change glyph stream length.

- [x] Step 3: Implement GPOS Type 6: Mark-to-Mark Attachment
  - [x] Implement `Mark2Array` and `Mark1Array` parsing.
  - [x] Implement Mark-to-Mark positioning logic (align Mark2 anchor with Mark1 anchor).
  - [x] Add unit test for stacked marks.

- [x] Step 4: Implement GPOS Type 5: Mark-to-Ligature Attachment
  - [x] Implement `LigatureArray` and `ComponentRecord` parsing.
  - [x] Implement Mark-to-Ligature positioning logic for mark class anchors.
  - [x] Improve component index resolution for real ligature component selection.
  - [x] Add unit test for ligature marks.

- [x] Step 5: Hardening and Validation
  - [x] Add bounds checks for component indices in Mark-to-Ligature.
  - [x] Add bounds checks for mark classes in Mark-to-Mark.
  - [x] Verify that existing shaping (Single, Ligature, Contextual Type 6, Mark-to-Base) still works.
  - [x] Run `zig build test`.

## Completion Criteria

- [x] GSUB Type 3 lookups correctly substitute glyphs with their first alternate.
- [x] GSUB Type 5 Format 3 lookups apply sub-lookups based on coverage context.
- [x] GSUB Type 5 Format 1/2 lookups apply sub-lookups based on glyph and class context.
- [x] Contextual sub-lookups can update the glyph stream when substitutions change length.
- [x] GPOS Type 6 lookups correctly position marks relative to other marks.
- [x] GPOS Type 5 lookups position marks relative to tested ligature anchors.
- [x] All subtable accesses are bounds-checked.
- [x] `zig build test` passes.
