# NFR Design Patterns - Unit 3: SVG Rendering & CLI

## Bounded Binary Reads

All font table reads use explicit length checks before reading big-endian values.

## Streaming Document Assembly

The renderer appends SVG text into an `ArrayList(u8)` and returns an owned slice to the caller.

## Scoped Temporary Allocation

Contour endpoint, flag, and point arrays are allocated per glyph and freed before the next glyph is processed.

## Bounded Recursion

Composite glyph expansion uses a fixed recursion limit to prevent malformed component graphs from recursing indefinitely.

## Transform-Based Scaling

Raw font-unit path coordinates are preserved in path data, while the SVG group transform maps them to pixel output. This keeps path generation simple and avoids rounding geometry during extraction.
