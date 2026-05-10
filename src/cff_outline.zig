const std = @import("std");
const font_parser = @import("font_parser.zig");

pub const CffError = font_parser.ParserError || std.mem.Allocator.Error || error{
    UnsupportedCffOperator,
};

const Cff = struct {
    const header_min_size = 4;
    const header_size_offset = 2;
    const index_count_size = 2;
    const index_off_size_offset = 2;
    const top_dict_charstrings_operator = 17;
    const top_dict_private_operator = 18;
    const private_subrs_operator = 19;
    const operand_stack_max = 48;
    const max_subr_depth = 16;
};

const Type2 = struct {
    const hstem = 1;
    const vstem = 3;
    const vmoveto = 4;
    const rlineto = 5;
    const hlineto = 6;
    const vlineto = 7;
    const rrcurveto = 8;
    const callsubr = 10;
    const return_op = 11;
    const escape = 12;
    const endchar = 14;
    const hstemhm = 18;
    const hintmask = 19;
    const cntrmask = 20;
    const rmoveto = 21;
    const hmoveto = 22;
    const vstemhm = 23;
    const rcurveline = 24;
    const rlinecurve = 25;
    const vvcurveto = 26;
    const hhcurveto = 27;
    const callgsubr = 29;
    const vhcurveto = 30;
    const hvcurveto = 31;
};

pub const Transform = struct {
    xx: f64 = 1.0,
    yx: f64 = 0.0,
    xy: f64 = 0.0,
    yy: f64 = 1.0,
    dx: f64 = 0.0,
    dy: f64 = 0.0,

    fn apply(self: Transform, x: i32, y: i32) TransformedPoint {
        const fx: f64 = @floatFromInt(x);
        const fy: f64 = @floatFromInt(y);
        return .{
            .x = self.xx * fx + self.xy * fy + self.dx,
            .y = self.yx * fx + self.yy * fy + self.dy,
        };
    }
};

const TransformedPoint = struct {
    x: f64,
    y: f64,
};

const CffIndex = struct {
    data: []const u8,
    count: u16,
    off_size: u8,
    offsets_offset: usize,
    object_data_offset: usize,
    end_offset: usize,
};

const CffContext = struct {
    cff: []const u8,
    charstrings: CffIndex,
    global_subrs: CffIndex,
    local_subrs: ?CffIndex,
};

const TopDictInfo = struct {
    charstrings_offset: ?usize = null,
    private_size: ?usize = null,
    private_offset: ?usize = null,
};

const Type2State = struct {
    stack: [Cff.operand_stack_max]i32 = undefined,
    stack_len: usize = 0,
    x: i32 = 0,
    y: i32 = 0,
    hint_count: usize = 0,
    has_current_point: bool = false,
};

pub fn appendGlyphPath(writer: std.ArrayList(u8).Writer, cff: []const u8, glyph_id: u16, transform: Transform) CffError!void {
    const context = try parseCffContext(cff);
    const charstring = try getCffCharString(context, glyph_id);
    if (charstring.len == 0) return;

    try writer.print("    <path d=\"", .{});
    try appendType2CharStringPath(writer, charstring, transform, context);
    try writer.print("\"/>\n", .{});
}

fn getCffCharString(context: CffContext, glyph_id: u16) CffError![]const u8 {
    return getCffIndexObject(context.charstrings, glyph_id);
}

fn parseCffContext(cff: []const u8) CffError!CffContext {
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

    const top_dict = try getCffIndexObject(top_dict_index, 0);
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
    };
}

fn readCffTopDictInfo(dict: []const u8) CffError!TopDictInfo {
    var result = TopDictInfo{};
    var stack: [Cff.operand_stack_max]i32 = undefined;
    var stack_len: usize = 0;
    var offset: usize = 0;
    while (offset < dict.len) {
        const byte = dict[offset];
        if (isCffDictOperator(byte)) {
            offset += 1;
            if (byte == 12) {
                if (offset >= dict.len) return font_parser.ParserError.InvalidTable;
                offset += 1;
                stack_len = 0;
                continue;
            }
            if (byte == Cff.top_dict_charstrings_operator) {
                if (stack_len == 0) return font_parser.ParserError.InvalidTable;
                const value = stack[stack_len - 1];
                if (value < 0) return font_parser.ParserError.InvalidTable;
                result.charstrings_offset = @intCast(value);
            } else if (byte == Cff.top_dict_private_operator) {
                if (stack_len < 2) return font_parser.ParserError.InvalidTable;
                const private_size = stack[stack_len - 2];
                const private_offset = stack[stack_len - 1];
                if (private_size < 0 or private_offset < 0) return font_parser.ParserError.InvalidTable;
                result.private_size = @intCast(private_size);
                result.private_offset = @intCast(private_offset);
            }
            stack_len = 0;
            continue;
        }

        const operand = try readCffDictOperand(dict, &offset);
        if (stack_len >= stack.len) return font_parser.ParserError.InvalidTable;
        stack[stack_len] = operand;
        stack_len += 1;
    }
    return result;
}

fn readCffPrivateSubrsOffset(dict: []const u8) CffError!?usize {
    var stack: [Cff.operand_stack_max]i32 = undefined;
    var stack_len: usize = 0;
    var offset: usize = 0;
    while (offset < dict.len) {
        const byte = dict[offset];
        if (isCffDictOperator(byte)) {
            offset += 1;
            if (byte == 12) {
                if (offset >= dict.len) return font_parser.ParserError.InvalidTable;
                offset += 1;
                stack_len = 0;
                continue;
            }
            if (byte == Cff.private_subrs_operator) {
                if (stack_len == 0) return font_parser.ParserError.InvalidTable;
                const value = stack[stack_len - 1];
                if (value < 0) return font_parser.ParserError.InvalidTable;
                return @intCast(value);
            }
            stack_len = 0;
            continue;
        }

        const operand = try readCffDictOperand(dict, &offset);
        if (stack_len >= stack.len) return font_parser.ParserError.InvalidTable;
        stack[stack_len] = operand;
        stack_len += 1;
    }
    return null;
}

fn appendType2CharStringPath(writer: std.ArrayList(u8).Writer, charstring: []const u8, transform: Transform, context: CffContext) CffError!void {
    var state = Type2State{};
    try executeType2CharString(writer, charstring, transform, context, &state, 0);
}

fn executeType2CharString(writer: std.ArrayList(u8).Writer, charstring: []const u8, transform: Transform, context: CffContext, state: *Type2State, depth: u8) CffError!void {
    if (depth > Cff.max_subr_depth) return CffError.UnsupportedCffOperator;
    var offset: usize = 0;

    while (offset < charstring.len) {
        const byte = charstring[offset];
        if (isType2Number(byte)) {
            const number = try readType2Number(charstring, &offset);
            if (state.stack_len >= state.stack.len) return font_parser.ParserError.InvalidTable;
            state.stack[state.stack_len] = number;
            state.stack_len += 1;
            continue;
        }

        offset += 1;
        switch (byte) {
            Type2.hstem, Type2.vstem, Type2.hstemhm, Type2.vstemhm => {
                const width_operands: usize = if ((state.stack_len % 2) == 1) 1 else 0;
                state.hint_count += (state.stack_len - width_operands) / 2;
                state.stack_len = 0;
            },
            Type2.hintmask, Type2.cntrmask => {
                const width_operands: usize = if ((state.stack_len % 2) == 1) 1 else 0;
                state.hint_count += (state.stack_len - width_operands) / 2;
                state.stack_len = 0;
                const mask_len = (state.hint_count + 7) / 8;
                if (offset + mask_len > charstring.len) return font_parser.ParserError.InvalidTable;
                offset += mask_len;
            },
            Type2.rmoveto => {
                if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
                state.x += state.stack[state.stack_len - 2];
                state.y += state.stack[state.stack_len - 1];
                const point = transform.apply(state.x, state.y);
                try writer.print("M {d:.2} {d:.2} ", .{ point.x, point.y });
                state.has_current_point = true;
                state.stack_len = 0;
            },
            Type2.hmoveto => {
                if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
                state.x += state.stack[state.stack_len - 1];
                const point = transform.apply(state.x, state.y);
                try writer.print("M {d:.2} {d:.2} ", .{ point.x, point.y });
                state.has_current_point = true;
                state.stack_len = 0;
            },
            Type2.vmoveto => {
                if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
                state.y += state.stack[state.stack_len - 1];
                const point = transform.apply(state.x, state.y);
                try writer.print("M {d:.2} {d:.2} ", .{ point.x, point.y });
                state.has_current_point = true;
                state.stack_len = 0;
            },
            Type2.rlineto => {
                if (!state.has_current_point or state.stack_len < 2 or (state.stack_len % 2) != 0) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                while (index < state.stack_len) : (index += 2) {
                    state.x += state.stack[index];
                    state.y += state.stack[index + 1];
                    const point = transform.apply(state.x, state.y);
                    try writer.print("L {d:.2} {d:.2} ", .{ point.x, point.y });
                }
                state.stack_len = 0;
            },
            Type2.hlineto, Type2.vlineto => {
                if (!state.has_current_point or state.stack_len == 0) return font_parser.ParserError.InvalidTable;
                var horizontal = byte == Type2.hlineto;
                for (state.stack[0..state.stack_len]) |value| {
                    if (horizontal) state.x += value else state.y += value;
                    const point = transform.apply(state.x, state.y);
                    try writer.print("L {d:.2} {d:.2} ", .{ point.x, point.y });
                    horizontal = !horizontal;
                }
                state.stack_len = 0;
            },
            Type2.rrcurveto => {
                if (!state.has_current_point or state.stack_len < 6 or (state.stack_len % 6) != 0) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                while (index < state.stack_len) : (index += 6) {
                    try emitType2Curve(writer, transform, state, state.stack[index], state.stack[index + 1], state.stack[index + 2], state.stack[index + 3], state.stack[index + 4], state.stack[index + 5]);
                }
                state.stack_len = 0;
            },
            Type2.rcurveline => {
                if (!state.has_current_point or state.stack_len < 8 or ((state.stack_len - 2) % 6) != 0) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                while (index + 2 < state.stack_len) : (index += 6) {
                    try emitType2Curve(writer, transform, state, state.stack[index], state.stack[index + 1], state.stack[index + 2], state.stack[index + 3], state.stack[index + 4], state.stack[index + 5]);
                }
                state.x += state.stack[state.stack_len - 2];
                state.y += state.stack[state.stack_len - 1];
                const point = transform.apply(state.x, state.y);
                try writer.print("L {d:.2} {d:.2} ", .{ point.x, point.y });
                state.stack_len = 0;
            },
            Type2.rlinecurve => {
                if (!state.has_current_point or state.stack_len < 8 or ((state.stack_len - 6) % 2) != 0) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                while (index + 6 < state.stack_len) : (index += 2) {
                    state.x += state.stack[index];
                    state.y += state.stack[index + 1];
                    const point = transform.apply(state.x, state.y);
                    try writer.print("L {d:.2} {d:.2} ", .{ point.x, point.y });
                }
                try emitType2Curve(writer, transform, state, state.stack[index], state.stack[index + 1], state.stack[index + 2], state.stack[index + 3], state.stack[index + 4], state.stack[index + 5]);
                state.stack_len = 0;
            },
            Type2.hhcurveto => {
                if (!state.has_current_point or state.stack_len < 4) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                var dy1: i32 = 0;
                if ((state.stack_len % 4) == 1) {
                    dy1 = state.stack[0];
                    index = 1;
                }
                if (((state.stack_len - index) % 4) != 0) return font_parser.ParserError.InvalidTable;
                while (index < state.stack_len) : (index += 4) {
                    try emitType2Curve(writer, transform, state, state.stack[index], dy1, state.stack[index + 1], state.stack[index + 2], state.stack[index + 3], 0);
                    dy1 = 0;
                }
                state.stack_len = 0;
            },
            Type2.vvcurveto => {
                if (!state.has_current_point or state.stack_len < 4) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                var dx1: i32 = 0;
                if ((state.stack_len % 4) == 1) {
                    dx1 = state.stack[0];
                    index = 1;
                }
                if (((state.stack_len - index) % 4) != 0) return font_parser.ParserError.InvalidTable;
                while (index < state.stack_len) : (index += 4) {
                    try emitType2Curve(writer, transform, state, dx1, state.stack[index], state.stack[index + 1], state.stack[index + 2], 0, state.stack[index + 3]);
                    dx1 = 0;
                }
                state.stack_len = 0;
            },
            Type2.hvcurveto, Type2.vhcurveto => {
                if (!state.has_current_point or state.stack_len < 4) return font_parser.ParserError.InvalidTable;
                try emitType2AlternatingCurve(writer, transform, state, byte == Type2.hvcurveto);
                state.stack_len = 0;
            },
            Type2.callsubr => try executeCffSubroutine(writer, transform, context, context.local_subrs, state, depth + 1),
            Type2.callgsubr => try executeCffSubroutine(writer, transform, context, context.global_subrs, state, depth + 1),
            Type2.return_op => return,
            Type2.endchar => {
                try writer.print("Z ", .{});
                return;
            },
            Type2.escape => return CffError.UnsupportedCffOperator,
            else => return CffError.UnsupportedCffOperator,
        }
    }
}

fn emitType2Curve(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State, dx1: i32, dy1: i32, dx2: i32, dy2: i32, dx3: i32, dy3: i32) CffError!void {
    const c1x = state.x + dx1;
    const c1y = state.y + dy1;
    const c2x = c1x + dx2;
    const c2y = c1y + dy2;
    state.x = c2x + dx3;
    state.y = c2y + dy3;
    const c1 = transform.apply(c1x, c1y);
    const c2 = transform.apply(c2x, c2y);
    const end = transform.apply(state.x, state.y);
    try writer.print("C {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} ", .{ c1.x, c1.y, c2.x, c2.y, end.x, end.y });
}

fn emitType2AlternatingCurve(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State, starts_horizontal: bool) CffError!void {
    var index: usize = 0;
    var horizontal = starts_horizontal;
    while (index < state.stack_len) {
        const remaining = state.stack_len - index;
        if (remaining < 4) return font_parser.ParserError.InvalidTable;
        if (horizontal) {
            const dx1 = state.stack[index];
            const dx2 = state.stack[index + 1];
            const dy2 = state.stack[index + 2];
            const dy3 = state.stack[index + 3];
            index += 4;
            const dx3: i32 = if (state.stack_len - index == 1) state.stack[index] else 0;
            if (state.stack_len - index == 1) index += 1;
            try emitType2Curve(writer, transform, state, dx1, 0, dx2, dy2, dx3, dy3);
        } else {
            const dy1 = state.stack[index];
            const dx2 = state.stack[index + 1];
            const dy2 = state.stack[index + 2];
            const dx3 = state.stack[index + 3];
            index += 4;
            const dy3: i32 = if (state.stack_len - index == 1) state.stack[index] else 0;
            if (state.stack_len - index == 1) index += 1;
            try emitType2Curve(writer, transform, state, 0, dy1, dx2, dy2, dx3, dy3);
        }
        horizontal = !horizontal;
    }
}

fn executeCffSubroutine(writer: std.ArrayList(u8).Writer, transform: Transform, context: CffContext, maybe_subrs: ?CffIndex, state: *Type2State, depth: u8) CffError!void {
    const subrs = maybe_subrs orelse return CffError.UnsupportedCffOperator;
    if (state.stack_len == 0) return font_parser.ParserError.InvalidTable;
    const raw_index = state.stack[state.stack_len - 1];
    state.stack_len -= 1;
    const biased_index = raw_index + cffSubrBias(subrs.count);
    if (biased_index < 0 or biased_index > std.math.maxInt(u16)) return font_parser.ParserError.InvalidTable;
    const subr = try getCffIndexObject(subrs, @intCast(biased_index));
    try executeType2CharString(writer, subr, transform, context, state, depth);
}

fn cffSubrBias(count: u16) i32 {
    if (count < 1240) return 107;
    if (count < 33900) return 1131;
    return 32768;
}

fn readCffIndex(data: []const u8) font_parser.ParserError!CffIndex {
    if (data.len < Cff.index_count_size) return font_parser.ParserError.InvalidTable;
    const count = try readU16(data, 0);
    if (count == 0) {
        return .{
            .data = data,
            .count = 0,
            .off_size = 0,
            .offsets_offset = Cff.index_count_size,
            .object_data_offset = Cff.index_count_size,
            .end_offset = Cff.index_count_size,
        };
    }

    if (data.len < Cff.index_count_size + 1) return font_parser.ParserError.InvalidTable;
    const off_size = data[Cff.index_off_size_offset];
    if (off_size == 0 or off_size > 4) return font_parser.ParserError.InvalidTable;
    const offsets_offset = Cff.index_count_size + 1;
    const object_data_offset = offsets_offset + (@as(usize, count) + 1) * @as(usize, off_size);
    if (object_data_offset > data.len) return font_parser.ParserError.InvalidTable;

    const last_offset = try readCffOffset(data, offsets_offset + @as(usize, count) * @as(usize, off_size), off_size);
    if (last_offset == 0) return font_parser.ParserError.InvalidTable;
    const end_offset = object_data_offset + @as(usize, last_offset) - 1;
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

fn getCffIndexObject(index: CffIndex, object_index: u16) font_parser.ParserError![]const u8 {
    if (object_index >= index.count) return font_parser.ParserError.InvalidGlyphId;
    const offset_size = @as(usize, index.off_size);
    const start_offset = try readCffOffset(index.data, index.offsets_offset + @as(usize, object_index) * offset_size, index.off_size);
    const end_offset = try readCffOffset(index.data, index.offsets_offset + (@as(usize, object_index) + 1) * offset_size, index.off_size);
    if (start_offset == 0 or end_offset < start_offset) return font_parser.ParserError.InvalidTable;
    const start = index.object_data_offset + @as(usize, start_offset) - 1;
    const end = index.object_data_offset + @as(usize, end_offset) - 1;
    if (end > index.data.len or start > end) return font_parser.ParserError.InvalidTable;
    return index.data[start..end];
}

fn readCffOffset(data: []const u8, offset: usize, off_size: u8) font_parser.ParserError!u32 {
    if (off_size == 0 or off_size > 4 or offset + off_size > data.len) return font_parser.ParserError.InvalidTable;
    var value: u32 = 0;
    for (data[offset .. offset + off_size]) |byte| {
        value = (value << 8) | byte;
    }
    return value;
}

fn isCffDictOperator(byte: u8) bool {
    return byte <= 21;
}

fn readCffDictOperand(data: []const u8, offset: *usize) font_parser.ParserError!i32 {
    if (offset.* >= data.len) return font_parser.ParserError.InvalidTable;
    const byte = data[offset.*];
    offset.* += 1;
    return switch (byte) {
        32...246 => @as(i32, byte) - 139,
        247...250 => blk: {
            if (offset.* >= data.len) return font_parser.ParserError.InvalidTable;
            const b1 = data[offset.*];
            offset.* += 1;
            break :blk (@as(i32, byte) - 247) * 256 + @as(i32, b1) + 108;
        },
        251...254 => blk: {
            if (offset.* >= data.len) return font_parser.ParserError.InvalidTable;
            const b1 = data[offset.*];
            offset.* += 1;
            break :blk -((@as(i32, byte) - 251) * 256) - @as(i32, b1) - 108;
        },
        28 => blk: {
            const value = try readI16(data, offset.*);
            offset.* += 2;
            break :blk value;
        },
        29 => blk: {
            const value = try readI32(data, offset.*);
            offset.* += 4;
            break :blk value;
        },
        30 => blk: {
            try skipCffReal(data, offset);
            break :blk 0;
        },
        else => font_parser.ParserError.InvalidTable,
    };
}

fn skipCffReal(data: []const u8, offset: *usize) font_parser.ParserError!void {
    while (offset.* < data.len) {
        const byte = data[offset.*];
        offset.* += 1;
        if ((byte & 0x0f) == 0x0f or (byte >> 4) == 0x0f) return;
    }
    return font_parser.ParserError.InvalidTable;
}

fn isType2Number(byte: u8) bool {
    return byte == 28 or byte >= 32;
}

fn readType2Number(data: []const u8, offset: *usize) font_parser.ParserError!i32 {
    return readCffDictOperand(data, offset);
}

fn readU16(data: []const u8, offset: usize) font_parser.ParserError!u16 {
    if (offset + 2 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readI16(data: []const u8, offset: usize) font_parser.ParserError!i16 {
    if (offset + 2 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

fn readI32(data: []const u8, offset: usize) font_parser.ParserError!i32 {
    if (offset + 4 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(i32, data[offset..][0..4], .big);
}

test "CFF INDEX reads object slices" {
    const data = [_]u8{
        0,   2,   1,
        1,   3,   4,
        'A', 'B', 'C',
    };
    const index = try readCffIndex(&data);
    try std.testing.expectEqual(@as(u16, 2), index.count);
    try std.testing.expectEqualSlices(u8, "AB", try getCffIndexObject(index, 0));
    try std.testing.expectEqualSlices(u8, "C", try getCffIndexObject(index, 1));
}

test "CFF subroutine bias follows Type 2 thresholds" {
    try std.testing.expectEqual(@as(i32, 107), cffSubrBias(0));
    try std.testing.expectEqual(@as(i32, 107), cffSubrBias(1239));
    try std.testing.expectEqual(@as(i32, 1131), cffSubrBias(1240));
    try std.testing.expectEqual(@as(i32, 32768), cffSubrBias(33900));
}

test "Type2 charstring emits moveto and lines" {
    var output = std.ArrayList(u8).empty;
    defer output.deinit(std.testing.allocator);
    const writer = output.writer(std.testing.allocator);
    const empty_index = try readCffIndex(&[_]u8{ 0, 0 });
    const context = CffContext{
        .cff = &[_]u8{},
        .charstrings = empty_index,
        .global_subrs = empty_index,
        .local_subrs = null,
    };
    const charstring = [_]u8{
        139,           139,           Type2.rmoveto,
        189,           139,           139,
        189,           89,            139,
        Type2.rlineto, Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 L 50.00 0.00 L 50.00 50.00 L 0.00 50.00 Z ", output.items);
}
