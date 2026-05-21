const std = @import("std");
const font_parser = @import("font_parser.zig");
const shaper = @import("shaper.zig");
const svg_color = @import("svg_color.zig");
const svg_glyph = @import("svg_glyph.zig");

pub const SvgError = shaper.ShapeError || svg_color.SvgColorError || svg_glyph.SvgGlyphError;

const default_font_size_px = 64.0;
const default_margin_px = 8.0;

pub const RenderOptions = struct {
    font_size_px: f64 = default_font_size_px,
    margin_px: f64 = default_margin_px,
    fill: []const u8 = "black",
    background: ?[]const u8 = null,
    shape: shaper.ShapeOptions = .{},
    variation_coords: []const font_parser.VariationCoord = &.{},
    variation_instance_index: ?u16 = null,
    cff2_variation_coords: []const f64 = &.{},
};

pub const SvgRenderer = struct {
    pub fn init() SvgRenderer {
        return .{};
    }

    pub fn renderText(
        self: SvgRenderer,
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        text: []const u8,
    ) SvgError![]u8 {
        return self.renderTextWithOptions(allocator, face, text, .{});
    }

    pub fn renderTextWithOptions(
        self: SvgRenderer,
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        text: []const u8,
        options: RenderOptions,
    ) SvgError![]u8 {
        _ = self;

        const engine = shaper.ShapeEngine.init();
        var shaped = try engine.shapeTextWithOptions(allocator, face, text, options.shape);
        defer shaped.deinit(allocator);

        const bounds = try svg_glyph.textBounds(face, shaped, options.shape.direction);
        const scale = options.font_size_px / @as(f64, @floatFromInt(face.units_per_em));
        const width_px = @as(f64, @floatFromInt(bounds.width())) * scale + options.margin_px * 2.0;
        const height_px = @as(f64, @floatFromInt(bounds.height())) * scale + options.margin_px * 2.0;
        const translate_x = options.margin_px - @as(f64, @floatFromInt(bounds.min_x)) * scale;
        const translate_y = options.margin_px + @as(f64, @floatFromInt(bounds.max_y)) * scale;
        try svg_color.validate(options.fill);
        if (options.background) |background| try svg_color.validate(background);
        const normalized_variation_coords = if (options.variation_coords.len > 0)
            try face.normalizedVariationCoords(allocator, options.variation_coords)
        else if (options.variation_instance_index) |instance_index|
            try face.normalizedVariationInstanceCoords(allocator, instance_index)
        else
            null;
        defer if (normalized_variation_coords) |coords| allocator.free(coords);
        const cff2_variation_coords = normalized_variation_coords orelse options.cff2_variation_coords;

        var output = std.Io.Writer.Allocating.init(allocator);
        errdefer output.deinit();
        const writer = &output.writer;

        try writer.print(
            \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.2}" height="{d:.2}" viewBox="0 0 {d:.2} {d:.2}">
            \\
        , .{
            width_px,
            height_px,
            width_px,
            height_px,
        });

        if (options.background) |background| {
            try writer.print("  <rect width=\"100%\" height=\"100%\" fill=\"{s}\"/>\n", .{background});
        }

        try writer.print(
            \\  <g fill="{s}" transform="translate({d:.2} {d:.2}) scale({d:.6} {d:.6})">
            \\
        , .{
            options.fill,
            translate_x,
            translate_y,
            scale,
            -scale,
        });

        for (shaped.glyphs) |glyph| {
            const transform = try svg_glyph.glyphTransform(face, glyph, options.shape.direction);
            try svg_glyph.appendGlyphPath(allocator, writer, face, glyph.glyph_id, transform, 0, cff2_variation_coords);
        }

        try writer.print(
            \\  </g>
            \\</svg>
            \\
        , .{});

        return try output.toOwnedSlice();
    }
};
