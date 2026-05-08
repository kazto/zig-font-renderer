//! Public library surface for zig-font-renderer.

pub const font_parser = @import("font_parser.zig");

pub const Face = font_parser.Face;
pub const GlyphInfo = font_parser.GlyphInfo;
pub const HMetric = font_parser.HMetric;
pub const ParserError = font_parser.ParserError;
pub const TableMetadata = font_parser.TableMetadata;

test {
    _ = font_parser;
}
