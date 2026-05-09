//! Public library surface for zig-font-renderer.

pub const font_parser = @import("font_parser.zig");
pub const shaper = @import("shaper.zig");
pub const svg_renderer = @import("svg_renderer.zig");

pub const Face = font_parser.Face;
pub const GlyphInfo = font_parser.GlyphInfo;
pub const HMetric = font_parser.HMetric;
pub const ParserError = font_parser.ParserError;
pub const TableMetadata = font_parser.TableMetadata;

pub const ShapeEngine = shaper.ShapeEngine;
pub const ShapeError = shaper.ShapeError;
pub const ShapedGlyph = shaper.ShapedGlyph;
pub const ShapedText = shaper.ShapedText;

pub const SvgError = svg_renderer.SvgError;
pub const RenderOptions = svg_renderer.RenderOptions;
pub const SvgRenderer = svg_renderer.SvgRenderer;

test {
    _ = font_parser;
    _ = shaper;
    _ = svg_renderer;
}
