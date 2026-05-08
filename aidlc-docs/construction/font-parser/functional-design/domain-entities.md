# Domain Entities - Unit 1: Font Parser

## 1. Face (Root Entity)
Represents a single font face loaded from binary data.
- **Attributes**:
    - `data`: Raw byte slice of the font file.
    - `units_per_em`: UPM value (e.g., 2048).
    - `num_glyphs`: Total number of glyphs in the font.
    - `tables`: A collection/map of metadata for each table (tag, offset, length).

## 2. TableMetadata (Value Object)
Internal metadata for locating tables.
- **Attributes**:
    - `tag`: 4-byte tag (e.g., 'head').
    - `offset`: Offset from the start of the file.
    - `length`: Length of the table data.

## 3. GlyphInfo (Value Object)
Basic information about a glyph.
- **Attributes**:
    - `id`: The 16-bit Glyph ID.
    - `advance_width`: Horizontal advance in `FUnits`.
    - `lsb`: Left side bearing in `FUnits`.

## 4. Outline (Entity)
The geometric representation of a glyph.
- **Attributes**:
    - `points`: List of coordinate points (X, Y) and their flags (on-curve/off-curve).
    - `contours`: Indices indicating the end of each contour in the `points` list.

## 5. Point (Value Object)
A single coordinate in the font's 2D space.
- **Attributes**:
    - `x`: Integer coordinate (FUnits).
    - `y`: Integer coordinate (FUnits).
    - `on_curve`: Boolean indicating if this is an anchor point or a control point.
