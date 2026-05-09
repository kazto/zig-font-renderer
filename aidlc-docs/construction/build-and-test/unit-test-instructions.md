# Unit Test Execution

## Run Unit Tests

### 1. Execute All Unit Tests

```bash
zig build test
```

### 2. Review Test Results

- **Expected**: Command exits with status 0 and no failing test blocks.
- **Test Coverage**: Zig's built-in test runner does not emit coverage in this project.
- **Test Report Location**: Console output only; no separate report file is generated.

### 3. Fix Failing Tests

If tests fail:

1. Review the failing test name and source location in the Zig output.
2. Fix the parser implementation or synthetic font fixture that caused the failure.
3. Rerun `zig build test` until all tests pass.
