const std = @import("std");

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
    cmap: ?CmapSelection,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) ParserError!Face {
        if (data.len < 12) return ParserError.InvalidFontFormat;

        const flavor = try readU32(data, 0);
        if (flavor != 0x00010000 and flavor != tagToU32("OTTO".*)) {
            return ParserError.InvalidFontFormat;
        }

        const num_tables = try readU16(data, 4);
        const directory_len = 12 + @as(usize, num_tables) * 16;
        if (directory_len > data.len) return ParserError.TableOutOfBounds;

        const tables = allocator.alloc(TableMetadata, num_tables) catch return ParserError.InvalidTable;
        errdefer allocator.free(tables);

        for (tables, 0..) |*table, index| {
            const record_offset = 12 + index * 16;
            const offset = try readU32(data, record_offset + 8);
            const length = try readU32(data, record_offset + 12);
            try validateRange(data, offset, length);

            table.* = .{
                .tag = data[record_offset..][0..4].*,
                .offset = offset,
                .length = length,
            };
        }

        const head = try requiredTable(data, tables, "head".*);
        const maxp = try requiredTable(data, tables, "maxp".*);
        const hhea = try requiredTable(data, tables, "hhea".*);
        _ = try requiredTable(data, tables, "hmtx".*);
        _ = try requiredTable(data, tables, "cmap".*);
        if (findTable(tables, "glyf".*) == null and findTable(tables, "CFF ".*) == null) {
            return ParserError.MissingMandatoryTable;
        }

        if (head.len < 20 or maxp.len < 6 or hhea.len < 36) return ParserError.InvalidTable;

        const units_per_em = try readU16(head, 18);
        const num_glyphs = try readU16(maxp, 4);
        const number_of_h_metrics = try readU16(hhea, 34);
        if (number_of_h_metrics == 0) return ParserError.InvalidTable;

        return .{
            .data = data,
            .units_per_em = units_per_em,
            .num_glyphs = num_glyphs,
            .tables = tables,
            .number_of_h_metrics = number_of_h_metrics,
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
        const cmap_table = try self.requireTable("cmap".*);
        return switch (cmap.format) {
            4 => try lookupCmapFormat4(cmap_table, cmap.offset, codepoint),
            12 => try lookupCmapFormat12(cmap_table, cmap.offset, codepoint),
            else => ParserError.UnsupportedCmapFormat,
        };
    }

    pub fn getHMetric(self: Face, glyph_id: u16) ParserError!HMetric {
        if (glyph_id >= self.num_glyphs) return ParserError.InvalidGlyphId;

        const hmtx = try self.requireTable("hmtx".*);
        const metric_count = @as(usize, self.number_of_h_metrics);
        const glyph_index = @as(usize, glyph_id);
        if (metric_count == 0) return ParserError.InvalidTable;

        if (glyph_index < metric_count) {
            const offset = glyph_index * 4;
            if (offset + 4 > hmtx.len) return ParserError.InvalidTable;
            return .{
                .advance_width = try readU16(hmtx, offset),
                .lsb = try readI16(hmtx, offset + 2),
            };
        }

        const last_metric_offset = (metric_count - 1) * 4;
        const lsb_offset = metric_count * 4 + (glyph_index - metric_count) * 2;
        if (last_metric_offset + 4 > hmtx.len or lsb_offset + 2 > hmtx.len) {
            return ParserError.InvalidTable;
        }

        return .{
            .advance_width = try readU16(hmtx, last_metric_offset),
            .lsb = try readI16(hmtx, lsb_offset),
        };
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
    const cmap = try requiredTable(data, tables, "cmap".*);
    if (cmap.len < 4) return ParserError.InvalidTable;

    const num_tables = try readU16(cmap, 2);
    if (4 + @as(usize, num_tables) * 8 > cmap.len) return ParserError.InvalidTable;

    var fallback: ?CmapSelection = null;
    var best: ?CmapSelection = null;
    var best_priority: u8 = 255;

    var index: usize = 0;
    while (index < num_tables) : (index += 1) {
        const record = 4 + index * 8;
        const platform_id = try readU16(cmap, record);
        const encoding_id = try readU16(cmap, record + 2);
        const offset = try readU32(cmap, record + 4);
        if (offset + 2 > cmap.len) return ParserError.InvalidTable;

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
    if (platform_id == 3 and encoding_id == 10) return 0;
    if (platform_id == 3 and encoding_id == 1) return 1;
    if (platform_id == 0) return 2;
    return 3;
}

fn lookupCmapFormat4(cmap: []const u8, offset: u32, codepoint: u32) ParserError!u16 {
    if (codepoint > 0xFFFF) return 0;
    const start = @as(usize, offset);
    if (start + 16 > cmap.len) return ParserError.InvalidTable;

    const length = try readU16(cmap, start + 2);
    if (start + length > cmap.len) return ParserError.InvalidTable;

    const seg_count_x2 = try readU16(cmap, start + 6);
    if (seg_count_x2 % 2 != 0) return ParserError.InvalidTable;
    const seg_count = @as(usize, seg_count_x2 / 2);
    const end_codes = start + 14;
    const reserved_pad = end_codes + seg_count * 2;
    const start_codes = reserved_pad + 2;
    const id_deltas = start_codes + seg_count * 2;
    const id_range_offsets = id_deltas + seg_count * 2;
    const glyph_array = id_range_offsets + seg_count * 2;
    if (glyph_array > start + length) return ParserError.InvalidTable;

    const cp = @as(u16, @intCast(codepoint));
    var i: usize = 0;
    while (i < seg_count) : (i += 1) {
        const end_code = try readU16(cmap, end_codes + i * 2);
        if (cp > end_code) continue;

        const start_code = try readU16(cmap, start_codes + i * 2);
        if (cp < start_code) return 0;

        const delta = try readI16(cmap, id_deltas + i * 2);
        const range_offset_location = id_range_offsets + i * 2;
        const range_offset = try readU16(cmap, range_offset_location);
        if (range_offset == 0) {
            return wrapU16(@as(i32, cp) + @as(i32, delta));
        }

        const glyph_index_offset = range_offset_location + range_offset + (@as(usize, cp - start_code) * 2);
        if (glyph_index_offset + 2 > start + length) return ParserError.InvalidTable;
        const glyph_id = try readU16(cmap, glyph_index_offset);
        if (glyph_id == 0) return 0;
        return wrapU16(@as(i32, glyph_id) + @as(i32, delta));
    }

    return 0;
}

fn lookupCmapFormat12(cmap: []const u8, offset: u32, codepoint: u32) ParserError!u16 {
    const start = @as(usize, offset);
    if (start + 16 > cmap.len) return ParserError.InvalidTable;

    const length = try readU32(cmap, start + 4);
    if (start + length > cmap.len) return ParserError.InvalidTable;

    const num_groups = try readU32(cmap, start + 12);
    if (16 + @as(usize, num_groups) * 12 > length) return ParserError.InvalidTable;

    var low: usize = 0;
    var high: usize = num_groups;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const group = start + 16 + mid * 12;
        const start_char = try readU32(cmap, group);
        const end_char = try readU32(cmap, group + 4);
        const start_glyph = try readU32(cmap, group + 8);

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

fn readU16(data: []const u8, offset: usize) ParserError!u16 {
    if (offset + 2 > data.len) return ParserError.InvalidTable;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readI16(data: []const u8, offset: usize) ParserError!i16 {
    if (offset + 2 > data.len) return ParserError.InvalidTable;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) ParserError!u32 {
    if (offset + 4 > data.len) return ParserError.InvalidTable;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

fn tagToU32(tag: [4]u8) u32 {
    return std.mem.readInt(u32, &tag, .big);
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
