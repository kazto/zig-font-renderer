const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");
const ot_layout = @import("ot_layout.zig");
const types = @import("shaper_types.zig");
const test_utils = @import("shaper_test_utils.zig");

const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;
const ShapedGlyph = types.ShapedGlyph;

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

pub fn hasGposAdjustment(glyphs: []const ShapedGlyph) bool {
    for (glyphs) |glyph| {
        if (glyph.x_offset != 0 or glyph.y_offset != 0 or glyph.y_advance != 0) return true;
        if (glyph.x_advance != @as(i32, glyph.advance_width)) return true;
    }
    return false;
}

pub fn applyKerning(face: font_parser.Face, glyphs: []ShapedGlyph) font_parser.ParserError!i32 {
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

pub fn getLegacyKernAdjustment(face: font_parser.Face, left: u16, right: u16) font_parser.ParserError!i16 {
    const kern = face.getTable(ot_layout.TableTags.kern) orelse return 0;
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

pub fn lookupKernFormat0(subtable: []const u8, left: u16, right: u16) font_parser.ParserError!i16 {
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

test "legacy kern format 0 lookup returns pair adjustment" {
    var subtable = [_]u8{0} ** 26;
    test_utils.writeU16(&subtable, 2, 26);
    test_utils.writeU16(&subtable, 4, 0x0001);
    test_utils.writeU16(&subtable, 6, 2);
    test_utils.writeU16(&subtable, 8, 12);
    test_utils.writeU16(&subtable, 10, 1);
    test_utils.writeU16(&subtable, 12, 0);

    test_utils.writeU16(&subtable, 14, 10);
    test_utils.writeU16(&subtable, 16, 20);
    test_utils.writeI16(&subtable, 18, -40);
    test_utils.writeU16(&subtable, 20, 10);
    test_utils.writeU16(&subtable, 22, 30);
    test_utils.writeI16(&subtable, 24, -80);

    try std.testing.expectEqual(@as(i16, -40), try lookupKernFormat0(&subtable, 10, 20));
    try std.testing.expectEqual(@as(i16, -80), try lookupKernFormat0(&subtable, 10, 30));
    try std.testing.expectEqual(@as(i16, 0), try lookupKernFormat0(&subtable, 20, 10));
}
