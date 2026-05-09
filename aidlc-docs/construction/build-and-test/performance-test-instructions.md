# Performance Test Instructions

## Purpose

Validate parser performance characteristics when representative font fixtures are available.

## Performance Requirements

- **Initialization**: Validate table directory and scalar headers without eager glyph parsing.
- **Memory**: Keep font table access zero-copy; only table metadata is allocated during `Face.init`.
- **Lookup**: Use deterministic table lookup and `cmap` glyph lookup without internal caching.

## Current Status

Automated performance tests are not implemented in Unit 1 because no representative font fixture corpus is committed yet. The current build verifies correctness-focused unit tests only.

## Recommended Future Test

Add a benchmark or timed test that:

1. Loads representative TrueType and OpenType font buffers.
2. Measures `Face.init`.
3. Measures repeated `getGlyphId` and `getHMetric` calls for common codepoints.
4. Confirms allocations remain limited to table metadata.
