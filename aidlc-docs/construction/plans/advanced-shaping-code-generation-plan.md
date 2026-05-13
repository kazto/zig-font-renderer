# Code Generation Plan - Unit 2 Extension: Advanced GSUB/GPOS

This plan covers the implementation of GPOS Type 4 (Mark-to-Base) and GSUB Type 6 (Chained Contextual Substitution) in the Shaping Engine.

## Unit Context

- **Unit**: Shaping Engine (Unit 2 Extension)
- **Primary story**: US-3 - カーニングと合字のサポート (Extended for marks and context)
- **Dependencies**: Unit 1 `Face`, Unit 2 Basic Layout
- **Application code paths**:
  - `src/shaper.zig`

## Execution Checklist

- [x] Step 1: Implement GPOS Type 4: Mark-to-Base Attachment
  - [x] Implement `AnchorTable` parsing (Formats 1, 2, 3).
  - [x] Implement `MarkArray` and `BaseArray` parsing.
  - [x] Implement Mark-to-Base positioning logic in `applyGposLookup`.
  - [x] Handle mark glyph identification and base glyph searching.
  - [x] Update `ShapedGlyph` offsets and advances.

- [x] Step 2: Implement GSUB Type 6: Chained Contextual Substitution
  - [x] Implement Format 3 (Coverage-based).
  - [ ] Defer Format 1 (Simple) and Format 2 (Class-based).
  - [x] Implement contextual matching logic for backtrack, input, and lookahead sequences.
  - [x] Add recursive lookup application with a hard depth limit (16).
  - [x] Handle glyph ID replacement after contextual sub-lookups.
  - [x] Handle contextual sub-lookups that change glyph stream length.

- [x] Step 3: Hardening and Validation
  - [x] Add explicit offset checks for all newly introduced subtables.
  - [x] Add unit tests for Mark-to-Base attachment.
  - [x] Add unit tests for Chained Contextual Format 3 substitution.
  - [x] Add a regression test for recursion depth limiting.
  - [x] Verify that existing shaping (kern, ligatures) still works.

## Completion Criteria

- [x] GPOS Type 4 lookups correctly position marks relative to bases.
- [x] GSUB Type 6 Format 3 lookups correctly substitute glyphs based on coverage-based context.
- [x] Recursion depth limit rejects excessive recursive GSUB lookup application.
- [x] All subtable accesses are bounds-checked.
- [x] `zig build test` passes.
- [ ] SVG output for real fonts using these features still needs targeted visual verification.
