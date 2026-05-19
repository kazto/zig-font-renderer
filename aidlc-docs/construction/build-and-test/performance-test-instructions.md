# Performance Test Instructions

## Purpose

Validate parser, shaping, and SVG rendering performance characteristics when representative font fixtures are available.

## Performance Requirements

- **Initialization**: Validate table directory and scalar headers without eager glyph parsing.
- **Memory**: Keep font table access zero-copy; only table metadata is allocated during `Face.init`.
- **Lookup**: Use deterministic table lookup and `cmap` glyph lookup without internal caching.
- **Shaping/SVG**: Exercise representative Latin, Arabic, Indic, and CFF text paths when matching system fonts are present.

## Current Status

`zig build perf` runs optional performance smoke tests. The step looks for representative system fonts and skips missing fonts without failing the build, so the repository still does not require committed font fixtures.

## Run

```bash
zig build perf
```

## Coverage

1. Loads representative TrueType and OpenType/CFF font buffers when present.
2. Measures repeated `Face.init`.
3. Measures repeated `getGlyphId` and `getHMetric` calls for common codepoints.
4. Measures repeated shaping of representative text.
5. Measures repeated SVG rendering of representative text.
