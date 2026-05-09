const std = @import("std");
const font_parser = @import("font_parser.zig");

pub const ShapeError = font_parser.ParserError || std.mem.Allocator.Error || error{
    InvalidUtf8,
};

pub const ShapedGlyph = struct {
    codepoint: u21,
    glyph_id: u16,
    cluster: usize,
    x_offset: i32,
    y_offset: i32,
    x_advance: i32,
    y_advance: i32,
    advance_width: u16,
    lsb: i16,
};

pub const ShapedText = struct {
    glyphs: []ShapedGlyph,
    total_advance: i32,

    pub fn deinit(self: *ShapedText, allocator: std.mem.Allocator) void {
        allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub const ShapeEngine = struct {
    pub fn init() ShapeEngine {
        return .{};
    }

    pub fn shapeText(
        self: ShapeEngine,
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        text: []const u8,
    ) ShapeError!ShapedText {
        _ = self;

        var view = std.unicode.Utf8View.init(text) catch return ShapeError.InvalidUtf8;

        var glyphs = std.ArrayList(ShapedGlyph).empty;
        errdefer glyphs.deinit(allocator);

        var iterator = view.iterator();
        var pen_x: i32 = 0;
        var cluster: usize = 0;
        while (iterator.nextCodepoint()) |codepoint| : (cluster += 1) {
            const info = try face.getGlyphInfo(codepoint);
            const x_advance = @as(i32, info.advance_width);

            try glyphs.append(allocator, .{
                .codepoint = codepoint,
                .glyph_id = info.id,
                .cluster = cluster,
                .x_offset = pen_x,
                .y_offset = 0,
                .x_advance = x_advance,
                .y_advance = 0,
                .advance_width = info.advance_width,
                .lsb = info.lsb,
            });

            pen_x += x_advance;
        }

        return .{
            .glyphs = try glyphs.toOwnedSlice(allocator),
            .total_advance = pen_x,
        };
    }
};

test "shape engine rejects invalid utf8" {
    const engine = ShapeEngine.init();
    const face: font_parser.Face = undefined;
    try std.testing.expectError(
        ShapeError.InvalidUtf8,
        engine.shapeText(std.testing.allocator, face, "\xff"),
    );
}
