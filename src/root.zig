//! Public library surface for zig-font-renderer.

pub const font_parser = @import("font_parser.zig");
pub const font_rendering_service = @import("font_rendering_service.zig");
pub const shaper = @import("shaper.zig");
pub const svg_renderer = @import("svg_renderer.zig");

pub const Face = font_parser.Face;
pub const GlyphInfo = font_parser.GlyphInfo;
pub const HMetric = font_parser.HMetric;
pub const ParserError = font_parser.ParserError;
pub const TableMetadata = font_parser.TableMetadata;
pub const VariationCoord = font_parser.VariationCoord;

pub const ShapeEngine = shaper.ShapeEngine;
pub const ShapeError = shaper.ShapeError;
pub const ShapeDirection = shaper.ShapeDirection;
pub const ShapeOptions = shaper.ShapeOptions;
pub const ShapedGlyph = shaper.ShapedGlyph;
pub const ShapedText = shaper.ShapedText;

pub const SvgError = svg_renderer.SvgError;
pub const RenderOptions = svg_renderer.RenderOptions;
pub const SvgRenderer = svg_renderer.SvgRenderer;

pub const RenderToSvgError = font_rendering_service.RenderToSvgError;
pub const RenderToSvgOptions = font_rendering_service.RenderToSvgOptions;
pub const renderToSvg = font_rendering_service.renderToSvg;

test {
    _ = font_parser;
    _ = font_rendering_service;
    _ = shaper;
    _ = svg_renderer;
}
