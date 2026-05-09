const std = @import("std");
const font_parser = @import("font_parser.zig");

const TableTags = struct {
    const kern = "kern".*;
};

const Kern = struct {
    const version_offset = 0;
    const n_tables_offset = 2;
    const header_size = 4;
    const subtable_header_size = 6;
    const subtable_length_offset = 2;
    const subtable_coverage_offset = 4;
    const version0 = 0;
};

const KernCoverage = struct {
    const horizontal_mask = 0x0001;
    const format_shift = 8;
    const format0 = 0;
};

const KernFormat0 = struct {
    const min_size = 14;
    const n_pairs_offset = 6;
    const pair_records_offset = 14;
    const pair_record_size = 6;
    const left_glyph_offset = 0;
    const right_glyph_offset = 2;
    const value_offset = 4;
};

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
                .kern_adjustment = 0,
            });

            pen_x += x_advance;
        }

        pen_x = try applyKerning(face, glyphs.items);

        return .{
            .glyphs = try glyphs.toOwnedSlice(allocator),
            .total_advance = pen_x,
        };
    }
};

fn applyKerning(face: font_parser.Face, glyphs: []ShapedGlyph) font_parser.ParserError!i32 {
    if (glyphs.len == 0) return 0;

    var index: usize = 0;
    while (index + 1 < glyphs.len) : (index += 1) {
        const adjustment = try getLegacyKernAdjustment(face, glyphs[index].glyph_id, glyphs[index + 1].glyph_id);
        glyphs[index].kern_adjustment = adjustment;
        glyphs[index].x_advance = @as(i32, glyphs[index].advance_width) + @as(i32, adjustment);
    }

    var pen_x: i32 = 0;
    for (glyphs) |*glyph| {
        glyph.x_offset = pen_x;
        pen_x += glyph.x_advance;
    }
    return pen_x;
}

fn getLegacyKernAdjustment(face: font_parser.Face, left: u16, right: u16) font_parser.ParserError!i16 {
    const kern = face.getTable(TableTags.kern) orelse return 0;
    if (kern.len < Kern.header_size) return font_parser.ParserError.InvalidTable;

    const version = try readU16(kern, Kern.version_offset);
    if (version != Kern.version0) return 0;

    const n_tables = try readU16(kern, Kern.n_tables_offset);
    var offset: usize = Kern.header_size;
    var total: i32 = 0;

    var table_index: usize = 0;
    while (table_index < n_tables) : (table_index += 1) {
        if (offset + Kern.subtable_header_size > kern.len) return font_parser.ParserError.InvalidTable;

        const length = try readU16(kern, offset + Kern.subtable_length_offset);
        const coverage = try readU16(kern, offset + Kern.subtable_coverage_offset);
        if (length < Kern.subtable_header_size or offset + length > kern.len) return font_parser.ParserError.InvalidTable;

        const format = @as(u8, @intCast(coverage >> KernCoverage.format_shift));
        const horizontal = (coverage & KernCoverage.horizontal_mask) != 0;
        if (format == KernCoverage.format0 and horizontal) {
            total += try lookupKernFormat0(kern[offset .. offset + length], left, right);
        }

        offset += length;
    }

    if (total < std.math.minInt(i16) or total > std.math.maxInt(i16)) {
        return font_parser.ParserError.InvalidTable;
    }
    return @as(i16, @intCast(total));
}

fn lookupKernFormat0(subtable: []const u8, left: u16, right: u16) font_parser.ParserError!i16 {
    if (subtable.len < KernFormat0.min_size) return font_parser.ParserError.InvalidTable;

    const n_pairs = try readU16(subtable, KernFormat0.n_pairs_offset);
    if (KernFormat0.pair_records_offset + @as(usize, n_pairs) * KernFormat0.pair_record_size > subtable.len) return font_parser.ParserError.InvalidTable;

    const target = (@as(u32, left) << 16) | @as(u32, right);
    var low: usize = 0;
    var high: usize = n_pairs;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const pair_offset = KernFormat0.pair_records_offset + mid * KernFormat0.pair_record_size;
        const pair = (@as(u32, try readU16(subtable, pair_offset + KernFormat0.left_glyph_offset)) << 16) |
            @as(u32, try readU16(subtable, pair_offset + KernFormat0.right_glyph_offset));

        if (target < pair) {
            high = mid;
        } else if (target > pair) {
            low = mid + 1;
        } else {
            return try readI16(subtable, pair_offset + KernFormat0.value_offset);
        }
    }

    return 0;
}

fn readU16(data: []const u8, offset: usize) font_parser.ParserError!u16 {
    if (offset + 2 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readI16(data: []const u8, offset: usize) font_parser.ParserError!i16 {
    if (offset + 2 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

test "shape engine rejects invalid utf8" {
    const engine = ShapeEngine.init();
    const face: font_parser.Face = undefined;
    try std.testing.expectError(
        ShapeError.InvalidUtf8,
        engine.shapeText(std.testing.allocator, face, "\xff"),
    );
}

test "legacy kern format 0 lookup returns pair adjustment" {
    var subtable = [_]u8{0} ** 26;
    writeU16(&subtable, 2, 26);
    writeU16(&subtable, 4, 0x0001);
    writeU16(&subtable, 6, 2);
    writeU16(&subtable, 8, 12);
    writeU16(&subtable, 10, 1);
    writeU16(&subtable, 12, 0);

    writeU16(&subtable, 14, 10);
    writeU16(&subtable, 16, 20);
    writeI16(&subtable, 18, -40);
    writeU16(&subtable, 20, 10);
    writeU16(&subtable, 22, 30);
    writeI16(&subtable, 24, -80);

    try std.testing.expectEqual(@as(i16, -40), try lookupKernFormat0(&subtable, 10, 20));
    try std.testing.expectEqual(@as(i16, -80), try lookupKernFormat0(&subtable, 10, 30));
    try std.testing.expectEqual(@as(i16, 0), try lookupKernFormat0(&subtable, 20, 10));
}

fn writeU16(data: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, data[offset..][0..2], value, .big);
}

fn writeI16(data: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, data[offset..][0..2], value, .big);
}
