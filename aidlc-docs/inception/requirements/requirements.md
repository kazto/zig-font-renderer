# Requirements Document

## Intent Analysis Summary
- **User Request**: Zig言語を用いて、TrueType/OpenTypeフォントを読み込んでテキストをSVGにレンダリングするシステム（Pure Zig実装）。
- **Request Type**: New Project (Development from scaffold)
- **Scope Estimate**: Single Component (Font Renderer Library/CLI)
- **Complexity Estimate**: Complex (Due to Pure Zig requirement for shaping and rendering)

## Functional Requirements
- **Font Support**: 
    - Support for TrueType (.ttf) and OpenType (.otf) formats.
- **Rendering Output**:
    - Primary output format: **SVG**.
    - SVG details: Output character outlines using `<path>` elements.
- **Text Layout (Shaping)**:
    - Advanced shaping support: Implementation of complex script shaping (comparable to HarfBuzz), including kerning and ligatures.
- **CLI Interface**:
    - Provide a command-line interface to take text, font file, and output path as arguments.

## Non-Functional Requirements
- **Dependency Restrictions**:
    - **Pure Zig**: No external C libraries (FreeType, HarfBuzz, etc.) are allowed. All parsing, shaping, and rendering logic must be implemented in Zig.
- **Performance & Use Case**:
    - Targeting real-time rendering scenarios (e.g., games or GUI applications).
- **Maintainability**:
    - Code should be modular to allow future extension to other output formats (like raster images).

## Key Decisions
- Priority is set to SVG output first.
- Shaping logic will be a significant part of the implementation to meet "HarfBuzz-like" requirements within Pure Zig.
