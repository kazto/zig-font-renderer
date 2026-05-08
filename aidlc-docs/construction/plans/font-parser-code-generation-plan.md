# Code Generation Plan - Unit 1: Font Parser

This plan is the single source of truth for Unit 1 Code Generation. Application code will be written only under the workspace root, not under `aidlc-docs/`.

## Unit Context

- **Unit**: Font Parser
- **Primary story**: US-1 - TrueType/OpenTypeファイルの解析 (Pure Zig)
- **Project type**: Brownfield Zig library/CLI scaffold
- **Language and toolchain**: Zig 0.15.2
- **Dependency policy**: Zero external dependencies; Zig standard library only
- **Application code paths**:
  - `src/root.zig`
  - `src/font_parser.zig`
  - `src/main.zig`
- **Documentation path**:
  - `aidlc-docs/construction/font-parser/code/`

## Dependencies and Boundaries

- Unit 1 owns `Face`, table metadata, glyph ID lookup, horizontal metrics, and raw glyph table access.
- Unit 1 must expose stable parser APIs for Unit 2 Shaping Engine and Unit 3 SVG Rendering & CLI.
- Unit 1 does not perform shaping, coordinate scaling, SVG generation, glyph caching, or thread synchronization.
- `Face` borrows the source font buffer; callers must keep the buffer alive for the lifetime of `Face`.
- Parsing must be lazy: initialization reads table metadata and mandatory scalar headers only; detailed glyph data is read on demand.

## Implementation Rules

- Validate font flavor `0x00010000` or `OTTO`.
- Read all multi-byte font integers as big endian.
- Validate table offsets and lengths before slicing.
- Do not verify table checksums.
- Prefer stateless extraction and avoid internal glyph caches.
- Preserve raw FUnits and Y-up coordinates.
- Return glyph ID 0 when a codepoint is missing from `cmap`.
- Initially support simple direct data access and metrics; complex/composite glyph outline parsing remains outside this unit's first code generation pass.

## Story Traceability

- [x] US-1: Parse TrueType/OpenType font data in Pure Zig
  - Covered by Steps 1-8.

## Execution Checklist

- [x] Step 1: Update module exports in `src/root.zig`
  - Replace template exports with the public Font Parser API.
  - Re-export `Face`, `GlyphInfo`, `HMetric`, `TableMetadata`, and parser errors from `src/font_parser.zig`.

- [x] Step 2: Create core parser module in `src/font_parser.zig`
  - Define `Face`, `TableMetadata`, `HMetric`, `GlyphInfo`, internal table directory structures, and error set.
  - Implement small big-endian read helpers with explicit bounds validation.

- [x] Step 3: Implement `Face.init`
  - Validate font flavor.
  - Parse table directory.
  - Validate table ranges against the source buffer.
  - Load required scalar values from `head`, `maxp`, `hhea`, and `hmtx`.
  - Store table metadata for lazy access.

- [x] Step 4: Implement table lookup and raw table access
  - Provide `getTable(tag)` and internal required-table helpers.
  - Provide raw slices for `glyf`, `CFF `, and other known tables where present.
  - Keep returned slices zero-copy.

- [x] Step 5: Implement character map selection and glyph lookup
  - Select `cmap` subtables using the documented priority order.
  - Implement at least `cmap` format 4 and format 12 lookup.
  - Return glyph ID 0 for missing codepoints.

- [x] Step 6: Implement horizontal metrics access
  - Parse `hhea.numberOfHMetrics`.
  - Implement `getHMetric(glyph_id)` with correct fallback for glyph IDs beyond `numberOfHMetrics`.
  - Return advance width and left side bearing in raw FUnits.

- [x] Step 7: Add focused unit tests
  - Test invalid flavor rejection.
  - Test table-range validation.
  - Test minimal `head`, `maxp`, `hhea`, `hmtx`, and `cmap` parsing using synthetic in-memory font data.
  - Test missing codepoint fallback to glyph ID 0.

- [x] Step 8: Update CLI scaffold only as needed
  - Remove template demo behavior from `src/main.zig`.
  - Keep CLI functionality minimal until Unit 3, avoiding premature rendering behavior.

- [x] Step 9: Create Unit 1 code summary
  - Write `aidlc-docs/construction/font-parser/code/code-generation-summary.md`.
  - Summarize created and modified files, public APIs, tests, and known limitations.

- [x] Step 10: Run local verification
  - Run `zig build test`.
  - Fix compile/test failures within Unit 1 scope.
  - Record verification result in the code summary.

## Completion Criteria

- [x] All checklist items above are marked complete immediately after execution.
- [x] US-1 traceability is marked complete when parser API and tests are in place.
- [x] No duplicate brownfield files are created.
- [x] Application code remains outside `aidlc-docs/`.
- [x] Documentation remains Markdown-only under `aidlc-docs/construction/font-parser/code/`.
