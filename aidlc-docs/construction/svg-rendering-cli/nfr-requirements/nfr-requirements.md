# NFR Requirements - Unit 3: SVG Rendering & CLI

## Performance

- Render in a single pass over shaped glyphs.
- Avoid copying font tables.
- Allocate temporary per-glyph point arrays only while rendering each glyph.

## Reliability

- Bounds-check all `head`, `loca`, and `glyf` reads.
- Bound composite glyph recursion.
- Return explicit errors for unsupported composite transforms.
- Preserve existing parser and shaper behavior.

## Security

- Treat font data as untrusted binary input.
- Reject malformed glyph ranges and coordinate streams.
- Reject composite component records that would read past glyph bounds.

## Usability

- Provide a simple CLI path to visible output through `--output`.
