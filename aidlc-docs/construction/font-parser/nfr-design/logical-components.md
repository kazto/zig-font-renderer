# Logical Components - Unit 1: Font Parser

## 1. Binary Stream Abstraction
- **Purpose**: Provides a low-level interface to read Big-Endian integers from the font buffer with safety checks.
- **Pattern**: A simple wrapper around a byte slice using `std.mem.readIntBig`.
- **Implementation Note**: Uses Zig's `@ptrCast` for fast data mapping where appropriate after manual bounds validation.

## 2. Table Directory Map
- **Purpose**: Fast lookup for font table locations (e.g., "Where is the `glyf` table?").
- **Pattern**: An array of `TableMetadata` sorted by tag to allow O(log N) binary search lookup.

## 3. Glyph Locator (loca)
- **Purpose**: Translates a Glyph ID into a byte offset within the `glyf` table.
- **Logic**: Handles both Short (16-bit) and Long (32-bit) formats based on the `head` table's `indexToLocFormat`.

## 4. Error Context Tracker (Optional/Debug)
- **Purpose**: Provides detailed info when a parse fails.
- **Pattern**: Standard Zig error return with a dedicated error enum, potentially using a simple struct to capture the failing table tag and offset in debug builds.
