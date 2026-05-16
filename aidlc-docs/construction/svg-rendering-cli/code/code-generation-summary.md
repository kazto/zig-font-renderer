# Code Generation Summary - Unit 3: SVG Rendering & CLI

## Generated At

2026-05-09T02:15:51Z

## Scope

Implemented visible SVG rendering increments for TrueType outlines, including high-level rendering and basic SVG styling controls.

## Application Code

- Created `src/binary_reader.zig`
  - Provides shared big-endian `readU16`, `readI16`, `readU32`, and `readI32` helpers.
  - Provides `tagToU32` for four-byte SFNT tags.
  - Returns `InvalidTable` on out-of-range reads for parser-compatible error propagation.

- Created `src/svg_renderer.zig`
  - Defines `SvgRenderer` and `SvgError`.
  - Defines `RenderOptions` for SVG sizing and shaping direction.
  - Resolves glyph byte ranges with `loca`.
  - Reads glyph header bounds and computes shaped text bounds.
  - Decodes simple TrueType `glyf` contours.
  - Expands composite TrueType glyphs when components use XY offsets.
  - Applies composite uniform scale, separate XY scale, and 2x2 transforms to emitted path coordinates.
  - Aligns point-matched composite TrueType components by resolving component point indexes against accumulated parent component points.
  - Applies `VORG`-derived vertical origins when rendering top-to-bottom shaped glyphs.
  - Parses CFF INDEX data and Top DICT `CharStrings` offsets.
  - Retrieves CFF Type 2 charstrings by glyph ID.
  - Resolves CID-keyed CFF `FDArray`/`FDSelect` data for glyph-specific local subroutines.
  - Emits SVG path commands for basic Type 2 moveto, lineto, and rrcurveto operators.
  - Expands Type 2 `callsubr` and `callgsubr` with standard CFF subroutine bias.
  - Skips Type 2 `hintmask`/`cntrmask` data using the active stem count.
  - Counts escaped Type 2 `hstem3` and `vstem3` hint groups toward `hintmask` length.
  - Applies escaped Type 2 `setcurrentpoint` to update the current path origin without emitting geometry.
  - Emits SVG path closure for Type 2 `closepath` without forcing a duplicate close at `endchar`.
  - Preserves compatibility operands through escaped Type 2 `callothersubr` and `pop`.
  - Emits SVG cubic paths for common compact Type 2 curve operators.
  - Emits SVG cubic paths for escaped Type 2 flex operators.
  - Evaluates escaped Type 2 arithmetic, boolean, storage, conditional, and stack manipulation operators.
  - Returns `UnsupportedCffOperator` for remaining Type 2 operators that are not yet implemented.
  - Emits SVG path commands with bounds-based width, height, viewBox, and scaled group transform.
  - Supports glyph fill color, optional background color, and custom margin.
  - Rejects SVG color strings that can break attribute syntax.

- Created `src/font_rendering_service.zig`
  - Defines `renderToSvg`.
  - Defines `RenderToSvgOptions`.
  - Loads font bytes, parses `Face`, and returns an owned SVG buffer.

- Modified `src/root.zig`
  - Re-exports `SvgRenderer` and `SvgError`.
  - Re-exports `renderToSvg`, `RenderToSvgOptions`, and `RenderToSvgError`.

- Modified `src/main.zig`
  - Adds `--output <svg-file>`.
  - Adds `--font-size <px>` and `--quiet`.
  - Adds `--margin <px>`, `--fill <color>`, `--background <color>`, and `--direction <auto|ltr|rtl|ttb>`.
  - Writes SVG when `--font`, `--text`, and `--output` are supplied.
  - Suppresses metadata output by default when writing SVG files.
  - Displays direction-aware shaped glyph info, including vertical offsets and advances, when printing text output.
  - Routes SVG output through the high-level `renderToSvg` API.

## Verification

- Command: `zig fmt src/svg_renderer.zig src/root.zig src/main.zig`
- Result: Passed
- Command: `zig build test`
- Result: Passed
- Command: `zig build`
- Result: Passed
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text AV --output /tmp/zig-font-renderer-av.svg`
- Result: Passed
- Command: `rg "<path|<svg|viewBox" /tmp/zig-font-renderer-av.svg`
- Result: Passed; generated SVG contains `<svg>` and two `<path>` elements.
- Command: `wc -c /tmp/zig-font-renderer-av.svg`
- Result: `350 /tmp/zig-font-renderer-av.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text é --output /tmp/zig-font-renderer-eacute.svg`
- Result: Passed
- Command: `rg "<path|<svg|viewBox" /tmp/zig-font-renderer-eacute.svg`
- Result: Passed; generated SVG contains base glyph and accent paths.
- Command: `wc -c /tmp/zig-font-renderer-eacute.svg`
- Result: `558 /tmp/zig-font-renderer-eacute.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text AV --output /tmp/zig-font-renderer-av-96.svg --font-size 96`
- Result: Passed; generated SVG quietly.
- Command: `sed -n '1,6p' /tmp/zig-font-renderer-av-96.svg`
- Result: Passed; generated SVG includes `width="141.20"`, `height="136.00"`, and a scaled transform.
- Command: `wc -c /tmp/zig-font-renderer-av-96.svg`
- Result: `418 /tmp/zig-font-renderer-av-96.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text gé --output /tmp/zig-font-renderer-bounds.svg --font-size 96`
- Result: Passed; generated SVG quietly.
- Command: `sed -n '1,5p' /tmp/zig-font-renderer-bounds.svg`
- Result: Passed; generated SVG includes bounds-derived `width="130.70"`, `height="112.75"`, and transform `translate(2.70 84.78)`.
- Command: `wc -c /tmp/zig-font-renderer-bounds.svg`
- Result: `1187 /tmp/zig-font-renderer-bounds.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text SVG --output /tmp/zig-font-renderer-service.svg --font-size 96`
- Result: Passed; generated SVG through high-level API path.
- Command: `wc -c /tmp/zig-font-renderer-service.svg`
- Result: `1242 /tmp/zig-font-renderer-service.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text SVG --output /tmp/zig-font-renderer-style.svg --font-size 96 --margin 16 --fill '#1d4ed8' --background '#f8fafc'`
- Result: Passed; generated styled SVG through CLI.
- Command: `sed -n '1,8p' /tmp/zig-font-renderer-style.svg`
- Result: Passed; generated SVG includes `<rect width="100%" height="100%" fill="#f8fafc"/>` and `<g fill="#1d4ed8" ...>`.
- Command: `wc -c /tmp/zig-font-renderer-style.svg`
- Result: `1298 /tmp/zig-font-renderer-style.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text é --output /tmp/zig-font-renderer-transform-eacute.svg --font-size 96`
- Result: Passed; composite glyph output path still renders after transform pipeline change.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text SVG --output /tmp/zig-font-renderer-transform-style.svg --font-size 96 --margin 16 --fill '#1d4ed8' --background '#f8fafc'`
- Result: Passed; styled SVG output still renders after transform pipeline change.
- Command: `wc -c /tmp/zig-font-renderer-transform-eacute.svg /tmp/zig-font-renderer-transform-style.svg`
- Result: `867 /tmp/zig-font-renderer-transform-eacute.svg`, `1892 /tmp/zig-font-renderer-transform-style.svg`
- Command: `zig build run -- --font /usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf --text A --output /tmp/zig-font-renderer-cff.svg`
- Result: Expected failure; CLI reports `error: failed to render SVG: UnsupportedCffOutlines`.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text SVG --output /tmp/zig-font-renderer-cff-regression.svg --font-size 96 --fill '#111827'`
- Result: Passed; TrueType SVG rendering still works after CFF unsupported detection.
- Command: `wc -c /tmp/zig-font-renderer-cff-regression.svg`
- Result: `1838 /tmp/zig-font-renderer-cff-regression.svg`
- Command: `zig build run -- --font /usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf --text A --output /tmp/zig-font-renderer-cff-a.svg --font-size 96`
- Result: Expected current limitation; CFF parsing reaches Type 2 charstring execution and reports `UnsupportedCffOperator` for subroutine-backed outlines.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text AV --output /tmp/zig-font-renderer-cff-foundation-regression.svg --font-size 96`
- Result: Passed; TrueType SVG rendering still works after CFF foundation changes.
- Command: `wc -c /tmp/zig-font-renderer-cff-foundation-regression.svg`
- Result: `523 /tmp/zig-font-renderer-cff-foundation-regression.svg`
- Command: `zig build run -- --font /usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf --text A --output /tmp/zig-font-renderer-cff-subr-a.svg --font-size 96`
- Result: Passed; generated visible SVG from OTF/CFF via Type 2 subroutine expansion.
- Command: `sed -n '1,8p' /tmp/zig-font-renderer-cff-subr-a.svg`
- Result: Passed; generated SVG contains a CFF-derived `<path>`.
- Command: `wc -c /tmp/zig-font-renderer-cff-subr-a.svg /tmp/zig-font-renderer-cff-subr-regression.svg`
- Result: `378 /tmp/zig-font-renderer-cff-subr-a.svg`, `523 /tmp/zig-font-renderer-cff-subr-regression.svg`
- Command: `./zig-out/bin/zig_font_renderer --font /usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf --text B --output /tmp/zig-font-renderer-cff-op-B.svg --font-size 96`
- Result: Passed.
- Command: `./zig-out/bin/zig_font_renderer --font /usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf --text S --output /tmp/zig-font-renderer-cff-op-S.svg --font-size 96`
- Result: Passed.
- Command: `./zig-out/bin/zig_font_renderer --font /usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf --text g --output /tmp/zig-font-renderer-cff-op-g.svg --font-size 96`
- Result: Passed.
- Command: `wc -c /tmp/zig-font-renderer-cff-op-A.svg /tmp/zig-font-renderer-cff-op-B.svg /tmp/zig-font-renderer-cff-op-S.svg /tmp/zig-font-renderer-cff-op-g.svg /tmp/zig-font-renderer-cff-op-O.svg /tmp/zig-font-renderer-type2-regression.svg`
- Result: Passed; all generated SVG files are non-empty.
- Command: `zig build run -- --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --text Å --output /tmp/zig-font-renderer-point-composite.svg --font-size 96`
- Result: Passed; TrueType composite SVG output still renders after point-matched component support.
- Command: `wc -c /tmp/zig-font-renderer-point-composite.svg`
- Result: `899 /tmp/zig-font-renderer-point-composite.svg`
- Command: `zig build run -- --font /usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf --text A --output /tmp/zig-font-renderer-cff-stem3.svg --font-size 96`
- Result: Passed; CFF SVG output still renders after stem3 hint counting support.
- Command: `wc -c /tmp/zig-font-renderer-cff-stem3.svg`
- Result: `1196 /tmp/zig-font-renderer-cff-stem3.svg`
- Command: `zig build run -- --font /usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf --text A --output /tmp/zig-font-renderer-cff-setcurrentpoint.svg --font-size 96`
- Result: Passed; CFF SVG output still renders after setcurrentpoint support.
- Command: `wc -c /tmp/zig-font-renderer-cff-setcurrentpoint.svg`
- Result: `1196 /tmp/zig-font-renderer-cff-setcurrentpoint.svg`
- Command: `zig build run -- --font /usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf --text A --output /tmp/zig-font-renderer-cff-closepath-othersubr.svg --font-size 96`
- Result: Passed; CFF SVG output still renders after closepath and othersubr compatibility support.
- Command: `wc -c /tmp/zig-font-renderer-cff-closepath-othersubr.svg`
- Result: `1196 /tmp/zig-font-renderer-cff-closepath-othersubr.svg`
- Command: `zig build run -- --font /usr/share/fonts/truetype/fonts-japanese-gothic.ttf --text かな --output /tmp/zig-font-renderer-vertical-origin.svg --font-size 96 --direction ttb`
- Result: Passed; generated SVG through the new vertical shaping direction path.
- Command: `wc -c /tmp/zig-font-renderer-vertical-origin.svg`
- Result: `2189 /tmp/zig-font-renderer-vertical-origin.svg`
- Command: `git diff --check`
- Result: Passed

## Known Limitations

- Point-matched composite glyphs are implemented for tested TrueType component point alignment cases.
- Some uncommon Type 2 operators beyond compact curves, flex operators, stem3 hint groups, `setcurrentpoint`, `closepath`, and `callothersubr`/`pop` are not implemented.
- CFF2 outlines are not implemented.
- Complex shaping remains incomplete.
