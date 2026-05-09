# Tech Stack Decisions - Unit 2: Shaping Engine

## Language and Runtime

- Zig 0.15.2
- Zig standard library only

## Dependencies

- No external shaping libraries.
- No HarfBuzz dependency.

## Rationale

The project goal is a Pure Zig font renderer. The first Shaping Engine increment uses Unit 1 parser APIs directly and keeps the implementation small enough to validate the API boundary before adding GSUB/GPOS parsing.
