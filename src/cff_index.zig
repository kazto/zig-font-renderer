const font_parser = @import("font_parser.zig");
const binary_reader = @import("binary_reader.zig");
const types = @import("cff_types.zig");

const Cff = types.Cff;
pub const CffIndex = types.CffIndex;
const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;
const readI32 = binary_reader.readI32;

const cff_index_count_offset = 0;
const cff_dict_one_byte_integer_min = 32;
const cff_dict_one_byte_integer_max = 246;
const cff_dict_positive_two_byte_min = 247;
const cff_dict_positive_two_byte_max = 250;
const cff_dict_negative_two_byte_min = 251;
const cff_dict_negative_two_byte_max = 254;
const cff_dict_short_integer_operator = 28;
const cff_dict_long_integer_operator = 29;
const cff_dict_real_number_operator = 30;
const cff_dict_one_byte_integer_bias = 139;
const cff_dict_two_byte_integer_bias = 108;
const cff_dict_two_byte_multiplier = 256;
const cff_real_nibble_terminator = 0x0f;
const cff_real_nibble_shift = 4;
const cff_short_integer_size = 2;
const cff_long_integer_size = 4;
const cff_real_number_placeholder = 0;

pub fn readCffIndex(data: []const u8) font_parser.ParserError!CffIndex {
    if (data.len < Cff.index_count_size) return font_parser.ParserError.InvalidTable;
    const count = try readU16(data, cff_index_count_offset);
    if (count == Cff.index_empty_count) {
        return .{
            .data = data,
            .count = Cff.index_empty_count,
            .off_size = Cff.index_empty_off_size,
            .offsets_offset = Cff.index_count_size,
            .object_data_offset = Cff.index_count_size,
            .end_offset = Cff.index_count_size,
        };
    }

    if (data.len < Cff.index_count_size + Cff.index_off_size_size) return font_parser.ParserError.InvalidTable;
    const off_size = data[Cff.index_off_size_offset];
    if (off_size == Cff.index_empty_off_size or off_size > Cff.max_offset_size) return font_parser.ParserError.InvalidTable;
    const offsets_offset = Cff.index_count_size + Cff.index_off_size_size;
    const object_data_offset = offsets_offset + (@as(usize, count) + Cff.index_first_object_offset) * @as(usize, off_size);
    if (object_data_offset > data.len) return font_parser.ParserError.InvalidTable;

    const last_offset = try readCffOffset(data, offsets_offset + @as(usize, count) * @as(usize, off_size), off_size);
    if (last_offset == Cff.zero_offset) return font_parser.ParserError.InvalidTable;
    const end_offset = object_data_offset + @as(usize, last_offset) - Cff.index_first_object_offset;
    if (end_offset > data.len) return font_parser.ParserError.InvalidTable;

    return .{
        .data = data,
        .count = count,
        .off_size = off_size,
        .offsets_offset = offsets_offset,
        .object_data_offset = object_data_offset,
        .end_offset = end_offset,
    };
}

pub fn getCffIndexObject(index: CffIndex, object_index: u16) font_parser.ParserError![]const u8 {
    if (object_index >= index.count) return font_parser.ParserError.InvalidGlyphId;
    const offset_size = @as(usize, index.off_size);
    const start_offset = try readCffOffset(index.data, index.offsets_offset + @as(usize, object_index) * offset_size, index.off_size);
    const end_offset = try readCffOffset(index.data, index.offsets_offset + (@as(usize, object_index) + Cff.index_first_object_offset) * offset_size, index.off_size);
    if (start_offset == Cff.zero_offset or end_offset < start_offset) return font_parser.ParserError.InvalidTable;
    const start = index.object_data_offset + @as(usize, start_offset) - Cff.index_first_object_offset;
    const end = index.object_data_offset + @as(usize, end_offset) - Cff.index_first_object_offset;
    if (end > index.data.len or start > end) return font_parser.ParserError.InvalidTable;
    return index.data[start..end];
}

pub fn readCffOffset(data: []const u8, offset: usize, off_size: u8) font_parser.ParserError!u32 {
    if (off_size == Cff.index_empty_off_size or off_size > Cff.max_offset_size or offset + off_size > data.len) return font_parser.ParserError.InvalidTable;
    var value: u32 = 0;
    for (data[offset .. offset + off_size]) |byte| {
        value = (value << Cff.offset_accumulator_shift_bits) | byte;
    }
    return value;
}

pub fn isCffDictOperator(byte: u8) bool {
    return byte <= Cff.dict_operator_max;
}

pub fn readCffDictOperand(data: []const u8, offset: *usize) font_parser.ParserError!i32 {
    if (offset.* >= data.len) return font_parser.ParserError.InvalidTable;
    const byte = data[offset.*];
    offset.* += 1;
    return switch (byte) {
        cff_dict_one_byte_integer_min...cff_dict_one_byte_integer_max => @as(i32, byte) - cff_dict_one_byte_integer_bias,
        cff_dict_positive_two_byte_min...cff_dict_positive_two_byte_max => blk: {
            if (offset.* >= data.len) return font_parser.ParserError.InvalidTable;
            const b1 = data[offset.*];
            offset.* += 1;
            break :blk (@as(i32, byte) - cff_dict_positive_two_byte_min) * cff_dict_two_byte_multiplier + @as(i32, b1) + cff_dict_two_byte_integer_bias;
        },
        cff_dict_negative_two_byte_min...cff_dict_negative_two_byte_max => blk: {
            if (offset.* >= data.len) return font_parser.ParserError.InvalidTable;
            const b1 = data[offset.*];
            offset.* += 1;
            break :blk -((@as(i32, byte) - cff_dict_negative_two_byte_min) * cff_dict_two_byte_multiplier) - @as(i32, b1) - cff_dict_two_byte_integer_bias;
        },
        cff_dict_short_integer_operator => blk: {
            const value = try readI16(data, offset.*);
            offset.* += cff_short_integer_size;
            break :blk value;
        },
        cff_dict_long_integer_operator => blk: {
            const value = try readI32(data, offset.*);
            offset.* += cff_long_integer_size;
            break :blk value;
        },
        cff_dict_real_number_operator => blk: {
            try skipCffReal(data, offset);
            break :blk cff_real_number_placeholder;
        },
        else => font_parser.ParserError.InvalidTable,
    };
}

pub fn skipCffReal(data: []const u8, offset: *usize) font_parser.ParserError!void {
    while (offset.* < data.len) {
        const byte = data[offset.*];
        offset.* += 1;
        if ((byte & cff_real_nibble_terminator) == cff_real_nibble_terminator or (byte >> cff_real_nibble_shift) == cff_real_nibble_terminator) return;
    }
    return font_parser.ParserError.InvalidTable;
}

pub fn isType2Number(byte: u8) bool {
    return byte == cff_dict_short_integer_operator or byte >= cff_dict_one_byte_integer_min;
}

pub fn readType2Number(data: []const u8, offset: *usize) font_parser.ParserError!i32 {
    return readCffDictOperand(data, offset);
}
