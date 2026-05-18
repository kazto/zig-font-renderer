const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_types = @import("font_types.zig");

const ParserError = font_types.ParserError;
const VariationCoord = font_types.VariationCoord;
const VariationError = ParserError || std.mem.Allocator.Error;
const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;
const readU32 = binary_reader.readU32;
const readI32 = binary_reader.readI32;

const Fvar = struct {
    const min_size = 16;
    const expected_major_version = 1;
    const expected_minor_version = 0;
    const major_version_offset = 0;
    const minor_version_offset = 2;
    const axes_array_offset_offset = 4;
    const axis_count_offset = 8;
    const axis_size_offset = 10;
    const instance_count_offset = 12;
    const instance_size_offset = 14;
    const axis_record_min_size = 20;
    const axis_tag_offset = 0;
    const axis_min_value_offset = 4;
    const axis_default_value_offset = 8;
    const axis_max_value_offset = 12;
    const instance_header_size = 4;
};

const Avar = struct {
    const min_size = 8;
    const expected_major_version = 1;
    const expected_minor_version = 0;
    const major_version_offset = 0;
    const minor_version_offset = 2;
    const axis_count_offset = 6;
    const segment_count_size = 2;
    const segment_pair_size = 4;
    const segment_from_offset = 0;
    const segment_to_offset = 2;
};

const fixed_16_16_denominator = 65536.0;
const f2dot14_denominator = 16384.0;
const default_normalized_coord = 0.0;
const min_normalized_coord = -1.0;
const max_normalized_coord = 1.0;

pub fn normalizeCoords(allocator: std.mem.Allocator, fvar: []const u8, avar: ?[]const u8, coords: []const VariationCoord) VariationError![]f64 {
    const header = try readFvarHeader(fvar);

    const normalized = try allocator.alloc(f64, header.axis_count);
    errdefer allocator.free(normalized);

    var axis_index: usize = 0;
    while (axis_index < header.axis_count) : (axis_index += 1) {
        const axis_offset = axisRecordOffset(header, axis_index);
        const tag = fvar[axis_offset + Fvar.axis_tag_offset ..][0..4].*;
        const min_value = try readFixed16Dot16(fvar, axis_offset + Fvar.axis_min_value_offset);
        const default_value = try readFixed16Dot16(fvar, axis_offset + Fvar.axis_default_value_offset);
        const max_value = try readFixed16Dot16(fvar, axis_offset + Fvar.axis_max_value_offset);
        const value = designCoordForAxis(coords, tag) orelse default_value;
        normalized[axis_index] = normalizeAxisValue(value, min_value, default_value, max_value);
    }

    if (avar) |avar_table| try applyAvar(avar_table, normalized);
    return normalized;
}

pub fn normalizeInstanceCoords(allocator: std.mem.Allocator, fvar: []const u8, avar: ?[]const u8, instance_index: u16) VariationError![]f64 {
    const header = try readFvarHeader(fvar);
    if (instance_index >= header.instance_count) return ParserError.InvalidVariationInstanceIndex;
    const min_instance_size = Fvar.instance_header_size + @as(usize, header.axis_count) * @sizeOf(i32);
    if (header.instance_size < min_instance_size) return ParserError.InvalidTable;
    const instance_offset = header.instances_offset + @as(usize, instance_index) * header.instance_size;
    if (instance_offset + header.instance_size > fvar.len) return ParserError.InvalidTable;

    const normalized = try allocator.alloc(f64, header.axis_count);
    errdefer allocator.free(normalized);
    var axis_index: usize = 0;
    while (axis_index < header.axis_count) : (axis_index += 1) {
        const axis_offset = axisRecordOffset(header, axis_index);
        const min_value = try readFixed16Dot16(fvar, axis_offset + Fvar.axis_min_value_offset);
        const default_value = try readFixed16Dot16(fvar, axis_offset + Fvar.axis_default_value_offset);
        const max_value = try readFixed16Dot16(fvar, axis_offset + Fvar.axis_max_value_offset);
        const coord_offset = instance_offset + Fvar.instance_header_size + axis_index * @sizeOf(i32);
        const value = try readFixed16Dot16(fvar, coord_offset);
        normalized[axis_index] = normalizeAxisValue(value, min_value, default_value, max_value);
    }

    if (avar) |avar_table| try applyAvar(avar_table, normalized);
    return normalized;
}

pub fn instanceCount(fvar: []const u8) ParserError!u16 {
    return (try readFvarHeader(fvar)).instance_count;
}

const FvarHeader = struct {
    axes_offset: usize,
    axis_count: u16,
    axis_size: usize,
    instance_count: u16,
    instance_size: usize,
    instances_offset: usize,
};

fn readFvarHeader(fvar: []const u8) ParserError!FvarHeader {
    if (fvar.len < Fvar.min_size) return ParserError.InvalidTable;
    if (try readU16(fvar, Fvar.major_version_offset) != Fvar.expected_major_version) return ParserError.InvalidTable;
    if (try readU16(fvar, Fvar.minor_version_offset) != Fvar.expected_minor_version) return ParserError.InvalidTable;

    const axes_offset = @as(usize, try readU16(fvar, Fvar.axes_array_offset_offset));
    const axis_count = try readU16(fvar, Fvar.axis_count_offset);
    const axis_size = @as(usize, try readU16(fvar, Fvar.axis_size_offset));
    const instance_count_value = try readU16(fvar, Fvar.instance_count_offset);
    const instance_size = @as(usize, try readU16(fvar, Fvar.instance_size_offset));
    if (axis_size < Fvar.axis_record_min_size) return ParserError.InvalidTable;
    const axes_end = axes_offset + @as(usize, axis_count) * axis_size;
    if (axes_end > fvar.len) return ParserError.InvalidTable;
    const instances_end = axes_end + @as(usize, instance_count_value) * instance_size;
    if (instances_end > fvar.len) return ParserError.InvalidTable;
    return .{
        .axes_offset = axes_offset,
        .axis_count = axis_count,
        .axis_size = axis_size,
        .instance_count = instance_count_value,
        .instance_size = instance_size,
        .instances_offset = axes_end,
    };
}

fn axisRecordOffset(header: FvarHeader, axis_index: usize) usize {
    return header.axes_offset + axis_index * header.axis_size;
}

fn designCoordForAxis(coords: []const VariationCoord, tag: [4]u8) ?f64 {
    for (coords) |coord| {
        if (std.mem.eql(u8, &coord.tag, &tag)) return coord.value;
    }
    return null;
}

fn normalizeAxisValue(value: f64, min_value: f64, default_value: f64, max_value: f64) f64 {
    if (!std.math.isFinite(value)) return default_normalized_coord;
    if (value == default_value) return default_normalized_coord;
    if (value < default_value) {
        if (default_value == min_value) return default_normalized_coord;
        return std.math.clamp((value - default_value) / (default_value - min_value), min_normalized_coord, default_normalized_coord);
    }
    if (max_value == default_value) return default_normalized_coord;
    return std.math.clamp((value - default_value) / (max_value - default_value), default_normalized_coord, max_normalized_coord);
}

fn applyAvar(avar: []const u8, normalized: []f64) ParserError!void {
    if (avar.len < Avar.min_size) return ParserError.InvalidTable;
    if (try readU16(avar, Avar.major_version_offset) != Avar.expected_major_version) return ParserError.InvalidTable;
    if (try readU16(avar, Avar.minor_version_offset) != Avar.expected_minor_version) return ParserError.InvalidTable;
    const axis_count = try readU16(avar, Avar.axis_count_offset);
    if (axis_count != normalized.len) return ParserError.InvalidTable;

    var offset: usize = Avar.min_size;
    for (normalized) |*coord| {
        if (offset + Avar.segment_count_size > avar.len) return ParserError.InvalidTable;
        const segment_count = try readU16(avar, offset);
        offset += Avar.segment_count_size;
        const segments_offset = offset;
        const segments_len = @as(usize, segment_count) * Avar.segment_pair_size;
        if (segments_offset + segments_len > avar.len) return ParserError.InvalidTable;
        coord.* = try mapAvarAxis(avar[segments_offset .. segments_offset + segments_len], coord.*);
        offset += segments_len;
    }
}

fn mapAvarAxis(segments: []const u8, coord: f64) ParserError!f64 {
    if (segments.len == 0) return coord;

    var previous_from = try readF2Dot14(segments, Avar.segment_from_offset);
    var previous_to = try readF2Dot14(segments, Avar.segment_to_offset);
    if (coord <= previous_from) return previous_to;

    var offset: usize = Avar.segment_pair_size;
    while (offset < segments.len) : (offset += Avar.segment_pair_size) {
        const next_from = try readF2Dot14(segments, offset + Avar.segment_from_offset);
        const next_to = try readF2Dot14(segments, offset + Avar.segment_to_offset);
        if (next_from < previous_from) return ParserError.InvalidTable;
        if (coord <= next_from) {
            if (next_from == previous_from) return next_to;
            const t = (coord - previous_from) / (next_from - previous_from);
            return previous_to + t * (next_to - previous_to);
        }
        previous_from = next_from;
        previous_to = next_to;
    }
    return previous_to;
}

fn readFixed16Dot16(data: []const u8, offset: usize) ParserError!f64 {
    return @as(f64, @floatFromInt(try readI32(data, offset))) / fixed_16_16_denominator;
}

fn readF2Dot14(data: []const u8, offset: usize) ParserError!f64 {
    return @as(f64, @floatFromInt(try readI16(data, offset))) / f2dot14_denominator;
}

fn writeU16(data: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, data[offset..][0..2], value, .big);
}

fn writeI16(data: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, data[offset..][0..2], value, .big);
}

fn writeI32(data: []u8, offset: usize, value: i32) void {
    std.mem.writeInt(i32, data[offset..][0..4], value, .big);
}

test "fvar coordinates normalize design-space values" {
    var fvar = [_]u8{0} ** 40;
    writeU16(&fvar, Fvar.major_version_offset, Fvar.expected_major_version);
    writeU16(&fvar, Fvar.minor_version_offset, Fvar.expected_minor_version);
    writeU16(&fvar, Fvar.axes_array_offset_offset, 16);
    writeU16(&fvar, Fvar.axis_count_offset, 1);
    writeU16(&fvar, Fvar.axis_size_offset, Fvar.axis_record_min_size);
    @memcpy(fvar[16..20], "wght");
    writeI32(&fvar, 20, 100 << 16);
    writeI32(&fvar, 24, 400 << 16);
    writeI32(&fvar, 28, 900 << 16);

    const normalized = try normalizeCoords(std.testing.allocator, &fvar, null, &.{.{ .tag = "wght".*, .value = 650.0 }});
    defer std.testing.allocator.free(normalized);

    try std.testing.expectEqual(@as(usize, 1), normalized.len);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), normalized[0], 0.0001);
}

test "avar maps normalized coordinates with interpolation" {
    var fvar = [_]u8{0} ** 40;
    writeU16(&fvar, Fvar.major_version_offset, Fvar.expected_major_version);
    writeU16(&fvar, Fvar.minor_version_offset, Fvar.expected_minor_version);
    writeU16(&fvar, Fvar.axes_array_offset_offset, 16);
    writeU16(&fvar, Fvar.axis_count_offset, 1);
    writeU16(&fvar, Fvar.axis_size_offset, Fvar.axis_record_min_size);
    @memcpy(fvar[16..20], "wght");
    writeI32(&fvar, 20, 100 << 16);
    writeI32(&fvar, 24, 400 << 16);
    writeI32(&fvar, 28, 900 << 16);

    var avar = [_]u8{0} ** 22;
    writeU16(&avar, Avar.major_version_offset, Avar.expected_major_version);
    writeU16(&avar, Avar.minor_version_offset, Avar.expected_minor_version);
    writeU16(&avar, Avar.axis_count_offset, 1);
    writeU16(&avar, Avar.min_size, 3);
    writeI16(&avar, 10, -0x4000);
    writeI16(&avar, 12, -0x4000);
    writeI16(&avar, 14, 0);
    writeI16(&avar, 16, 0);
    writeI16(&avar, 18, 0x4000);
    writeI16(&avar, 20, 0x2000);

    const normalized = try normalizeCoords(std.testing.allocator, &fvar, &avar, &.{.{ .tag = "wght".*, .value = 650.0 }});
    defer std.testing.allocator.free(normalized);

    try std.testing.expectApproxEqAbs(@as(f64, 0.25), normalized[0], 0.0001);
}

test "fvar named instance coordinates normalize by instance index" {
    var fvar = [_]u8{0} ** 64;
    writeU16(&fvar, Fvar.major_version_offset, Fvar.expected_major_version);
    writeU16(&fvar, Fvar.minor_version_offset, Fvar.expected_minor_version);
    writeU16(&fvar, Fvar.axes_array_offset_offset, 16);
    writeU16(&fvar, Fvar.axis_count_offset, 1);
    writeU16(&fvar, Fvar.axis_size_offset, Fvar.axis_record_min_size);
    writeU16(&fvar, Fvar.instance_count_offset, 2);
    writeU16(&fvar, Fvar.instance_size_offset, 8);
    @memcpy(fvar[16..20], "wght");
    writeI32(&fvar, 20, 100 << 16);
    writeI32(&fvar, 24, 400 << 16);
    writeI32(&fvar, 28, 900 << 16);
    writeU16(&fvar, 36, 256);
    writeU16(&fvar, 38, 0);
    writeI32(&fvar, 40, 400 << 16);
    writeU16(&fvar, 44, 257);
    writeU16(&fvar, 46, 0);
    writeI32(&fvar, 48, 900 << 16);

    const normalized = try normalizeInstanceCoords(std.testing.allocator, &fvar, null, 1);
    defer std.testing.allocator.free(normalized);

    try std.testing.expectEqual(@as(u16, 2), try instanceCount(&fvar));
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), normalized[0], 0.0001);
    try std.testing.expectError(ParserError.InvalidVariationInstanceIndex, normalizeInstanceCoords(std.testing.allocator, &fvar, null, 2));
}
