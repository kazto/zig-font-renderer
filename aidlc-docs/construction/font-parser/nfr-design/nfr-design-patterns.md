# NFR Design Patterns - Unit 1: Font Parser

## 1. Performance Patterns
- **Stateless Extraction**: The parser acts as a stateless data extractor. It does not cache glyph information internally, delegating caching responsibility to the caller. This keeps the memory footprint of the `Face` object constant and small.
- **Lazy Table Directory**: Only the table directory is parsed during initialization. Actual table data is accessed only when needed by jumping to the pre-calculated offset.
- **Zero-Copy Data Access (Hybrid)**:
    - For bulk data (like raw glyph bytes), the parser returns a slice (`[]const u8`) pointing directly into the original font buffer.
    - For structured data (like glyph points), if a Zig-native representation is needed, it will be generated. However, the design aims to minimize intermediate copies.

## 2. Security & Robustness Patterns
- **Manual Bounds Checking (Performance Optimized)**:
    - Instead of wrapping every small read in a heavy abstraction, the parser validates "segment boundaries" before performing direct pointer/slice access.
    - Example: Before parsing a glyph, the parser ensures the entire glyph entry range (as defined in `loca`) is within the total buffer bounds.
- **Fail-Fast with Context**: On any boundary violation or logical error (e.g., invalid offsets within a table), the parser returns an error immediately, preventing any potentially unsafe memory access.

## 3. Concurrency & Lifetime
- **Thread-Unsafe by Design**: The library provides no internal synchronization (No Mutex). This avoids overhead for the primary real-time single-threaded rendering loop. Callers are responsible for synchronization if sharing a `Face` across threads.
- **Buffer Ownership**: The `Face` object maintains a reference to the source buffer. The caller must ensure the buffer outlives the `Face` object (borrowing pattern).
