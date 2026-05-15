const std = @import("std");
const font_parser = @import("font_parser.zig");

pub const LayoutError = font_parser.ParserError || std.mem.Allocator.Error;

pub const ShapeError = font_parser.ParserError || std.mem.Allocator.Error || error{
    InvalidUtf8,
};

pub const ShapeOptions = struct {
    script_tag: ?[4]u8 = null,
    language_tag: ?[4]u8 = null,
    feature_tags: ?[]const [4]u8 = null,
    direction: ShapeDirection = .auto,
};

pub const ShapeDirection = enum {
    auto,
    ltr,
    rtl,
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
    kern_adjustment: i16,
};

pub const ShapedText = struct {
    glyphs: []ShapedGlyph,
    total_advance: i32,

    pub fn deinit(self: *ShapedText, allocator: std.mem.Allocator) void {
        allocator.free(self.glyphs);
        self.* = undefined;
    }
};
