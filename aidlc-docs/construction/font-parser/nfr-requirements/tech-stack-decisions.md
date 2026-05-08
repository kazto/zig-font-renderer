# Tech Stack Decisions - Unit 1: Font Parser

## 1. Core Language & Build System
- **Decision**: **Zig 0.15.2**
- **Rationale**: User mandate for a Pure Zig implementation. Zig provides native big-endian to native-endian conversion utilities, explicit memory management, and excellent safety features (bounds checking by default) suitable for binary parsing.

## 2. Dependency Strategy
- **Decision**: **Zero External Dependencies**
- **Rationale**: Strict mandate for "Pure Zig". All parsing logic for TTF/OTF (Apple/Microsoft specifications) will be implemented using the Zig Standard Library only.

## 3. Data Handling Pattern
- **Decision**: **Slice-based Big-Endian Parsers**
- **Rationale**: Using `std.mem.readIntBig` and `std.io.fixedBufferStream` for safe and efficient binary reading.

## 4. Optimization Strategy
- **Decision**: **Cross-Platform SIMD (Planned)**
- **Rationale**: Leverage `std.simd` where applicable (e.g., mass coordinate scaling) while maintaining a portable Zig codebase. Initial focus will be on correctness, with performance hooks integrated for future SIMD optimization.
