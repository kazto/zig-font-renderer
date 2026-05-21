# Build Instructions

## Prerequisites

- **Build Tool**: Zig 0.16.0
- **Dependencies**: Zig standard library only; no external package dependencies
- **Environment Variables**: None required
- **System Requirements**: Native platform supported by Zig 0.16.0 with write access to Zig cache and `zig-out/`

## Build Steps

### 1. Install Dependencies

No dependency installation is required.

### 2. Configure Environment

No environment configuration is required.

### 3. Build All Units

```bash
zig build
```

### 4. Verify Build Success

- **Expected Output**: Command exits with status 0 and no compilation errors.
- **Build Artifacts**: Installed executable under `zig-out/bin/zig_font_renderer`.
- **Common Warnings**: No warnings are expected for the current Unit 1 scope.

### 5. Optional Performance Smoke

```bash
zig build perf
```

- **Expected Output**: Prints per-iteration timings for representative fonts found on the local system.
- **Missing Fonts**: Missing representative fonts are reported as skipped and do not fail the command.

## Troubleshooting

### Build Fails with Dependency Errors

- **Cause**: Unexpected Zig package dependency or cache resolution issue.
- **Solution**: Confirm `build.zig.zon` has no external dependencies and rerun `zig build`.

### Build Fails with Compilation Errors

- **Cause**: Zig version mismatch or source-level compile error.
- **Solution**: Confirm `zig version` reports `0.16.0`, then fix the reported file and line before rerunning `zig build`.
