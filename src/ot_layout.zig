const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");
const types = @import("shaper_types.zig");
const test_utils = @import("shaper_test_utils.zig");

const readU16 = binary_reader.readU16;
const LayoutError = types.LayoutError;
const ShapeOptions = types.ShapeOptions;

pub const TableTags = struct {
    pub const kern = "kern".*;
    pub const gsub = "GSUB".*;
    pub const gpos = "GPOS".*;
};

pub const OtLayout = struct {
    pub const default_script_tag = "DFLT".*;
    pub const latin_script_tag = "latn".*;
    pub const arabic_script_tag = "arab".*;
    pub const cyrillic_script_tag = "cyrl".*;
    pub const devanagari_script_tag = "deva".*;
    pub const greek_script_tag = "grek".*;
    pub const han_script_tag = "hani".*;
    pub const hangul_script_tag = "hang".*;
    pub const hebrew_script_tag = "hebr".*;
    pub const kana_script_tag = "kana".*;
    pub const thai_script_tag = "thai".*;
    pub const required_feature_none = 0xffff;

    pub const header_min_size = 10;
    pub const script_list_offset = 4;
    pub const feature_list_offset = 6;
    pub const lookup_list_offset = 8;

    pub const script_default_lang_sys_offset = 0;
    pub const script_lang_sys_count_offset = 2;
    pub const script_lang_sys_records_offset = 4;
    pub const script_lang_sys_record_size = 6;
    pub const script_lang_sys_tag_offset = 0;
    pub const script_lang_sys_offset_offset = 4;

    pub const lang_sys_required_feature_index_offset = 2;
    pub const lang_sys_feature_count_offset = 4;
    pub const lang_sys_feature_indices_offset = 6;
    pub const feature_data_lookup_count_offset = 2;
    pub const feature_data_lookup_indices_offset = 4;

    pub const lookup_type_offset = 0;
    pub const lookup_subtable_count_offset = 4;
    pub const lookup_subtable_offsets_offset = 6;

    pub const script_list_count_offset = 0;
    pub const script_record_size = 6;
    pub const script_tag_offset = 0;
    pub const script_offset_offset = 4;

    pub const feature_list_count_offset = 0;
    pub const feature_record_size = 6;
    pub const feature_tag_offset = 0;
    pub const feature_offset_offset = 4;

    pub const lookup_list_count_offset = 0;
    pub const lookup_offset_size = 2;
    pub const lookup_list_header_size = 2;

    pub fn findScriptOffset(data: []const u8, tag: [4]u8) font_parser.ParserError!?u16 {
        if (data.len < 2) return font_parser.ParserError.InvalidTable;
        const count = try readU16(data, script_list_count_offset);
        if (2 + @as(usize, count) * script_record_size > data.len) return font_parser.ParserError.InvalidTable;
        for (0..count) |i| {
            const offset = 2 + i * script_record_size;
            if (std.mem.eql(u8, data[offset + script_tag_offset ..][0..4], &tag)) {
                return try readU16(data, offset + script_offset_offset);
            }
        }
        return null;
    }

    pub fn findLangSysOffset(script_data: []const u8, tag: [4]u8) font_parser.ParserError!?u16 {
        if (script_data.len < script_lang_sys_records_offset) return font_parser.ParserError.InvalidTable;
        const count = try readU16(script_data, script_lang_sys_count_offset);
        if (script_lang_sys_records_offset + @as(usize, count) * script_lang_sys_record_size > script_data.len) return font_parser.ParserError.InvalidTable;

        for (0..count) |i| {
            const offset = script_lang_sys_records_offset + i * script_lang_sys_record_size;
            if (std.mem.eql(u8, script_data[offset + script_lang_sys_tag_offset ..][0..4], &tag)) {
                return try readU16(script_data, offset + script_lang_sys_offset_offset);
            }
        }
        return null;
    }

    pub fn getFeatureRecordOffset(feature_list: []const u8, feature_index: u16) font_parser.ParserError!usize {
        if (feature_list.len < feature_list_count_offset + 2) return font_parser.ParserError.InvalidTable;
        const feature_count = try readU16(feature_list, feature_list_count_offset);
        if (feature_index >= feature_count) return font_parser.ParserError.InvalidTable;
        const feature_offset = feature_list_count_offset + 2 + @as(usize, feature_index) * feature_record_size;
        if (feature_offset + feature_record_size > feature_list.len) return font_parser.ParserError.InvalidTable;
        return feature_offset;
    }

    pub fn featureMatches(feature_list: []const u8, feature_index: u16, selected_tags: ?[]const [4]u8) font_parser.ParserError!bool {
        const tags = selected_tags orelse return true;
        const feature_record_offset = try getFeatureRecordOffset(feature_list, feature_index);
        const feature_tag = feature_list[feature_record_offset + feature_tag_offset ..][0..4];
        for (tags) |tag| {
            if (std.mem.eql(u8, feature_tag, &tag)) return true;
        }
        return false;
    }

    pub fn appendLookupIndicesForFeature(feature_list: []const u8, feature_index: u16, lookup_indices: *std.ArrayList(u16), allocator: std.mem.Allocator) LayoutError!void {
        const feature_record_offset = try getFeatureRecordOffset(feature_list, feature_index);
        const feature_data_off = try readU16(feature_list, feature_record_offset + feature_offset_offset);
        const feature_data = try sliceFrom(feature_list, feature_data_off);
        const lookup_count = try readU16(feature_data, feature_data_lookup_count_offset);

        for (0..lookup_count) |i| {
            const lookup_index = try readU16(feature_data, feature_data_lookup_indices_offset + i * 2);
            try lookup_indices.append(allocator, lookup_index);
        }
    }

    pub fn collectLookupIndices(allocator: std.mem.Allocator, data: []const u8, options: ShapeOptions) LayoutError!std.ArrayList(u16) {
        var result = std.ArrayList(u16).empty;
        errdefer result.deinit(allocator);

        if (data.len < header_min_size) return font_parser.ParserError.InvalidTable;

        const script_list_off = try readU16(data, script_list_offset);
        const feature_list_off = try readU16(data, feature_list_offset);
        const script_list_data = try sliceFrom(data, script_list_off);
        const feature_list_data = try sliceFrom(data, feature_list_off);

        const script_off_val = blk: {
            if (options.script_tag) |script_tag| {
                if (try findScriptOffset(script_list_data, script_tag)) |script_off| break :blk script_off;
            }
            var script_off = try findScriptOffset(script_list_data, default_script_tag);
            if (script_off == null) script_off = try findScriptOffset(script_list_data, latin_script_tag);
            break :blk script_off;
        };
        const actual_script_off = script_off_val orelse return result;
        const script_data = try sliceFrom(script_list_data, actual_script_off);

        const lang_sys_off_val = if (options.language_tag) |language_tag|
            try findLangSysOffset(script_data, language_tag)
        else
            null;
        const lang_sys_off = lang_sys_off_val orelse try readU16(script_data, script_default_lang_sys_offset);
        if (lang_sys_off == 0) return result;

        const lang_sys_data = try sliceFrom(script_data, lang_sys_off);
        const required_feature_index = try readU16(lang_sys_data, lang_sys_required_feature_index_offset);
        if (required_feature_index != required_feature_none) {
            try appendLookupIndicesForFeature(feature_list_data, required_feature_index, &result, allocator);
        }

        const feature_count = try readU16(lang_sys_data, lang_sys_feature_count_offset);
        for (0..feature_count) |i| {
            const feature_index = try readU16(lang_sys_data, lang_sys_feature_indices_offset + i * 2);
            if (try featureMatches(feature_list_data, feature_index, options.feature_tags)) {
                try appendLookupIndicesForFeature(feature_list_data, feature_index, &result, allocator);
            }
        }

        return result;
    }

    pub fn getLookupOffset(data: []const u8, index: u16) font_parser.ParserError!u16 {
        if (data.len < lookup_list_header_size) return font_parser.ParserError.InvalidTable;
        const count = try readU16(data, lookup_list_count_offset);
        if (index >= count) return font_parser.ParserError.InvalidTable;
        if (lookup_list_header_size + @as(usize, count) * lookup_offset_size > data.len) return font_parser.ParserError.InvalidTable;
        return try readU16(data, lookup_list_header_size + @as(usize, index) * lookup_offset_size);
    }
};

pub fn sliceFrom(data: []const u8, offset: usize) font_parser.ParserError![]const u8 {
    if (offset > data.len) return font_parser.ParserError.InvalidTable;
    return data[offset..];
}

pub fn sliceRange(data: []const u8, offset: usize, len: usize) font_parser.ParserError![]const u8 {
    if (offset > data.len or len > data.len - offset) return font_parser.ParserError.InvalidTable;
    return data[offset .. offset + len];
}

pub const Coverage = struct {
    pub const format_offset = 0;
    pub const format1 = 1;
    pub const format2 = 2;
    pub const format1_count_offset = 2;
    pub const format1_glyphs_offset = 4;
    pub const format2_count_offset = 2;
    pub const format2_ranges_offset = 4;
    pub const range_record_size = 6;
    pub const range_start_offset = 0;
    pub const range_end_offset = 2;
    pub const range_index_offset = 4;

    pub fn getIndex(data: []const u8, glyph_id: u16) font_parser.ParserError!?u16 {
        if (data.len < 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(data, format_offset);
        if (format == format1) {
            const count = try readU16(data, format1_count_offset);
            if (format1_glyphs_offset + @as(usize, count) * 2 > data.len) return font_parser.ParserError.InvalidTable;
            var low: usize = 0;
            var high: usize = count;
            while (low < high) {
                const mid = low + (high - low) / 2;
                const gid = try readU16(data, format1_glyphs_offset + mid * 2);
                if (glyph_id < gid) {
                    high = mid;
                } else if (glyph_id > gid) {
                    low = mid + 1;
                } else {
                    return @as(u16, @intCast(mid));
                }
            }
        } else if (format == format2) {
            const count = try readU16(data, format2_count_offset);
            if (format2_ranges_offset + @as(usize, count) * range_record_size > data.len) return font_parser.ParserError.InvalidTable;
            var low: usize = 0;
            var high: usize = count;
            while (low < high) {
                const mid = low + (high - low) / 2;
                const range_offset = format2_ranges_offset + mid * range_record_size;
                const start = try readU16(data, range_offset + range_start_offset);
                const end = try readU16(data, range_offset + range_end_offset);
                const start_index = try readU16(data, range_offset + range_index_offset);
                if (glyph_id < start) {
                    high = mid;
                } else if (glyph_id > end) {
                    low = mid + 1;
                } else {
                    return start_index + (glyph_id - start);
                }
            }
        }
        return null;
    }
};

pub const ClassDef = struct {
    pub const format1 = 1;
    pub const format2 = 2;
    pub const format1_start_offset = 2;
    pub const format1_count_offset = 4;
    pub const format1_classes_offset = 6;
    pub const format2_count_offset = 2;
    pub const format2_ranges_offset = 4;
    pub const range_record_size = 6;
    pub const range_start_offset = 0;
    pub const range_end_offset = 2;
    pub const range_class_offset = 4;

    pub fn getClass(data: []const u8, glyph_id: u16) font_parser.ParserError!u16 {
        if (data.len < 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(data, 0);
        if (format == format1) {
            const start = try readU16(data, format1_start_offset);
            const count = try readU16(data, format1_count_offset);
            if (format1_classes_offset + @as(usize, count) * 2 > data.len) return font_parser.ParserError.InvalidTable;
            if (glyph_id >= start and glyph_id < start + count) {
                return try readU16(data, format1_classes_offset + @as(usize, glyph_id - start) * 2);
            }
        } else if (format == format2) {
            const count = try readU16(data, format2_count_offset);
            if (format2_ranges_offset + @as(usize, count) * range_record_size > data.len) return font_parser.ParserError.InvalidTable;
            var low: usize = 0;
            var high: usize = count;
            while (low < high) {
                const mid = low + (high - low) / 2;
                const range_offset = format2_ranges_offset + mid * range_record_size;
                const start = try readU16(data, range_offset + range_start_offset);
                const end = try readU16(data, range_offset + range_end_offset);
                const class = try readU16(data, range_offset + range_class_offset);
                if (glyph_id < start) {
                    high = mid;
                } else if (glyph_id > end) {
                    low = mid + 1;
                } else {
                    return class;
                }
            }
        }
        return 0;
    }
};

test "coverage format 1 lookup" {
    var data = [_]u8{0} ** 10;
    test_utils.writeU16(&data, 0, 1);
    test_utils.writeU16(&data, 2, 3);
    test_utils.writeU16(&data, 4, 10);
    test_utils.writeU16(&data, 6, 20);
    test_utils.writeU16(&data, 8, 30);

    try std.testing.expectEqual(@as(?u16, 0), try Coverage.getIndex(&data, 10));
    try std.testing.expectEqual(@as(?u16, 1), try Coverage.getIndex(&data, 20));
    try std.testing.expectEqual(@as(?u16, 2), try Coverage.getIndex(&data, 30));
    try std.testing.expectEqual(@as(?u16, null), try Coverage.getIndex(&data, 15));
}

test "coverage format 2 lookup" {
    var data = [_]u8{0} ** 16;
    test_utils.writeU16(&data, 0, 2);
    test_utils.writeU16(&data, 2, 2);
    test_utils.writeU16(&data, 4, 10);
    test_utils.writeU16(&data, 6, 12);
    test_utils.writeU16(&data, 8, 0);
    test_utils.writeU16(&data, 10, 20);
    test_utils.writeU16(&data, 12, 25);
    test_utils.writeU16(&data, 14, 3);

    try std.testing.expectEqual(@as(?u16, 0), try Coverage.getIndex(&data, 10));
    try std.testing.expectEqual(@as(?u16, 1), try Coverage.getIndex(&data, 11));
    try std.testing.expectEqual(@as(?u16, 3), try Coverage.getIndex(&data, 20));
    try std.testing.expectEqual(@as(?u16, 8), try Coverage.getIndex(&data, 25));
    try std.testing.expectEqual(@as(?u16, null), try Coverage.getIndex(&data, 15));
}

test "class def format 2 lookup" {
    var data = [_]u8{0} ** 16;
    test_utils.writeU16(&data, 0, 2);
    test_utils.writeU16(&data, 2, 2);
    test_utils.writeU16(&data, 4, 10);
    test_utils.writeU16(&data, 6, 12);
    test_utils.writeU16(&data, 8, 1);
    test_utils.writeU16(&data, 10, 20);
    test_utils.writeU16(&data, 12, 25);
    test_utils.writeU16(&data, 14, 2);

    try std.testing.expectEqual(@as(u16, 1), try ClassDef.getClass(&data, 10));
    try std.testing.expectEqual(@as(u16, 1), try ClassDef.getClass(&data, 11));
    try std.testing.expectEqual(@as(u16, 2), try ClassDef.getClass(&data, 20));
    try std.testing.expectEqual(@as(u16, 0), try ClassDef.getClass(&data, 15));
}

test "sliceFrom rejects out of range offsets" {
    const data = [_]u8{ 1, 2, 3 };
    try std.testing.expectError(font_parser.ParserError.InvalidTable, sliceFrom(&data, 4));
    try std.testing.expectEqualSlices(u8, data[3..], try sliceFrom(&data, 3));
}
