# NFR Requirements - Unit 2: Shaping Engine

## Performance

- Shape text in a single pass over UTF-8 input.
- Avoid copying font data.
- Allocate only the shaped glyph output slice.
- Apply legacy `kern` pair lookup without allocating auxiliary kerning maps.

## Reliability

- Invalid UTF-8 must return a clear error.
- Parser errors from Unit 1 must propagate without being hidden.
- Malformed `kern` tables must fail with a parser table error rather than reading past bounds.

## Security

- All font table bounds validation remains owned by Unit 1.
- The shaping layer must not perform unchecked pointer arithmetic.

## Maintainability

- Keep basic shaping separate from future GSUB/GPOS implementation.
- Preserve a stateless `ShapeEngine` so future table-specific helpers can be added without changing callers.
