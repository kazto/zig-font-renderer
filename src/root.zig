//! Public library surface for zig-font-renderer.

pub const font_parser = @import("font_parser.zig");
pub const shaper = @import("shaper.zig");

pub const Face = font_parser.Face;
pub const GlyphInfo = font_parser.GlyphInfo;
pub const HMetric = font_parser.HMetric;
pub const ParserError = font_parser.ParserError;
pub const TableMetadata = font_parser.TableMetadata;

pub const ShapeEngine = shaper.ShapeEngine;
pub const ShapeError = shaper.ShapeError;
pub const ShapedGlyph = shaper.ShapedGlyph;
pub const ShapedText = shaper.ShapedText;

test {
    _ = font_parser;
    _ = shaper;
}
