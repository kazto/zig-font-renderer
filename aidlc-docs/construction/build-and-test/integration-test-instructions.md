# Integration Test Instructions

## Purpose

Validate the current integration boundary between the library module and CLI executable.

## Test Scenarios

### Scenario 1: Font Parser Module -> CLI Build Integration

- **Description**: Ensure the executable links against the `zig_font_renderer` module without import or symbol errors.
- **Setup**: Zig 0.15.2 installed.
- **Test Steps**: Run `zig build`.
- **Expected Results**: The executable builds successfully at `zig-out/bin/zig_font_renderer`.
- **Cleanup**: No cleanup required.

### Scenario 2: Root Module -> Font Parser API Export Integration

- **Description**: Ensure `src/root.zig` exposes Unit 1 parser APIs through the package module.
- **Setup**: Zig 0.15.2 installed.
- **Test Steps**: Run `zig build test`.
- **Expected Results**: Module and executable test steps pass.
- **Cleanup**: No cleanup required.

## Setup Integration Test Environment

No services or external endpoints are required.

## Run Integration Tests

### 1. Execute Integration Test Suite

```bash
zig build
zig build test
```

### 2. Verify Service Interactions

- **Test Scenarios**: Library export and executable link integration.
- **Expected Results**: Both commands exit with status 0.
- **Logs Location**: Console output only.

### 3. Cleanup

No cleanup is required.
