# NFR Design Patterns - Unit 2: Shaping Engine

## Stateless Engine

`ShapeEngine` currently stores no mutable state. This keeps shaping deterministic and allows callers to reuse the engine without synchronization.

## Owned Output Slice

`shapeText` returns `ShapedText`, which owns the shaped glyph slice and exposes `deinit`. This keeps allocation ownership explicit.

## Error Propagation

Parser errors are propagated directly from Unit 1. Invalid UTF-8 is reported at the shaping boundary.
