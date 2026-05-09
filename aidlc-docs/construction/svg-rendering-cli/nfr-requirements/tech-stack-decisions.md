# Tech Stack Decisions - Unit 3: SVG Rendering & CLI

## Language and Runtime

- Zig 0.15.2
- Zig standard library only

## Output Format

- SVG 1.1-compatible path output.

## Rationale

SVG path output gives immediate visual feedback while preserving the Pure Zig dependency policy. The first increment targets TrueType simple glyphs because they are directly available from Unit 1's `glyf` table access.
