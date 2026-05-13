# NFR Design - Unit 2 Extension: Advanced GSUB/GPOS

This document defines the NFR design for advanced OpenType Layout features, prioritizing performance stability and execution safety.

## Performance Design

- **Context Matching Efficiency**: Use direct coverage comparisons for the implemented Format 3 path. Glyph ID and class-based contextual formats remain deferred.
- **Anchor Resolution**: Resolve Mark and Base anchors in a single pass where possible.
- **Lookbehind Limits**: Bound contextual backtrack checks by the coverage sequence length to avoid out-of-bounds reads.

## Safety & Security Design

- **Recursion Depth Limit**: Enforce a hard limit on GSUB lookup recursion (e.g., 16 levels) to prevent stack overflow and infinite substitution loops.
- **Offset Validation**: All subtable offsets (Anchor tables, MarkArrays, BaseArrays, etc.) must be checked against the parent table's slice size before dereferencing.
- **Mark Classification Validation**: Verify that MarkClass indices in the MarkArray are within the bounds of the BaseArray's class count.
- **Sequence Boundary Checks**: Contextual matches must be bounded by the actual glyph stream size to prevent out-of-bounds reads.

## Memory Design

- **Zero-Allocation Execution**: Continue the strategy of applying lookups directly from font table slices without building intermediate lookup maps.
- **Stack-Based Context**: Use small fixed-size arrays or the caller's stack for temporary context matching state to avoid heap allocations.
