const std = @import("std");

pub const ReadError = error{
    InvalidTable,
};

pub fn readU16(data: []const u8, offset: usize) ReadError!u16 {
    if (offset + 2 > data.len) return ReadError.InvalidTable;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

pub fn readI16(data: []const u8, offset: usize) ReadError!i16 {
    if (offset + 2 > data.len) return ReadError.InvalidTable;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

pub fn readU32(data: []const u8, offset: usize) ReadError!u32 {
    if (offset + 4 > data.len) return ReadError.InvalidTable;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

pub fn readI32(data: []const u8, offset: usize) ReadError!i32 {
    if (offset + 4 > data.len) return ReadError.InvalidTable;
    return std.mem.readInt(i32, data[offset..][0..4], .big);
}

pub fn tagToU32(tag: [4]u8) u32 {
    return std.mem.readInt(u32, &tag, .big);
}

test "big-endian integer readers decode signed and unsigned values" {
    const data = [_]u8{ 0x12, 0x34, 0xff, 0xfe, 0x80, 0x00 };

    try std.testing.expectEqual(@as(u16, 0x1234), try readU16(&data, 0));
    try std.testing.expectEqual(@as(i16, -2), try readI16(&data, 2));
    try std.testing.expectEqual(@as(u32, 0x1234fffe), try readU32(&data, 0));
    try std.testing.expectEqual(@as(i32, -98304), try readI32(&data, 2));
}

test "integer readers reject out-of-range offsets" {
    const data = [_]u8{ 0x12, 0x34, 0x56 };

    try std.testing.expectError(ReadError.InvalidTable, readU16(&data, 2));
    try std.testing.expectError(ReadError.InvalidTable, readI16(&data, 2));
    try std.testing.expectError(ReadError.InvalidTable, readU32(&data, 0));
    try std.testing.expectError(ReadError.InvalidTable, readI32(&data, 0));
}
