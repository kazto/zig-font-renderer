# Business Rules - Unit 1: Font Parser

## 1. Validation Rules
- **Rule-VALID-MAGIC**: Font must start with `0x00010000` (TrueType) or `OTTO` (OpenType/CFF). Otherwise, reject with `InvalidFontFormat`.
- **Rule-MANDATORY-TABLES**: Must contain `head`, `cmap`, `maxp`, `hhea`, `hmtx`, and `glyf`. If any are missing, reject with `MissingMandatoryTable`.
- **Rule-STRUCTURAL-ONLY**: Do NOT verify checksums for performance and compatibility. Validate only that offsets and lengths remain within the provided binary slice.

## 2. Parsing Rules
- **Rule-BIG-ENDIAN**: All multi-byte integers in TTF/OTF are Big Endian. Parser must convert these to native endianness.
- **Rule-LAZY-LOADING**: Do not parse the entire font into memory structures at once. Store table pointers and parse specific data (like glyph outlines) only when requested.
- **Rule-CMAP-PRIORITY**: 
    1. Platform 3 (Windows), Encoding 10 (UCS-4)
    2. Platform 3 (Windows), Encoding 1 (UCS-2)
    3. Platform 0 (Unicode)
    4. Fallback to the first available sub-table if none of the above are found.

## 3. Coordinate & Unit Rules
- **Rule-RAW-FUNITS**: Output coordinates MUST be in raw `FUnits` (integers). No floating-point scaling occurs in this unit.
- **Rule-Y-UP**: Maintain the font's native "Y-up" coordinate system (positive Y is up).

## 4. Constraint Rules
- **Rule-SIMPLE-ONLY**: Initially, if a glyph is a "Composite Glyph" (multiple components), return an `UnsupportedGlyphType` error.
- **Rule-NOTDEF-FALLBACK**: If a codepoint is not found in the `cmap`, ALWAYS return Glyph ID 0.
