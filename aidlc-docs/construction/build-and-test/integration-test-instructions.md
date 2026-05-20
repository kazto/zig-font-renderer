# Integration Test Instructions

## Purpose

Validate the integration boundaries across all components (Parser, Shaper, SVG Renderer, and CLI executable), including advanced GPOS Complex Typography features.

## Test Scenarios

### Scenario 1: Full Layout and Rendering Pipeline (Parser -> Shaper -> Renderer -> CLI)

- **Description**: Verify that the CLI successfully parses an OpenType font, applies GSUB/GPOS shaping features, translates coordinates into vector SVG paths, and exports the resulting markup.
- **Setup**: Zig 0.15.2 installed, and system font files (e.g., DejaVuSans.ttf) available.
- **Test Steps**:
  1. Build the release binary: `zig build`
  2. Run layout and render: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text "AV" --output /tmp/integration-test-gpos.svg --font-size 96`
- **Expected Results**:
  - The CLI command completes with exit code 0.
  - The SVG file `/tmp/integration-test-gpos.svg` is generated and contains valid XML markup with `<path>` elements representing styled and spaced glyphs.
- **Cleanup**: Delete `/tmp/integration-test-gpos.svg` after verification.

### Scenario 2: Public API Exports via Root Module

- **Description**: Ensure `src/root.zig` exposes full APIs (Face, ShapeEngine, SVG Renderer structures) properly to external packages.
- **Setup**: Zig 0.15.2 installed.
- **Test Steps**: Run `zig build test`.
- **Expected Results**: All unit and module integration tests pass successfully without compiler package mapping issues.
- **Cleanup**: No cleanup required.

## Setup Integration Test Environment

No external services or endpoints are required. The tests execute entirely locally using native filesystem assets and Zig compiler toolchain.

## Run Integration Tests

### 1. Execute Integration Script/Commands

```bash
zig build
zig build test
zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text "fi" --output /tmp/integration-test-gsub.svg
```

### 2. Verify Output

- Ensure console output logs all processed glyph runs successfully.
- Check generated SVG file sizes and ensure standard XML validation checks pass.

### 3. Cleanup

```bash
rm -f /tmp/integration-test-gsub.svg /tmp/integration-test-gpos.svg
```
