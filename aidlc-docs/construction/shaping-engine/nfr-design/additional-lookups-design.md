# NFR Design - Unit 2 Extension: Additional GSUB/GPOS Lookups

This document defines the NFR design for additional OpenType Layout features, ensuring consistent safety and efficiency across all lookup types.

## Performance Design

- **Mark Stacking Search**: Backward scan for the preceding mark in Mark-to-Mark attachment; additional optimization remains available if profiling shows pathological input costs.
- **Shared Matching Engine**: Re-use the contextual matching logic from Type 6 for Type 5 (Contextual), avoiding code duplication and ensuring consistent performance characteristics.
- **Alternate Selection**: Direct lookup of AlternateSets with zero search overhead.

## Safety & Security Design

- **Ligature Component Bounds**: In Mark-to-Ligature attachment, derive the selected component from glyph cluster distance and clamp it to the available component count.
- **Mark1 Validation**: Ensure that the "base mark" in Mark-to-Mark attachment actually exists and has an anchor for the required class.
- **Anchor Offset Validation**: Continue strict validation of all anchor offsets (Mark2Array, Mark1Array, LigatureArray, etc.) before slicing.

## Memory Design

- **Stateless Sub-lookups**: Ensure that contextual sub-lookups don't require auxiliary heap memory for their execution.
- **Zero-Copy Transformation**: Apply alternate substitutions by replacing glyph IDs in-place within the `ShapedGlyph` stream.
