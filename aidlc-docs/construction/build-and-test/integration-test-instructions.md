# Integration Test Instructions

## Purpose

Validate the integration boundaries across all components (Parser, Shaper, SVG Renderer, static/shared library artifacts, and CLI wrapper executable), including advanced GPOS Complex Typography features.

## Test Scenarios

### Scenario 1: Full Layout and Rendering Pipeline (Parser -> Shaper -> Renderer -> CLI)

- **Description**: Verify that the CLI successfully parses an OpenType font, applies GSUB/GPOS shaping features, translates coordinates into vector SVG paths, and exports the resulting markup.
- **Setup**: Zig 0.16.0 installed, and system font files (e.g., DejaVuSans.ttf) available.
- **Test Steps**:
  1. Build the release binary: `zig build`
  2. Run layout and render: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text "AV" --output /tmp/integration-test-gpos.svg --font-size 96`
- **Expected Results**:
  - The CLI command completes with exit code 0.
  - The SVG file `/tmp/integration-test-gpos.svg` is generated and contains valid XML markup with `<path>` elements representing styled and spaced glyphs.
- **Cleanup**: Delete `/tmp/integration-test-gpos.svg` after verification.

### Scenario 2: Public API Exports via Root Module

- **Description**: Ensure `src/root.zig` exposes full APIs (Face, ShapeEngine, SVG Renderer structures) properly to external packages.
- **Setup**: Zig 0.16.0 installed.
- **Test Steps**: Run `zig build test`.
- **Expected Results**: All unit and module integration tests pass successfully without compiler package mapping issues.
- **Cleanup**: No cleanup required.

### Scenario 3: Static/Shared Library and Wrapper Artifact Split

- **Description**: Ensure the default build produces static library, shared library, and CLI wrapper executable artifacts.
- **Setup**: Zig 0.16.0 installed.
- **Test Steps**:
  1. Run `zig build`.
  2. Run `find zig-out -maxdepth 3 -type f`.
- **Expected Results**:
  - `zig-out/lib/libzig_font_renderer.a` exists.
  - `zig-out/lib/libzig_font_renderer.so` exists on Linux.
  - `zig-out/include/zig_font_renderer.h` exists.
  - `zig-out/bin/zig_font_renderer` exists.
- **Cleanup**: No cleanup required.

### Scenario 4: C ABI Smoke Test

- **Description**: Ensure a C program can include `zig_font_renderer.h`, link `libzig_font_renderer.so`, call `zfr_render_svg_file`, and release the returned string with `zfr_free_string`.
- **Setup**: Zig 0.16.0 installed, system font files available, and `zig build` completed.
- **Test Steps**:
  1. Compile a C smoke program with `zig cc`, using `-I zig-out/include` and `-L zig-out/lib -lzig_font_renderer`.
  2. Run the smoke program with an rpath or library path that can find `zig-out/lib/libzig_font_renderer.so`.
- **Expected Results**:
  - The C program links successfully.
  - `zfr_render_svg_file` returns `ZFR_OK`.
  - The generated SVG length is non-zero.
  - The program calls `zfr_free_string` before exit.
- **Cleanup**: Delete temporary C smoke files from `/tmp`.

## Setup Integration Test Environment

No external services or endpoints are required. The tests execute entirely locally using native filesystem assets and Zig compiler toolchain.

## Run Integration Tests

### 1. Execute Integration Script/Commands

```bash
zig build
zig build lib
zig build test
nm -D --defined-only zig-out/lib/libzig_font_renderer.so | rg ' zfr_'
zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text "fi" --output /tmp/integration-test-gsub.svg
```

### 2. Verify Output

- Ensure console output logs all processed glyph runs successfully.
- Check generated SVG file sizes and ensure standard XML validation checks pass.

### 3. Cleanup

```bash
rm -f /tmp/integration-test-gsub.svg /tmp/integration-test-gpos.svg
```
