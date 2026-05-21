# Tech Stack Decisions - Unit 1: Font Parser

## 1. Core Language & Build System
- **Decision**: **Zig 0.16.0**
- **Rationale**: User mandate for a Pure Zig implementation. The project now targets Zig 0.16.0, using the current `std.Io` and `std.heap.DebugAllocator` APIs while preserving explicit memory management and bounds-checked binary parsing.

## 2. Dependency Strategy
- **Decision**: **Zero External Dependencies**
- **Rationale**: Strict mandate for "Pure Zig". All parsing logic for TTF/OTF (Apple/Microsoft specifications) will be implemented using the Zig Standard Library only.

## 3. Data Handling Pattern
- **Decision**: **Slice-based Big-Endian Parsers**
- **Rationale**: Using local big-endian binary reader helpers and Zig standard library primitives for safe and efficient binary reading.

## 4. Optimization Strategy
- **Decision**: **Cross-Platform SIMD (Planned)**
- **Rationale**: Leverage `std.simd` where applicable (e.g., mass coordinate scaling) while maintaining a portable Zig codebase. Initial focus will be on correctness, with performance hooks integrated for future SIMD optimization.
