const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_types = @import("font_types.zig");

const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;
const readU32 = binary_reader.readU32;
const ParserError = font_types.ParserError;

const Cmap = struct {
    const header_size = 4;
    const num_tables_offset = 2;
    const encoding_record_size = 8;
    const platform_id_offset = 0;
    const encoding_id_offset = 2;
    const subtable_offset_offset = 4;
    const format_size = 2;

    const format4 = 4;
    const format12 = 12;

    const unicode_platform_id = 0;
    const windows_platform_id = 3;
    const windows_bmp_encoding_id = 1;
    const windows_full_unicode_encoding_id = 10;

    const priority_windows_full_unicode = 0;
    const priority_windows_bmp = 1;
    const priority_unicode = 2;
    const priority_fallback = 3;
    const priority_unset = 255;
};

const CmapFormat4 = struct {
    const min_size = 16;
    const length_offset = 2;
    const seg_count_x2_offset = 6;
    const end_codes_offset = 14;
    const reserved_pad_size = 2;
    const code_unit_size = 2;
};

const CmapFormat12 = struct {
    const min_size = 16;
    const length_offset = 4;
    const num_groups_offset = 12;
    const groups_offset = 16;
    const group_size = 12;
    const start_char_offset = 0;
    const end_char_offset = 4;
    const start_glyph_offset = 8;
};

pub const Selection = struct {
    offset: u32,
    format: u16,
};

pub fn select(cmap: []const u8) ParserError!?Selection {
    if (cmap.len < Cmap.header_size) return ParserError.InvalidTable;

    const num_tables = try readU16(cmap, Cmap.num_tables_offset);
    if (Cmap.header_size + @as(usize, num_tables) * Cmap.encoding_record_size > cmap.len) return ParserError.InvalidTable;

    var fallback: ?Selection = null;
    var best: ?Selection = null;
    var best_priority: u8 = Cmap.priority_unset;

    var index: usize = 0;
    while (index < num_tables) : (index += 1) {
        const record = Cmap.header_size + index * Cmap.encoding_record_size;
        const platform_id = try readU16(cmap, record + Cmap.platform_id_offset);
        const encoding_id = try readU16(cmap, record + Cmap.encoding_id_offset);
        const offset = try readU32(cmap, record + Cmap.subtable_offset_offset);
        if (offset + Cmap.format_size > cmap.len) return ParserError.InvalidTable;

        const format = try readU16(cmap, offset);
        const selection: Selection = .{ .offset = offset, .format = format };
        if (fallback == null) fallback = selection;

        const priority = cmapPriority(platform_id, encoding_id);
        if (priority < best_priority) {
            best = selection;
            best_priority = priority;
        }
    }

    return best orelse fallback;
}

pub fn lookup(cmap: []const u8, selection: Selection, codepoint: u32) ParserError!u16 {
    return switch (selection.format) {
        Cmap.format4 => try lookupFormat4(cmap, selection.offset, codepoint),
        Cmap.format12 => try lookupFormat12(cmap, selection.offset, codepoint),
        else => ParserError.UnsupportedCmapFormat,
    };
}

fn cmapPriority(platform_id: u16, encoding_id: u16) u8 {
    if (platform_id == Cmap.windows_platform_id and encoding_id == Cmap.windows_full_unicode_encoding_id) return Cmap.priority_windows_full_unicode;
    if (platform_id == Cmap.windows_platform_id and encoding_id == Cmap.windows_bmp_encoding_id) return Cmap.priority_windows_bmp;
    if (platform_id == Cmap.unicode_platform_id) return Cmap.priority_unicode;
    return Cmap.priority_fallback;
}

fn lookupFormat4(cmap: []const u8, offset: u32, codepoint: u32) ParserError!u16 {
    if (codepoint > 0xFFFF) return 0;
    const start = @as(usize, offset);
    if (start + CmapFormat4.min_size > cmap.len) return ParserError.InvalidTable;

    const length = try readU16(cmap, start + CmapFormat4.length_offset);
    if (start + length > cmap.len) return ParserError.InvalidTable;

    const seg_count_x2 = try readU16(cmap, start + CmapFormat4.seg_count_x2_offset);
    if (seg_count_x2 % 2 != 0) return ParserError.InvalidTable;
    const seg_count = @as(usize, seg_count_x2 / 2);
    const end_codes = start + CmapFormat4.end_codes_offset;
    const reserved_pad = end_codes + seg_count * CmapFormat4.code_unit_size;
    const start_codes = reserved_pad + CmapFormat4.reserved_pad_size;
    const id_deltas = start_codes + seg_count * CmapFormat4.code_unit_size;
    const id_range_offsets = id_deltas + seg_count * CmapFormat4.code_unit_size;
    const glyph_array = id_range_offsets + seg_count * CmapFormat4.code_unit_size;
    if (glyph_array > start + length) return ParserError.InvalidTable;

    const cp = @as(u16, @intCast(codepoint));
    var i: usize = 0;
    while (i < seg_count) : (i += 1) {
        const end_code = try readU16(cmap, end_codes + i * CmapFormat4.code_unit_size);
        if (cp > end_code) continue;

        const start_code = try readU16(cmap, start_codes + i * CmapFormat4.code_unit_size);
        if (cp < start_code) return 0;

        const delta = try readI16(cmap, id_deltas + i * CmapFormat4.code_unit_size);
        const range_offset_location = id_range_offsets + i * CmapFormat4.code_unit_size;
        const range_offset = try readU16(cmap, range_offset_location);
        if (range_offset == 0) {
            return wrapU16(@as(i32, cp) + @as(i32, delta));
        }

        const glyph_index_offset = range_offset_location + range_offset + (@as(usize, cp - start_code) * CmapFormat4.code_unit_size);
        if (glyph_index_offset + CmapFormat4.code_unit_size > start + length) return ParserError.InvalidTable;
        const glyph_id = try readU16(cmap, glyph_index_offset);
        if (glyph_id == 0) return 0;
        return wrapU16(@as(i32, glyph_id) + @as(i32, delta));
    }

    return 0;
}

fn lookupFormat12(cmap: []const u8, offset: u32, codepoint: u32) ParserError!u16 {
    const start = @as(usize, offset);
    if (start + CmapFormat12.min_size > cmap.len) return ParserError.InvalidTable;

    const length = try readU32(cmap, start + CmapFormat12.length_offset);
    if (start + length > cmap.len) return ParserError.InvalidTable;

    const num_groups = try readU32(cmap, start + CmapFormat12.num_groups_offset);
    if (CmapFormat12.groups_offset + @as(usize, num_groups) * CmapFormat12.group_size > length) return ParserError.InvalidTable;

    var low: usize = 0;
    var high: usize = num_groups;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const group = start + CmapFormat12.groups_offset + mid * CmapFormat12.group_size;
        const start_char = try readU32(cmap, group + CmapFormat12.start_char_offset);
        const end_char = try readU32(cmap, group + CmapFormat12.end_char_offset);
        const start_glyph = try readU32(cmap, group + CmapFormat12.start_glyph_offset);

        if (codepoint < start_char) {
            high = mid;
        } else if (codepoint > end_char) {
            low = mid + 1;
        } else {
            const glyph = start_glyph + (codepoint - start_char);
            if (glyph > std.math.maxInt(u16)) return ParserError.InvalidTable;
            return @as(u16, @intCast(glyph));
        }
    }

    return 0;
}

fn wrapU16(value: i32) u16 {
    return @intCast(@mod(value, 1 << 16));
}

test "format 4 lookup maps BMP codepoint with delta" {
    const cmap = [_]u8{
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x03, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x0c,
        0x00, 0x04, 0x00, 0x18,
        0x00, 0x00, 0x00, 0x02,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 'A',
        0x00, 0x00, 0x00, 'A',
        0xff, 0xc0, 0x00, 0x00,
        0x00, 0x00,
    };
    const selection = (try select(&cmap)).?;

    try std.testing.expectEqual(@as(u16, 1), try lookup(&cmap, selection, 'A'));
    try std.testing.expectEqual(@as(u16, 0), try lookup(&cmap, selection, 'B'));
}
