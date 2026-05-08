# Business Logic Model - Unit 1: Font Parser

## 1. Font Loading & Validation Workflow
1. **Binary Data Receipt**: `Face.init` receives a byte slice (`[]const u8`) containing the entire font file.
2. **Initial Header Check**: Validate the magic number (e.g., `0x00010000` for TrueType or `OTTO` for OpenType).
3. **Table Directory Parsing**: Read the number of tables and iterate to find mandatory tables.
4. **Mandatory Table Check**: Verify existence of `head`, `cmap`, `maxp`, `hhea`, `hmtx`, and `glyf` (or `CFF `).
5. **Table Mapping**: Store offsets and lengths of each found table for lazy access.

## 2. Character to Glyph Mapping (cmap)
- **Logic**: Implement a search algorithm that prioritizes Windows Unicode (Platform 3, Encoding 1/10) sub-tables.
- **Mapping Process**:
    1. Scan `cmap` sub-tables.
    2. Select the highest priority sub-table found.
    3. Provide a mapping function: `Codepoint (U32) -> GlyphID (U16)`.
    4. If no mapping exists, return Glyph ID 0 (the ".notdef" glyph).

## 3. Metric & Coordinate Handling
- **Coordinate System**: Retain raw `FUnits` as defined in the font.
- **Scaling Logic**: The Parser provides the `UnitsPerEm` (UPM) value from the `head` table. Scaling calculation is deferred to the Rendering unit.
- **Metrics Retrieval**: Provide logic to fetch `advanceWidth` and `lsb` (left side bearing) from the `hmtx` table using a Glyph ID.

## 4. Glyph Extraction
- **Scope**: Focus on "Simple Glyphs" for initial implementation.
- **Logic**:
    1. Locate glyph offset using the `loca` table.
    2. Parse glyph header (number of contours, bounding box).
    3. Read contour endpoints and coordinate deltas.
    4. Convert deltas into absolute `FUnits` coordinates.
