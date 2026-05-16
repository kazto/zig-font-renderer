const std = @import("std");
const binary_reader = @import("binary_reader.zig");

const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;
const readU32 = binary_reader.readU32;
const tagToU32 = binary_reader.tagToU32;

const Sfnt = struct {
    const header_size = 12;
    const num_tables_offset = 4;
    const table_record_size = 16;
    const table_record_tag_offset = 0;
    const table_record_offset_offset = 8;
    const table_record_length_offset = 12;
    const truetype_flavor = 0x00010000;
};

const TableTags = struct {
    const cff = "CFF ".*;
    const cmap = "cmap".*;
    const glyf = "glyf".*;
    const head = "head".*;
    const hhea = "hhea".*;
    const hmtx = "hmtx".*;
    const maxp = "maxp".*;
    const vorg = "VORG".*;
    const vhea = "vhea".*;
    const vmtx = "vmtx".*;
    const otto = "OTTO".*;
};

const Head = struct {
    const min_size = 20;
    const units_per_em_offset = 18;
};

const Maxp = struct {
    const min_size = 6;
    const num_glyphs_offset = 4;
};

const Hhea = struct {
    const min_size = 36;
    const number_of_h_metrics_offset = 34;
};

const Vhea = struct {
    const min_size = 36;
    const number_of_v_metrics_offset = 34;
};

const Vorg = struct {
    const min_size = 10;
    const version_offset = 0;
    const version_minor_offset = 2;
    const default_vert_origin_y_offset = 4;
    const num_vert_origin_y_metrics_offset = 6;
    const record_size = 4;
    const glyph_index_offset = 0;
    const vert_origin_y_offset = 2;
    const expected_major_version = 1;
    const expected_minor_version = 0;
};

const Hmtx = struct {
    const long_metric_size = 4;
    const lsb_offset = 2;
    const short_lsb_size = 2;
};

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

pub const ParserError = error{
    InvalidFontFormat,
    MissingMandatoryTable,
    TableOutOfBounds,
    InvalidTable,
    UnsupportedCmapFormat,
    InvalidGlyphId,
};

pub const TableMetadata = struct {
    tag: [4]u8,
    offset: u32,
    length: u32,
};

pub const HMetric = struct {
    advance_width: u16,
    lsb: i16,
};

pub const VMetric = struct {
    advance_height: u16,
    tsb: i16,
};

pub const GlyphInfo = struct {
    id: u16,
    advance_width: u16,
    lsb: i16,
};

const CmapSelection = struct {
    offset: u32,
    format: u16,
};

pub const Face = struct {
    data: []const u8,
    units_per_em: u16,
    num_glyphs: u16,
    tables: []const TableMetadata,
    number_of_h_metrics: u16,
    number_of_v_metrics: ?u16,
    vorg_default_vert_origin_y: ?i16,
    vorg: ?TableMetadata,
    cmap: ?CmapSelection,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) ParserError!Face {
        if (data.len < Sfnt.header_size) return ParserError.InvalidFontFormat;

        const flavor = try readU32(data, 0);
        if (flavor != Sfnt.truetype_flavor and flavor != tagToU32(TableTags.otto)) {
            return ParserError.InvalidFontFormat;
        }

        const num_tables = try readU16(data, Sfnt.num_tables_offset);
        const directory_len = Sfnt.header_size + @as(usize, num_tables) * Sfnt.table_record_size;
        if (directory_len > data.len) return ParserError.TableOutOfBounds;

        const tables = allocator.alloc(TableMetadata, num_tables) catch return ParserError.InvalidTable;
        errdefer allocator.free(tables);

        for (tables, 0..) |*table, index| {
            const record_offset = Sfnt.header_size + index * Sfnt.table_record_size;
            const offset = try readU32(data, record_offset + Sfnt.table_record_offset_offset);
            const length = try readU32(data, record_offset + Sfnt.table_record_length_offset);
            try validateRange(data, offset, length);

            table.* = .{
                .tag = data[record_offset + Sfnt.table_record_tag_offset ..][0..4].*,
                .offset = offset,
                .length = length,
            };
        }

        const head = try requiredTable(data, tables, TableTags.head);
        const maxp = try requiredTable(data, tables, TableTags.maxp);
        const hhea = try requiredTable(data, tables, TableTags.hhea);
        _ = try requiredTable(data, tables, TableTags.hmtx);
        _ = try requiredTable(data, tables, TableTags.cmap);
        if (findTable(tables, TableTags.glyf) == null and findTable(tables, TableTags.cff) == null) {
            return ParserError.MissingMandatoryTable;
        }

        if (head.len < Head.min_size or maxp.len < Maxp.min_size or hhea.len < Hhea.min_size) return ParserError.InvalidTable;

        const units_per_em = try readU16(head, Head.units_per_em_offset);
        const num_glyphs = try readU16(maxp, Maxp.num_glyphs_offset);
        const number_of_h_metrics = try readU16(hhea, Hhea.number_of_h_metrics_offset);
        if (number_of_h_metrics == 0) return ParserError.InvalidTable;

        const vhea = findTable(tables, TableTags.vhea);
        const vmtx = findTable(tables, TableTags.vmtx);
        if ((vhea == null) != (vmtx == null)) return ParserError.InvalidTable;
        const number_of_v_metrics = if (vhea) |vhea_table| blk: {
            if (vhea_table.length < Vhea.min_size) return ParserError.InvalidTable;
            const vhea_data = data[vhea_table.offset..][0..vhea_table.length];
            break :blk try readU16(vhea_data, Vhea.number_of_v_metrics_offset);
        } else null;

        const vorg = findTable(tables, TableTags.vorg);
        const vorg_default_vert_origin_y = if (vorg) |vorg_table| blk: {
            if (vorg_table.length < Vorg.min_size) return ParserError.InvalidTable;
            const vorg_data = data[vorg_table.offset..][0..vorg_table.length];
            if (try readU16(vorg_data, Vorg.version_offset) != Vorg.expected_major_version) return ParserError.InvalidTable;
            if (try readU16(vorg_data, Vorg.version_minor_offset) != Vorg.expected_minor_version) return ParserError.InvalidTable;
            break :blk try readI16(vorg_data, Vorg.default_vert_origin_y_offset);
        } else null;

        return .{
            .data = data,
            .units_per_em = units_per_em,
            .num_glyphs = num_glyphs,
            .tables = tables,
            .number_of_h_metrics = number_of_h_metrics,
            .number_of_v_metrics = number_of_v_metrics,
            .vorg_default_vert_origin_y = vorg_default_vert_origin_y,
            .vorg = vorg,
            .cmap = try selectCmap(data, tables),
        };
    }

    pub fn deinit(self: *Face, allocator: std.mem.Allocator) void {
        allocator.free(self.tables);
        self.* = undefined;
    }

    pub fn getTable(self: Face, tag: [4]u8) ?[]const u8 {
        const metadata = findTable(self.tables, tag) orelse return null;
        return self.data[metadata.offset..][0..metadata.length];
    }

    pub fn requireTable(self: Face, tag: [4]u8) ParserError![]const u8 {
        return self.getTable(tag) orelse ParserError.MissingMandatoryTable;
    }

    pub fn getGlyphId(self: Face, codepoint: u32) ParserError!u16 {
        const cmap = self.cmap orelse return ParserError.MissingMandatoryTable;
        const cmap_table = try self.requireTable(TableTags.cmap);
        return switch (cmap.format) {
            Cmap.format4 => try lookupCmapFormat4(cmap_table, cmap.offset, codepoint),
            Cmap.format12 => try lookupCmapFormat12(cmap_table, cmap.offset, codepoint),
            else => ParserError.UnsupportedCmapFormat,
        };
    }

    pub fn getHMetric(self: Face, glyph_id: u16) ParserError!HMetric {
        if (glyph_id >= self.num_glyphs) return ParserError.InvalidGlyphId;

        const hmtx = try self.requireTable(TableTags.hmtx);
        const metric_count = @as(usize, self.number_of_h_metrics);
        const glyph_index = @as(usize, glyph_id);
        if (metric_count == 0) return ParserError.InvalidTable;

        if (glyph_index < metric_count) {
            const offset = glyph_index * Hmtx.long_metric_size;
            if (offset + Hmtx.long_metric_size > hmtx.len) return ParserError.InvalidTable;
            return .{
                .advance_width = try readU16(hmtx, offset),
                .lsb = try readI16(hmtx, offset + Hmtx.lsb_offset),
            };
        }

        const last_metric_offset = (metric_count - 1) * Hmtx.long_metric_size;
        const lsb_offset = metric_count * Hmtx.long_metric_size + (glyph_index - metric_count) * Hmtx.short_lsb_size;
        if (last_metric_offset + Hmtx.long_metric_size > hmtx.len or lsb_offset + Hmtx.short_lsb_size > hmtx.len) {
            return ParserError.InvalidTable;
        }

        return .{
            .advance_width = try readU16(hmtx, last_metric_offset),
            .lsb = try readI16(hmtx, lsb_offset),
        };
    }

    pub fn getVMetric(self: Face, glyph_id: u16) ParserError!VMetric {
        if (glyph_id >= self.num_glyphs) return ParserError.InvalidGlyphId;

        const vmtx = self.getTable(TableTags.vmtx) orelse {
            const metric = try self.getHMetric(glyph_id);
            return .{ .advance_height = metric.advance_width, .tsb = 0 };
        };

        const metric_count = self.number_of_v_metrics orelse {
            const metric = try self.getHMetric(glyph_id);
            return .{ .advance_height = metric.advance_width, .tsb = 0 };
        };
        if (metric_count == 0) return ParserError.InvalidTable;

        const glyph_index = @as(usize, glyph_id);
        const count = @as(usize, metric_count);
        if (glyph_index < count) {
            const offset = glyph_index * Hmtx.long_metric_size;
            if (offset + Hmtx.long_metric_size > vmtx.len) return ParserError.InvalidTable;
            return .{
                .advance_height = try readU16(vmtx, offset),
                .tsb = try readI16(vmtx, offset + Hmtx.lsb_offset),
            };
        }

        const last_metric_offset = (count - 1) * Hmtx.long_metric_size;
        const tsb_offset = count * Hmtx.long_metric_size + (glyph_index - count) * Hmtx.short_lsb_size;
        if (last_metric_offset + Hmtx.long_metric_size > vmtx.len or tsb_offset + Hmtx.short_lsb_size > vmtx.len) {
            return ParserError.InvalidTable;
        }

        return .{
            .advance_height = try readU16(vmtx, last_metric_offset),
            .tsb = try readI16(vmtx, tsb_offset),
        };
    }

    pub fn getVerticalOriginY(self: Face, glyph_id: u16) ParserError!?i16 {
        const vorg = self.vorg orelse return null;
        const vorg_data = self.data[vorg.offset..][0..vorg.length];
        if (vorg_data.len < Vorg.min_size) return ParserError.InvalidTable;

        const count = try readU16(vorg_data, Vorg.num_vert_origin_y_metrics_offset);
        const records_offset = Vorg.min_size;
        if (records_offset + @as(usize, count) * Vorg.record_size > vorg_data.len) return ParserError.InvalidTable;

        var low: usize = 0;
        var high: usize = count;
        while (low < high) {
            const mid = low + (high - low) / 2;
            const record = records_offset + mid * Vorg.record_size;
            const record_glyph_id = try readU16(vorg_data, record + Vorg.glyph_index_offset);
            if (glyph_id < record_glyph_id) {
                high = mid;
            } else if (glyph_id > record_glyph_id) {
                low = mid + 1;
            } else {
                return try readI16(vorg_data, record + Vorg.vert_origin_y_offset);
            }
        }

        return self.vorg_default_vert_origin_y;
    }

    pub fn getGlyphInfo(self: Face, codepoint: u32) ParserError!GlyphInfo {
        const glyph_id = try self.getGlyphId(codepoint);
        const metric = try self.getHMetric(glyph_id);
        return .{
            .id = glyph_id,
            .advance_width = metric.advance_width,
            .lsb = metric.lsb,
        };
    }
};

fn findTable(tables: []const TableMetadata, tag: [4]u8) ?TableMetadata {
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, &tag)) return table;
    }
    return null;
}

fn requiredTable(data: []const u8, tables: []const TableMetadata, tag: [4]u8) ParserError![]const u8 {
    const metadata = findTable(tables, tag) orelse return ParserError.MissingMandatoryTable;
    return data[metadata.offset..][0..metadata.length];
}

fn selectCmap(data: []const u8, tables: []const TableMetadata) ParserError!?CmapSelection {
    const cmap = try requiredTable(data, tables, TableTags.cmap);
    if (cmap.len < Cmap.header_size) return ParserError.InvalidTable;

    const num_tables = try readU16(cmap, Cmap.num_tables_offset);
    if (Cmap.header_size + @as(usize, num_tables) * Cmap.encoding_record_size > cmap.len) return ParserError.InvalidTable;

    var fallback: ?CmapSelection = null;
    var best: ?CmapSelection = null;
    var best_priority: u8 = Cmap.priority_unset;

    var index: usize = 0;
    while (index < num_tables) : (index += 1) {
        const record = Cmap.header_size + index * Cmap.encoding_record_size;
        const platform_id = try readU16(cmap, record + Cmap.platform_id_offset);
        const encoding_id = try readU16(cmap, record + Cmap.encoding_id_offset);
        const offset = try readU32(cmap, record + Cmap.subtable_offset_offset);
        if (offset + Cmap.format_size > cmap.len) return ParserError.InvalidTable;

        const format = try readU16(cmap, offset);
        const selection: CmapSelection = .{ .offset = offset, .format = format };
        if (fallback == null) fallback = selection;

        const priority = cmapPriority(platform_id, encoding_id);
        if (priority < best_priority) {
            best = selection;
            best_priority = priority;
        }
    }

    return best orelse fallback;
}

fn cmapPriority(platform_id: u16, encoding_id: u16) u8 {
    if (platform_id == Cmap.windows_platform_id and encoding_id == Cmap.windows_full_unicode_encoding_id) return Cmap.priority_windows_full_unicode;
    if (platform_id == Cmap.windows_platform_id and encoding_id == Cmap.windows_bmp_encoding_id) return Cmap.priority_windows_bmp;
    if (platform_id == Cmap.unicode_platform_id) return Cmap.priority_unicode;
    return Cmap.priority_fallback;
}

fn lookupCmapFormat4(cmap: []const u8, offset: u32, codepoint: u32) ParserError!u16 {
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

fn lookupCmapFormat12(cmap: []const u8, offset: u32, codepoint: u32) ParserError!u16 {
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

fn validateRange(data: []const u8, offset: u32, length: u32) ParserError!void {
    const start = @as(usize, offset);
    const len = @as(usize, length);
    if (start > data.len or len > data.len - start) return ParserError.TableOutOfBounds;
}

fn wrapU16(value: i32) u16 {
    return @intCast(@mod(value, 1 << 16));
}

test "invalid flavor is rejected" {
    const allocator = std.testing.allocator;
    const data = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    try std.testing.expectError(ParserError.InvalidFontFormat, Face.init(allocator, &data));
}

test "table range validation rejects out of bounds records" {
    const allocator = std.testing.allocator;
    var data = [_]u8{0} ** 28;
    writeU32(&data, 0, 0x00010000);
    writeU16(&data, 4, 1);
    @memcpy(data[12..16], "head");
    writeU32(&data, 20, 24);
    writeU32(&data, 24, 64);

    try std.testing.expectError(ParserError.TableOutOfBounds, Face.init(allocator, &data));
}

test "minimal format 4 cmap parses glyph and metrics" {
    const allocator = std.testing.allocator;
    var data = [_]u8{0} ** 288;
    buildMinimalFont(&data);

    var face = try Face.init(allocator, &data);
    defer face.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 1000), face.units_per_em);
    try std.testing.expectEqual(@as(u16, 3), face.num_glyphs);
    try std.testing.expectEqual(@as(u16, 1), try face.getGlyphId('A'));
    try std.testing.expectEqual(@as(u16, 0), try face.getGlyphId('B'));

    const metric = try face.getHMetric(1);
    try std.testing.expectEqual(@as(u16, 610), metric.advance_width);
    try std.testing.expectEqual(@as(i16, 11), metric.lsb);
}

test "vertical metrics lookup reads vmtx records" {
    const data = [_]u8{
        0x03, 0xE8, 0x00, 0x10,
        0x03, 0x20, 0x00, 0x20,
        0x00, 0x30, 0x00, 0x40,
    };
    const tables = [_]TableMetadata{.{
        .tag = TableTags.vmtx,
        .offset = 0,
        .length = data.len,
    }};
    const face = Face{
        .data = &data,
        .units_per_em = 1000,
        .num_glyphs = 3,
        .tables = &tables,
        .number_of_h_metrics = 1,
        .number_of_v_metrics = 2,
        .vorg_default_vert_origin_y = null,
        .vorg = null,
        .cmap = null,
    };

    const first = try face.getVMetric(0);
    try std.testing.expectEqual(@as(u16, 1000), first.advance_height);
    try std.testing.expectEqual(@as(i16, 16), first.tsb);

    const middle = try face.getVMetric(1);
    try std.testing.expectEqual(@as(u16, 800), middle.advance_height);
    try std.testing.expectEqual(@as(i16, 32), middle.tsb);

    const trailing = try face.getVMetric(2);
    try std.testing.expectEqual(@as(u16, 800), trailing.advance_height);
    try std.testing.expectEqual(@as(i16, 48), trailing.tsb);
}

test "format 12 cmap parses UCS-4 glyphs" {
    const allocator = std.testing.allocator;
    var data = [_]u8{0} ** 288;
    buildMinimalFont(&data);
    writeU16(&data, 4, 6);
    @memcpy(data[92..96], "cmap");
    writeU32(&data, 100, 200);
    writeU32(&data, 104, 44);
    writeU16(&data, 200, 0);
    writeU16(&data, 202, 1);
    writeU16(&data, 204, 3);
    writeU16(&data, 206, 10);
    writeU32(&data, 208, 12);
    writeU16(&data, 212, 12);
    writeU16(&data, 214, 0);
    writeU32(&data, 216, 28);
    writeU32(&data, 220, 0);
    writeU32(&data, 224, 1);
    writeU32(&data, 228, 0x1F600);
    writeU32(&data, 232, 0x1F600);
    writeU32(&data, 236, 2);

    var face = try Face.init(allocator, &data);
    defer face.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 2), try face.getGlyphId(0x1F600));
    try std.testing.expectEqual(@as(u16, 0), try face.getGlyphId(0x1F601));
}

fn buildMinimalFont(data: []u8) void {
    writeU32(data, 0, 0x00010000);
    writeU16(data, 4, 6);

    writeRecord(data, 12, "head".*, 108, 54);
    writeRecord(data, 28, "maxp".*, 164, 6);
    writeRecord(data, 44, "hhea".*, 172, 36);
    writeRecord(data, 60, "hmtx".*, 208, 12);
    writeRecord(data, 76, "glyf".*, 220, 4);
    writeRecord(data, 92, "cmap".*, 224, 36);

    writeU16(data, 108 + 18, 1000);
    writeU16(data, 164 + 4, 3);
    writeU16(data, 172 + 34, 3);
    writeU16(data, 208, 600);
    writeI16(data, 210, 10);
    writeU16(data, 212, 610);
    writeI16(data, 214, 11);
    writeU16(data, 216, 620);
    writeI16(data, 218, 12);

    writeU16(data, 224, 0);
    writeU16(data, 226, 1);
    writeU16(data, 228, 3);
    writeU16(data, 230, 1);
    writeU32(data, 232, 12);

    writeU16(data, 236, 4);
    writeU16(data, 238, 24);
    writeU16(data, 240, 0);
    writeU16(data, 242, 2);
    writeU16(data, 244, 0);
    writeU16(data, 246, 0);
    writeU16(data, 248, 0);
    writeU16(data, 250, 'A');
    writeU16(data, 252, 0);
    writeU16(data, 254, 'A');
    writeI16(data, 256, -64);
    writeU16(data, 258, 0);
}

fn writeRecord(data: []u8, offset: usize, tag: [4]u8, table_offset: u32, length: u32) void {
    @memcpy(data[offset..][0..4], &tag);
    writeU32(data, offset + 8, table_offset);
    writeU32(data, offset + 12, length);
}

fn writeU16(data: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, data[offset..][0..2], value, .big);
}

fn writeI16(data: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, data[offset..][0..2], value, .big);
}

fn writeU32(data: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, data[offset..][0..4], value, .big);
}
