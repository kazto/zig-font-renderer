# Code Generation Plan - Unit 2: Shaping Engine

This plan covers the first incremental implementation for Unit 2. It intentionally implements US-2 basic shaping before GSUB/GPOS complexity.

## Unit Context

- **Unit**: Shaping Engine
- **Primary story**: US-2 - ラテン文字と日本語の基本シェイピング
- **Deferred story**: US-3 - カーニングと合字のサポート (GSUB/GPOS)
- **Dependency**: Unit 1 `Face` parser API
- **Application code paths**:
  - `src/shaper.zig`
  - `src/root.zig`
  - `src/main.zig`

## Execution Checklist

- [x] Step 1: Add `src/shaper.zig`
  - Define `ShapeEngine`, `ShapedGlyph`, `ShapedText`, and `ShapeError`.

- [x] Step 2: Implement basic UTF-8 text shaping
  - Convert UTF-8 codepoints to glyph IDs through `Face.getGlyphInfo`.
  - Assign monotonically increasing cluster indexes.
  - Accumulate horizontal pen positions in raw FUnits.

- [x] Step 3: Export Shaping Engine API
  - Re-export Unit 2 public types from `src/root.zig`.

- [x] Step 4: Wire CLI text inspection through Shaping Engine
  - Use `ShapeEngine.shapeText` for `--text` glyph display.
  - Display cluster, codepoint, glyph ID, x offset, x advance, and total advance.

- [x] Step 5: Add focused tests and verification
  - Add invalid UTF-8 coverage for `ShapeEngine`.
  - Run `zig build test`, `zig build`, and real-font CLI smoke tests.

## Completion Criteria

- [x] Unit 2 basic shaping API exists.
- [x] CLI uses the shaping API for text glyph display.
- [x] Existing parser tests still pass.
- [x] GSUB/GPOS remains explicitly deferred.
