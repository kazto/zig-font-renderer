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
- Provide `--font-size` so generated SVGs have predictable display dimensions.
- Keep `--output` mode quiet enough for script usage.
- Avoid clipping descenders and accents by sizing from actual glyph bounds.
- Provide a one-call library API for common render-to-SVG usage.

## Resource Limits

- High-level file loading must enforce a maximum font size.
