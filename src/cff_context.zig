const std = @import("std");
const font_parser = @import("font_parser.zig");
const binary_reader = @import("binary_reader.zig");
const cff_index = @import("cff_index.zig");
const types = @import("cff_types.zig");

const Cff = types.Cff;
const Cff2 = types.Cff2;
pub const CffContext = types.CffContext;
pub const CffIndex = types.CffIndex;
const TopDictInfo = types.TopDictInfo;
const CffError = types.CffError;
const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;
const readU32 = binary_reader.readU32;
const readCffIndex = cff_index.readCffIndex;
const readCff2Index = cff_index.readCff2Index;
const getCffIndexObject = cff_index.getCffIndexObject;
const isCffDictOperator = cff_index.isCffDictOperator;
const readCffDictOperand = cff_index.readCffDictOperand;

const first_top_dict_index = 0;
const stack_empty = 0;
const top_dict_single_operand_count = 1;
const top_dict_private_operand_count = 2;
const fd_select_format_offset = 0;
const fd_select_format0_header_size = 1;
const fd_select_format3_header_size = 3;
const fd_select_format3_min_size = 5;
const fd_select_format3_range_count_offset = 1;
const fd_select_format3_range_size = 3;
const fd_select_format3_fd_index_offset = 2;
const fd_select_format3_next_range_offset = 3;
const fd_select_format3_sentinel_size = 2;
const variation_store_min_size = 8;
const variation_store_region_list_offset = 2;
const variation_store_item_data_count_offset = 6;
const variation_store_item_data_offset_size = 4;
const variation_region_list_axis_count_offset = 0;
const variation_region_list_region_count_offset = 2;
const variation_region_list_header_size = 4;
const variation_region_axis_region_size = 6;
const variation_region_start_offset = 0;
const variation_region_peak_offset = 2;
const variation_region_end_offset = 4;
const f2dot14_denominator = 16384.0;
const default_region_scalar = 1.0;
const zero_region_scalar = 0.0;

pub fn parseCffContext(cff: []const u8) CffError!CffContext {
    if (cff.len < Cff.header_min_size) return font_parser.ParserError.InvalidTable;
    const header_size = cff[Cff.header_size_offset];
    if (header_size > cff.len) return font_parser.ParserError.InvalidTable;

    var offset: usize = header_size;
    const name_index = try readCffIndex(cff[offset..]);
    offset += name_index.end_offset;
    const top_dict_index = try readCffIndex(cff[offset..]);
    offset += top_dict_index.end_offset;
    const string_index = try readCffIndex(cff[offset..]);
    offset += string_index.end_offset;
    const global_subr_index = try readCffIndex(cff[offset..]);

    const top_dict = try getCffIndexObject(top_dict_index, first_top_dict_index);
    const top_dict_info = try readCffTopDictInfo(top_dict);
    const charstrings_offset = top_dict_info.charstrings_offset orelse return font_parser.ParserError.MissingMandatoryTable;
    if (charstrings_offset >= cff.len) return font_parser.ParserError.InvalidTable;
    const charstrings = try readCffIndex(cff[charstrings_offset..]);

    var local_subrs: ?CffIndex = null;
    if (top_dict_info.private_size) |private_size| {
        const private_offset = top_dict_info.private_offset orelse return font_parser.ParserError.InvalidTable;
        if (private_offset + private_size > cff.len) return font_parser.ParserError.InvalidTable;
        const private_dict = cff[private_offset .. private_offset + private_size];
        if (try readCffPrivateSubrsOffset(private_dict)) |subrs_offset| {
            const absolute_subrs_offset = private_offset + subrs_offset;
            if (absolute_subrs_offset >= cff.len) return font_parser.ParserError.InvalidTable;
            local_subrs = try readCffIndex(cff[absolute_subrs_offset..]);
        }
    }

    return .{
        .cff = cff,
        .charstrings = charstrings,
        .global_subrs = global_subr_index,
        .local_subrs = local_subrs,
        .fd_array_offset = top_dict_info.fd_array_offset,
        .fd_select_offset = top_dict_info.fd_select_offset,
    };
}

pub fn parseCff2Context(cff2: []const u8) CffError!CffContext {
    if (cff2.len < Cff2.header_min_size) return font_parser.ParserError.InvalidTable;
    const header_size = cff2[Cff2.header_size_offset];
    if (header_size < Cff2.top_dict_data_offset or header_size > cff2.len) return font_parser.ParserError.InvalidTable;
    const top_dict_length = try readU16(cff2, Cff2.top_dict_length_offset);
    const top_dict_end = header_size + @as(usize, top_dict_length);
    if (top_dict_end > cff2.len) return font_parser.ParserError.InvalidTable;

    const top_dict_info = try readCff2TopDictInfo(cff2[header_size..top_dict_end]);
    const global_subr_index = try readCff2Index(cff2[top_dict_end..]);
    const charstrings_offset = top_dict_info.charstrings_offset orelse return font_parser.ParserError.MissingMandatoryTable;
    if (charstrings_offset >= cff2.len) return font_parser.ParserError.InvalidTable;
    const charstrings = try readCff2Index(cff2[charstrings_offset..]);
    const cff2_blend_region_count = if (top_dict_info.variation_store_offset) |variation_store_offset| blk: {
        if (variation_store_offset >= cff2.len) return font_parser.ParserError.InvalidTable;
        break :blk try readCff2VariationRegionCount(cff2[variation_store_offset..]);
    } else null;

    return .{
        .cff = cff2,
        .charstrings = charstrings,
        .global_subrs = global_subr_index,
        .local_subrs = null,
        .fd_array_offset = top_dict_info.fd_array_offset,
        .fd_select_offset = top_dict_info.fd_select_offset,
        .cff2_variation_store_offset = top_dict_info.variation_store_offset,
        .cff2_blend_region_count = cff2_blend_region_count,
        .is_cff2 = true,
    };
}

pub fn readCffTopDictInfo(dict: []const u8) CffError!TopDictInfo {
    var result = TopDictInfo{};
    var stack: [Cff.operand_stack_max]i32 = undefined;
    var stack_len: usize = 0;
    var offset: usize = 0;
    while (offset < dict.len) {
        const byte = dict[offset];
        if (isCffDictOperator(byte)) {
            offset += 1;
            if (byte == Cff.dict_escape_operator) {
                if (offset >= dict.len) return font_parser.ParserError.InvalidTable;
                const escaped_operator = dict[offset];
                offset += 1;
                if (escaped_operator == Cff.top_dict_fd_array_escaped_operator) {
                    if (stack_len < top_dict_single_operand_count) return font_parser.ParserError.InvalidTable;
                    const value = stack[stack_len - top_dict_single_operand_count];
                    if (value < 0) return font_parser.ParserError.InvalidTable;
                    result.fd_array_offset = @intCast(value);
                } else if (escaped_operator == Cff.top_dict_fd_select_escaped_operator) {
                    if (stack_len < top_dict_single_operand_count) return font_parser.ParserError.InvalidTable;
                    const value = stack[stack_len - top_dict_single_operand_count];
                    if (value < 0) return font_parser.ParserError.InvalidTable;
                    result.fd_select_offset = @intCast(value);
                }
                stack_len = stack_empty;
                continue;
            }
            if (byte == Cff.top_dict_charstrings_operator) {
                if (stack_len < top_dict_single_operand_count) return font_parser.ParserError.InvalidTable;
                const value = stack[stack_len - top_dict_single_operand_count];
                if (value < 0) return font_parser.ParserError.InvalidTable;
                result.charstrings_offset = @intCast(value);
            } else if (byte == Cff.top_dict_private_operator) {
                if (stack_len < top_dict_private_operand_count) return font_parser.ParserError.InvalidTable;
                const private_size = stack[stack_len - top_dict_private_operand_count];
                const private_offset = stack[stack_len - top_dict_single_operand_count];
                if (private_size < 0 or private_offset < 0) return font_parser.ParserError.InvalidTable;
                result.private_size = @intCast(private_size);
                result.private_offset = @intCast(private_offset);
            }
            stack_len = stack_empty;
            continue;
        }

        const operand = try readCffDictOperand(dict, &offset);
        if (stack_len >= stack.len) return font_parser.ParserError.InvalidTable;
        stack[stack_len] = operand;
        stack_len += 1;
    }
    return result;
}

pub fn readCff2TopDictInfo(dict: []const u8) CffError!TopDictInfo {
    var result = TopDictInfo{};
    var stack: [Cff.operand_stack_max]i32 = undefined;
    var stack_len: usize = 0;
    var offset: usize = 0;
    while (offset < dict.len) {
        const byte = dict[offset];
        if (isCffDictOperator(byte) or byte == Cff2.top_dict_variation_store_operator) {
            offset += 1;
            if (byte == Cff.dict_escape_operator) {
                if (offset >= dict.len) return font_parser.ParserError.InvalidTable;
                const escaped_operator = dict[offset];
                offset += 1;
                if (escaped_operator == Cff.top_dict_fd_array_escaped_operator) {
                    if (stack_len < top_dict_single_operand_count) return font_parser.ParserError.InvalidTable;
                    const value = stack[stack_len - top_dict_single_operand_count];
                    if (value < 0) return font_parser.ParserError.InvalidTable;
                    result.fd_array_offset = @intCast(value);
                } else if (escaped_operator == Cff.top_dict_fd_select_escaped_operator) {
                    if (stack_len < top_dict_single_operand_count) return font_parser.ParserError.InvalidTable;
                    const value = stack[stack_len - top_dict_single_operand_count];
                    if (value < 0) return font_parser.ParserError.InvalidTable;
                    result.fd_select_offset = @intCast(value);
                }
                stack_len = stack_empty;
                continue;
            }
            if (byte == Cff.top_dict_charstrings_operator) {
                if (stack_len < top_dict_single_operand_count) return font_parser.ParserError.InvalidTable;
                const value = stack[stack_len - top_dict_single_operand_count];
                if (value < 0) return font_parser.ParserError.InvalidTable;
                result.charstrings_offset = @intCast(value);
            } else if (byte == Cff2.top_dict_variation_store_operator) {
                if (stack_len < top_dict_single_operand_count) return font_parser.ParserError.InvalidTable;
                const value = stack[stack_len - top_dict_single_operand_count];
                if (value < 0) return font_parser.ParserError.InvalidTable;
                result.variation_store_offset = @intCast(value);
            }
            stack_len = stack_empty;
            continue;
        }

        const operand = try readCffDictOperand(dict, &offset);
        if (stack_len >= stack.len) return font_parser.ParserError.InvalidTable;
        stack[stack_len] = operand;
        stack_len += 1;
    }
    return result;
}

pub fn readCff2VariationRegionCount(data: []const u8) CffError!u16 {
    if (data.len < variation_store_min_size) return font_parser.ParserError.InvalidTable;
    const region_list_offset = try readU32(data, variation_store_region_list_offset);
    const item_data_count = try readU16(data, variation_store_item_data_count_offset);
    const item_data_offsets_end = variation_store_min_size + @as(usize, item_data_count) * variation_store_item_data_offset_size;
    if (item_data_offsets_end > data.len or region_list_offset > data.len) return font_parser.ParserError.InvalidTable;

    const region_list = data[region_list_offset..];
    if (region_list.len < variation_region_list_header_size) return font_parser.ParserError.InvalidTable;
    const axis_count = try readU16(region_list, variation_region_list_axis_count_offset);
    const region_count = try readU16(region_list, variation_region_list_region_count_offset);
    const region_data_len = @as(usize, axis_count) * @as(usize, region_count) * variation_region_axis_region_size;
    if (variation_region_list_header_size + region_data_len > region_list.len) return font_parser.ParserError.InvalidTable;
    return region_count;
}

pub fn readCff2VariationRegionWeights(allocator: std.mem.Allocator, data: []const u8, normalized_coords: []const f64) CffError![]f64 {
    if (data.len < variation_store_min_size) return font_parser.ParserError.InvalidTable;
    const region_list_offset = try readU32(data, variation_store_region_list_offset);
    const item_data_count = try readU16(data, variation_store_item_data_count_offset);
    const item_data_offsets_end = variation_store_min_size + @as(usize, item_data_count) * variation_store_item_data_offset_size;
    if (item_data_offsets_end > data.len or region_list_offset > data.len) return font_parser.ParserError.InvalidTable;

    const region_list = data[region_list_offset..];
    if (region_list.len < variation_region_list_header_size) return font_parser.ParserError.InvalidTable;
    const axis_count = try readU16(region_list, variation_region_list_axis_count_offset);
    const region_count = try readU16(region_list, variation_region_list_region_count_offset);
    if (normalized_coords.len < axis_count) return font_parser.ParserError.InvalidTable;
    const region_data_len = @as(usize, axis_count) * @as(usize, region_count) * variation_region_axis_region_size;
    if (variation_region_list_header_size + region_data_len > region_list.len) return font_parser.ParserError.InvalidTable;

    const weights = try allocator.alloc(f64, region_count);
    errdefer allocator.free(weights);
    var region_index: usize = 0;
    while (region_index < region_count) : (region_index += 1) {
        var weight: f64 = default_region_scalar;
        var axis_index: usize = 0;
        while (axis_index < axis_count) : (axis_index += 1) {
            const axis_offset = variation_region_list_header_size +
                (region_index * @as(usize, axis_count) + axis_index) * variation_region_axis_region_size;
            const start = try readF2Dot14(region_list, axis_offset + variation_region_start_offset);
            const peak = try readF2Dot14(region_list, axis_offset + variation_region_peak_offset);
            const end = try readF2Dot14(region_list, axis_offset + variation_region_end_offset);
            weight *= variationAxisScalar(normalized_coords[axis_index], start, peak, end);
        }
        weights[region_index] = weight;
    }
    return weights;
}

fn readF2Dot14(data: []const u8, offset: usize) CffError!f64 {
    return @as(f64, @floatFromInt(try readI16(data, offset))) / f2dot14_denominator;
}

fn variationAxisScalar(coord: f64, start: f64, peak: f64, end: f64) f64 {
    if (!std.math.isFinite(coord)) return zero_region_scalar;
    if (peak == zero_region_scalar and start == zero_region_scalar and end == zero_region_scalar) return default_region_scalar;
    if (coord == peak) return default_region_scalar;
    if (coord <= start or coord >= end) return zero_region_scalar;
    if (coord < peak) {
        if (peak == start) return zero_region_scalar;
        return (coord - start) / (peak - start);
    }
    if (end == peak) return zero_region_scalar;
    return (end - coord) / (end - peak);
}

pub fn readCffPrivateSubrsOffset(dict: []const u8) CffError!?usize {
    var stack: [Cff.operand_stack_max]i32 = undefined;
    var stack_len: usize = 0;
    var offset: usize = 0;
    while (offset < dict.len) {
        const byte = dict[offset];
        if (isCffDictOperator(byte)) {
            offset += 1;
            if (byte == Cff.dict_escape_operator) {
                if (offset >= dict.len) return font_parser.ParserError.InvalidTable;
                offset += 1;
                stack_len = stack_empty;
                continue;
            }
            if (byte == Cff.private_subrs_operator) {
                if (stack_len < top_dict_single_operand_count) return font_parser.ParserError.InvalidTable;
                const value = stack[stack_len - top_dict_single_operand_count];
                if (value < 0) return font_parser.ParserError.InvalidTable;
                return @intCast(value);
            }
            stack_len = stack_empty;
            continue;
        }

        const operand = try readCffDictOperand(dict, &offset);
        if (stack_len >= stack.len) return font_parser.ParserError.InvalidTable;
        stack[stack_len] = operand;
        stack_len += 1;
    }
    return null;
}

pub fn getCffGlyphLocalSubrs(context: CffContext, glyph_id: u16) CffError!?CffIndex {
    if (context.fd_array_offset == null and context.fd_select_offset == null) return context.local_subrs;
    const fd_array_offset = context.fd_array_offset orelse return context.local_subrs;
    const fd_select_offset = context.fd_select_offset orelse return context.local_subrs;
    if (fd_array_offset >= context.cff.len or fd_select_offset >= context.cff.len) return font_parser.ParserError.InvalidTable;

    const fd_index = try readCffFdSelect(context.cff[fd_select_offset..], glyph_id, context.charstrings.count);
    const fd_array = if (context.is_cff2)
        try readCff2Index(context.cff[fd_array_offset..])
    else
        try readCffIndex(context.cff[fd_array_offset..]);
    const font_dict = try getCffIndexObject(fd_array, fd_index);
    const font_dict_info = if (context.is_cff2) try readCff2FontDictInfo(font_dict) else try readCffTopDictInfo(font_dict);
    const private_size = font_dict_info.private_size orelse return null;
    const private_offset = font_dict_info.private_offset orelse return font_parser.ParserError.InvalidTable;
    if (private_offset + private_size > context.cff.len) return font_parser.ParserError.InvalidTable;

    const private_dict = context.cff[private_offset .. private_offset + private_size];
    const subrs_offset = (try readCffPrivateSubrsOffset(private_dict)) orelse return null;
    const absolute_subrs_offset = private_offset + subrs_offset;
    if (absolute_subrs_offset >= context.cff.len) return font_parser.ParserError.InvalidTable;
    return if (context.is_cff2)
        try readCff2Index(context.cff[absolute_subrs_offset..])
    else
        try readCffIndex(context.cff[absolute_subrs_offset..]);
}

pub fn readCff2FontDictInfo(dict: []const u8) CffError!TopDictInfo {
    var result = TopDictInfo{};
    var stack: [Cff.operand_stack_max]i32 = undefined;
    var stack_len: usize = 0;
    var offset: usize = 0;
    while (offset < dict.len) {
        const byte = dict[offset];
        if (isCffDictOperator(byte)) {
            offset += 1;
            if (byte == Cff.dict_escape_operator) {
                if (offset >= dict.len) return font_parser.ParserError.InvalidTable;
                offset += 1;
                stack_len = stack_empty;
                continue;
            }
            if (byte == Cff.top_dict_private_operator) {
                if (stack_len < top_dict_private_operand_count) return font_parser.ParserError.InvalidTable;
                const private_size = stack[stack_len - top_dict_private_operand_count];
                const private_offset = stack[stack_len - top_dict_single_operand_count];
                if (private_size < 0 or private_offset < 0) return font_parser.ParserError.InvalidTable;
                result.private_size = @intCast(private_size);
                result.private_offset = @intCast(private_offset);
            }
            stack_len = stack_empty;
            continue;
        }

        const operand = try readCffDictOperand(dict, &offset);
        if (stack_len >= stack.len) return font_parser.ParserError.InvalidTable;
        stack[stack_len] = operand;
        stack_len += 1;
    }
    return result;
}

pub fn readCffFdSelect(data: []const u8, glyph_id: u16, glyph_count: u32) CffError!u16 {
    if (glyph_id >= glyph_count or data.len == stack_empty) return font_parser.ParserError.InvalidTable;
    return switch (data[fd_select_format_offset]) {
        Cff.fd_select_format_0 => readCffFdSelectFormat0(data, glyph_id, glyph_count),
        Cff.fd_select_format_3 => readCffFdSelectFormat3(data, glyph_id),
        else => font_parser.ParserError.InvalidTable,
    };
}

pub fn readCffFdSelectFormat0(data: []const u8, glyph_id: u16, glyph_count: u32) CffError!u16 {
    if (data.len < fd_select_format0_header_size + @as(usize, glyph_count)) return font_parser.ParserError.InvalidTable;
    return data[fd_select_format0_header_size + @as(usize, glyph_id)];
}

pub fn readCffFdSelectFormat3(data: []const u8, glyph_id: u16) CffError!u16 {
    if (data.len < fd_select_format3_min_size) return font_parser.ParserError.InvalidTable;
    const range_count = try readU16(data, fd_select_format3_range_count_offset);
    const sentinel_offset = fd_select_format3_header_size + @as(usize, range_count) * fd_select_format3_range_size;
    if (sentinel_offset + fd_select_format3_sentinel_size > data.len) return font_parser.ParserError.InvalidTable;

    var offset: usize = fd_select_format3_header_size;
    var range_index: usize = 0;
    while (range_index < range_count) : (range_index += 1) {
        const first = try readU16(data, offset);
        const fd_index = data[offset + fd_select_format3_fd_index_offset];
        const next = if (range_index + 1 == range_count)
            try readU16(data, sentinel_offset)
        else
            try readU16(data, offset + fd_select_format3_next_range_offset);
        if (first > next) return font_parser.ParserError.InvalidTable;
        if (glyph_id >= first and glyph_id < next) return fd_index;
        offset += fd_select_format3_range_size;
    }

    return font_parser.ParserError.InvalidTable;
}
