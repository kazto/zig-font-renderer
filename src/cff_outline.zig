const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");

const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;
const readI32 = binary_reader.readI32;

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
    const top_dict_fd_array_escaped_operator = 36;
    const top_dict_fd_select_escaped_operator = 37;
    const private_subrs_operator = 19;
    const fd_select_format_0 = 0;
    const fd_select_format_3 = 3;
    const operand_stack_max = 48;
    const max_subr_depth = 16;
};

const Type2 = struct {
    const escaped_dotsection = 0;
    const escaped_and = 3;
    const escaped_or = 4;
    const escaped_not = 5;
    const escaped_abs = 9;
    const escaped_add = 10;
    const escaped_sub = 11;
    const escaped_div = 12;
    const escaped_neg = 14;
    const escaped_eq = 15;
    const escaped_drop = 18;
    const escaped_put = 20;
    const escaped_get = 21;
    const escaped_ifelse = 22;
    const escaped_random = 23;
    const escaped_mul = 24;
    const escaped_sqrt = 26;
    const escaped_dup = 27;
    const escaped_exch = 28;
    const escaped_index = 29;
    const escaped_roll = 30;
    const escaped_flex = 35;
    const escaped_hflex = 34;
    const escaped_hflex1 = 36;
    const escaped_flex1 = 37;

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
    local_subrs: ?CffIndex = null,
    fd_array_offset: ?usize = null,
    fd_select_offset: ?usize = null,
};

const TopDictInfo = struct {
    charstrings_offset: ?usize = null,
    private_size: ?usize = null,
    private_offset: ?usize = null,
    fd_array_offset: ?usize = null,
    fd_select_offset: ?usize = null,
};

const Type2State = struct {
    stack: [Cff.operand_stack_max]i32 = undefined,
    transient: [32]i32 = [_]i32{0} ** 32,
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
    const local_subrs = try getCffGlyphLocalSubrs(context, glyph_id);

    try writer.print("    <path d=\"", .{});
    try appendType2CharStringPathWithSubrs(writer, charstring, transform, context, local_subrs);
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
        .fd_array_offset = top_dict_info.fd_array_offset,
        .fd_select_offset = top_dict_info.fd_select_offset,
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
                const escaped_operator = dict[offset];
                offset += 1;
                if (escaped_operator == Cff.top_dict_fd_array_escaped_operator) {
                    if (stack_len == 0) return font_parser.ParserError.InvalidTable;
                    const value = stack[stack_len - 1];
                    if (value < 0) return font_parser.ParserError.InvalidTable;
                    result.fd_array_offset = @intCast(value);
                } else if (escaped_operator == Cff.top_dict_fd_select_escaped_operator) {
                    if (stack_len == 0) return font_parser.ParserError.InvalidTable;
                    const value = stack[stack_len - 1];
                    if (value < 0) return font_parser.ParserError.InvalidTable;
                    result.fd_select_offset = @intCast(value);
                }
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

fn getCffGlyphLocalSubrs(context: CffContext, glyph_id: u16) CffError!?CffIndex {
    if (context.fd_array_offset == null and context.fd_select_offset == null) return context.local_subrs;
    const fd_array_offset = context.fd_array_offset orelse return context.local_subrs;
    const fd_select_offset = context.fd_select_offset orelse return context.local_subrs;
    if (fd_array_offset >= context.cff.len or fd_select_offset >= context.cff.len) return font_parser.ParserError.InvalidTable;

    const fd_index = try readCffFdSelect(context.cff[fd_select_offset..], glyph_id, context.charstrings.count);
    const fd_array = try readCffIndex(context.cff[fd_array_offset..]);
    const font_dict = try getCffIndexObject(fd_array, fd_index);
    const font_dict_info = try readCffTopDictInfo(font_dict);
    const private_size = font_dict_info.private_size orelse return null;
    const private_offset = font_dict_info.private_offset orelse return font_parser.ParserError.InvalidTable;
    if (private_offset + private_size > context.cff.len) return font_parser.ParserError.InvalidTable;

    const private_dict = context.cff[private_offset .. private_offset + private_size];
    const subrs_offset = (try readCffPrivateSubrsOffset(private_dict)) orelse return null;
    const absolute_subrs_offset = private_offset + subrs_offset;
    if (absolute_subrs_offset >= context.cff.len) return font_parser.ParserError.InvalidTable;
    return try readCffIndex(context.cff[absolute_subrs_offset..]);
}

fn readCffFdSelect(data: []const u8, glyph_id: u16, glyph_count: u16) CffError!u16 {
    if (glyph_id >= glyph_count or data.len == 0) return font_parser.ParserError.InvalidTable;
    return switch (data[0]) {
        Cff.fd_select_format_0 => readCffFdSelectFormat0(data, glyph_id, glyph_count),
        Cff.fd_select_format_3 => readCffFdSelectFormat3(data, glyph_id),
        else => font_parser.ParserError.InvalidTable,
    };
}

fn readCffFdSelectFormat0(data: []const u8, glyph_id: u16, glyph_count: u16) CffError!u16 {
    if (data.len < 1 + @as(usize, glyph_count)) return font_parser.ParserError.InvalidTable;
    return data[1 + @as(usize, glyph_id)];
}

fn readCffFdSelectFormat3(data: []const u8, glyph_id: u16) CffError!u16 {
    if (data.len < 5) return font_parser.ParserError.InvalidTable;
    const range_count = try readU16(data, 1);
    const sentinel_offset = 3 + @as(usize, range_count) * 3;
    if (sentinel_offset + 2 > data.len) return font_parser.ParserError.InvalidTable;

    var offset: usize = 3;
    var range_index: usize = 0;
    while (range_index < range_count) : (range_index += 1) {
        const first = try readU16(data, offset);
        const fd_index = data[offset + 2];
        const next = if (range_index + 1 == range_count)
            try readU16(data, sentinel_offset)
        else
            try readU16(data, offset + 3);
        if (first > next) return font_parser.ParserError.InvalidTable;
        if (glyph_id >= first and glyph_id < next) return fd_index;
        offset += 3;
    }

    return font_parser.ParserError.InvalidTable;
}

fn appendType2CharStringPath(writer: std.ArrayList(u8).Writer, charstring: []const u8, transform: Transform, context: CffContext) CffError!void {
    try appendType2CharStringPathWithSubrs(writer, charstring, transform, context, context.local_subrs);
}

fn appendType2CharStringPathWithSubrs(writer: std.ArrayList(u8).Writer, charstring: []const u8, transform: Transform, context: CffContext, local_subrs: ?CffIndex) CffError!void {
    var state = Type2State{};
    try executeType2CharString(writer, charstring, transform, context, local_subrs, &state, 0);
}

fn executeType2CharString(writer: std.ArrayList(u8).Writer, charstring: []const u8, transform: Transform, context: CffContext, local_subrs: ?CffIndex, state: *Type2State, depth: u8) CffError!void {
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
            Type2.callsubr => try executeCffSubroutine(writer, transform, context, local_subrs, state, depth + 1),
            Type2.callgsubr => try executeCffSubroutine(writer, transform, context, context.global_subrs, state, depth + 1),
            Type2.return_op => return,
            Type2.endchar => {
                try writer.print("Z ", .{});
                return;
            },
            Type2.escape => {
                if (offset >= charstring.len) return font_parser.ParserError.InvalidTable;
                const escaped_operator = charstring[offset];
                offset += 1;
                switch (escaped_operator) {
                    Type2.escaped_dotsection => state.stack_len = 0,
                    Type2.escaped_and => try executeType2And(state),
                    Type2.escaped_or => try executeType2Or(state),
                    Type2.escaped_not => try executeType2Not(state),
                    Type2.escaped_abs => try executeType2Abs(state),
                    Type2.escaped_add => try executeType2Add(state),
                    Type2.escaped_sub => try executeType2Sub(state),
                    Type2.escaped_div => try executeType2Div(state),
                    Type2.escaped_neg => try executeType2Neg(state),
                    Type2.escaped_eq => try executeType2Eq(state),
                    Type2.escaped_drop => try executeType2Drop(state),
                    Type2.escaped_put => try executeType2Put(state),
                    Type2.escaped_get => try executeType2Get(state),
                    Type2.escaped_ifelse => try executeType2IfElse(state),
                    Type2.escaped_random => try executeType2Random(state),
                    Type2.escaped_mul => try executeType2Mul(state),
                    Type2.escaped_sqrt => try executeType2Sqrt(state),
                    Type2.escaped_dup => try executeType2Dup(state),
                    Type2.escaped_exch => try executeType2Exch(state),
                    Type2.escaped_index => try executeType2Index(state),
                    Type2.escaped_roll => try executeType2Roll(state),
                    Type2.escaped_flex => try emitType2Flex(writer, transform, state),
                    Type2.escaped_hflex => try emitType2HFlex(writer, transform, state),
                    Type2.escaped_hflex1 => try emitType2HFlex1(writer, transform, state),
                    Type2.escaped_flex1 => try emitType2Flex1(writer, transform, state),
                    else => return CffError.UnsupportedCffOperator,
                }
            },
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

fn executeType2And(state: *Type2State) CffError!void {
    if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
    const rhs = popType2Stack(state);
    const lhs = popType2Stack(state);
    try pushType2Stack(state, if (lhs != 0 and rhs != 0) 1 else 0);
}

fn executeType2Or(state: *Type2State) CffError!void {
    if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
    const rhs = popType2Stack(state);
    const lhs = popType2Stack(state);
    try pushType2Stack(state, if (lhs != 0 or rhs != 0) 1 else 0);
}

fn executeType2Not(state: *Type2State) CffError!void {
    if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
    state.stack[state.stack_len - 1] = if (state.stack[state.stack_len - 1] == 0) 1 else 0;
}

fn executeType2Abs(state: *Type2State) CffError!void {
    if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
    const value = state.stack[state.stack_len - 1];
    if (value == std.math.minInt(i32)) return font_parser.ParserError.InvalidTable;
    state.stack[state.stack_len - 1] = if (value < 0) -value else value;
}

fn executeType2Add(state: *Type2State) CffError!void {
    if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
    const rhs = popType2Stack(state);
    const lhs = popType2Stack(state);
    try pushType2Stack(state, try checkedAdd(lhs, rhs));
}

fn executeType2Sub(state: *Type2State) CffError!void {
    if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
    const rhs = popType2Stack(state);
    const lhs = popType2Stack(state);
    try pushType2Stack(state, try checkedSub(lhs, rhs));
}

fn executeType2Div(state: *Type2State) CffError!void {
    if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
    const rhs = popType2Stack(state);
    const lhs = popType2Stack(state);
    if (rhs == 0) return font_parser.ParserError.InvalidTable;
    try pushType2Stack(state, @divTrunc(lhs, rhs));
}

fn executeType2Neg(state: *Type2State) CffError!void {
    if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
    const value = state.stack[state.stack_len - 1];
    if (value == std.math.minInt(i32)) return font_parser.ParserError.InvalidTable;
    state.stack[state.stack_len - 1] = -value;
}

fn executeType2Eq(state: *Type2State) CffError!void {
    if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
    const rhs = popType2Stack(state);
    const lhs = popType2Stack(state);
    try pushType2Stack(state, if (lhs == rhs) 1 else 0);
}

fn executeType2Drop(state: *Type2State) CffError!void {
    if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
    _ = popType2Stack(state);
}

fn executeType2Put(state: *Type2State) CffError!void {
    if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
    const index = popType2Stack(state);
    const value = popType2Stack(state);
    if (index < 0 or index >= state.transient.len) return font_parser.ParserError.InvalidTable;
    state.transient[@intCast(index)] = value;
}

fn executeType2Get(state: *Type2State) CffError!void {
    if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
    const index = popType2Stack(state);
    if (index < 0 or index >= state.transient.len) return font_parser.ParserError.InvalidTable;
    try pushType2Stack(state, state.transient[@intCast(index)]);
}

fn executeType2IfElse(state: *Type2State) CffError!void {
    if (state.stack_len < 4) return font_parser.ParserError.InvalidTable;
    const value2 = popType2Stack(state);
    const value1 = popType2Stack(state);
    const s2 = popType2Stack(state);
    const s1 = popType2Stack(state);
    try pushType2Stack(state, if (value1 <= value2) s1 else s2);
}

fn executeType2Random(state: *Type2State) CffError!void {
    try pushType2Stack(state, 1);
}

fn executeType2Mul(state: *Type2State) CffError!void {
    if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
    const rhs = popType2Stack(state);
    const lhs = popType2Stack(state);
    try pushType2Stack(state, try checkedMul(lhs, rhs));
}

fn executeType2Sqrt(state: *Type2State) CffError!void {
    if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
    const value = state.stack[state.stack_len - 1];
    if (value < 0) return font_parser.ParserError.InvalidTable;
    state.stack[state.stack_len - 1] = @intFromFloat(@sqrt(@as(f64, @floatFromInt(value))));
}

fn executeType2Dup(state: *Type2State) CffError!void {
    if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
    try pushType2Stack(state, state.stack[state.stack_len - 1]);
}

fn executeType2Exch(state: *Type2State) CffError!void {
    if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
    const last = state.stack_len - 1;
    const previous = state.stack_len - 2;
    const tmp = state.stack[last];
    state.stack[last] = state.stack[previous];
    state.stack[previous] = tmp;
}

fn executeType2Index(state: *Type2State) CffError!void {
    if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
    const raw_index = popType2Stack(state);
    const index: usize = if (raw_index < 0) 0 else @intCast(raw_index);
    if (index >= state.stack_len) return font_parser.ParserError.InvalidTable;
    try pushType2Stack(state, state.stack[state.stack_len - 1 - index]);
}

fn executeType2Roll(state: *Type2State) CffError!void {
    if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
    const j = popType2Stack(state);
    const raw_n = popType2Stack(state);
    if (raw_n < 0) return font_parser.ParserError.InvalidTable;
    const n: usize = @intCast(raw_n);
    if (n == 0) return;
    if (n > state.stack_len) return font_parser.ParserError.InvalidTable;

    const base = state.stack_len - n;
    const rotation = @mod(j, raw_n);
    var steps: usize = @intCast(rotation);
    while (steps > 0) : (steps -= 1) {
        const last = state.stack[state.stack_len - 1];
        var index = state.stack_len - 1;
        while (index > base) : (index -= 1) {
            state.stack[index] = state.stack[index - 1];
        }
        state.stack[base] = last;
    }
}

fn popType2Stack(state: *Type2State) i32 {
    state.stack_len -= 1;
    return state.stack[state.stack_len];
}

fn pushType2Stack(state: *Type2State, value: i32) CffError!void {
    if (state.stack_len >= state.stack.len) return font_parser.ParserError.InvalidTable;
    state.stack[state.stack_len] = value;
    state.stack_len += 1;
}

fn checkedAdd(lhs: i32, rhs: i32) CffError!i32 {
    return std.math.add(i32, lhs, rhs) catch font_parser.ParserError.InvalidTable;
}

fn checkedSub(lhs: i32, rhs: i32) CffError!i32 {
    return std.math.sub(i32, lhs, rhs) catch font_parser.ParserError.InvalidTable;
}

fn checkedMul(lhs: i32, rhs: i32) CffError!i32 {
    return std.math.mul(i32, lhs, rhs) catch font_parser.ParserError.InvalidTable;
}

fn emitType2Flex(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != 13) return font_parser.ParserError.InvalidTable;
    try emitType2Curve(writer, transform, state, state.stack[0], state.stack[1], state.stack[2], state.stack[3], state.stack[4], state.stack[5]);
    try emitType2Curve(writer, transform, state, state.stack[6], state.stack[7], state.stack[8], state.stack[9], state.stack[10], state.stack[11]);
    state.stack_len = 0;
}

fn emitType2HFlex(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != 7) return font_parser.ParserError.InvalidTable;
    try emitType2Curve(writer, transform, state, state.stack[0], 0, state.stack[1], state.stack[2], state.stack[3], 0);
    try emitType2Curve(writer, transform, state, state.stack[4], 0, state.stack[5], -state.stack[2], state.stack[6], 0);
    state.stack_len = 0;
}

fn emitType2HFlex1(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != 9) return font_parser.ParserError.InvalidTable;
    const dy6 = -(state.stack[1] + state.stack[3] + state.stack[7]);
    try emitType2Curve(writer, transform, state, state.stack[0], state.stack[1], state.stack[2], state.stack[3], state.stack[4], 0);
    try emitType2Curve(writer, transform, state, state.stack[5], 0, state.stack[6], state.stack[7], state.stack[8], dy6);
    state.stack_len = 0;
}

fn emitType2Flex1(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != 11) return font_parser.ParserError.InvalidTable;
    const dx_sum = state.stack[0] + state.stack[2] + state.stack[4] + state.stack[6] + state.stack[8];
    const dy_sum = state.stack[1] + state.stack[3] + state.stack[5] + state.stack[7] + state.stack[9];
    const dx6: i32 = if (absI32(dx_sum) > absI32(dy_sum)) state.stack[10] else -dx_sum;
    const dy6: i32 = if (absI32(dx_sum) > absI32(dy_sum)) -dy_sum else state.stack[10];

    try emitType2Curve(writer, transform, state, state.stack[0], state.stack[1], state.stack[2], state.stack[3], state.stack[4], state.stack[5]);
    try emitType2Curve(writer, transform, state, state.stack[6], state.stack[7], state.stack[8], state.stack[9], dx6, dy6);
    state.stack_len = 0;
}

fn absI32(value: i32) i32 {
    return if (value < 0) -value else value;
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
    try executeType2CharString(writer, subr, transform, context, maybe_subrs, state, depth);
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

test "CFF top dict reads FDArray and FDSelect offsets" {
    const dict = [_]u8{
        189, Type2.escape, Cff.top_dict_fd_array_escaped_operator,
        199, Type2.escape, Cff.top_dict_fd_select_escaped_operator,
    };
    const info = try readCffTopDictInfo(&dict);
    try std.testing.expectEqual(@as(?usize, 50), info.fd_array_offset);
    try std.testing.expectEqual(@as(?usize, 60), info.fd_select_offset);
}

test "CFF FDSelect format 0 maps glyph IDs" {
    const fd_select = [_]u8{ Cff.fd_select_format_0, 2, 4, 2 };

    try std.testing.expectEqual(@as(u16, 2), try readCffFdSelect(&fd_select, 0, 3));
    try std.testing.expectEqual(@as(u16, 4), try readCffFdSelect(&fd_select, 1, 3));
    try std.testing.expectEqual(@as(u16, 2), try readCffFdSelect(&fd_select, 2, 3));
    try std.testing.expectError(font_parser.ParserError.InvalidTable, readCffFdSelect(&fd_select, 3, 3));
}

test "CFF FDSelect format 3 maps glyph ranges" {
    const fd_select = [_]u8{
        Cff.fd_select_format_3,
        0,
        2,
        0,
        0,
        1,
        0,
        3,
        2,
        0,
        5,
    };

    try std.testing.expectEqual(@as(u16, 1), try readCffFdSelect(&fd_select, 0, 5));
    try std.testing.expectEqual(@as(u16, 1), try readCffFdSelect(&fd_select, 2, 5));
    try std.testing.expectEqual(@as(u16, 2), try readCffFdSelect(&fd_select, 3, 5));
    try std.testing.expectEqual(@as(u16, 2), try readCffFdSelect(&fd_select, 4, 5));
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

test "Type2 escaped arithmetic operators feed drawing operands" {
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
        139,               139,               Type2.rmoveto,
        149,               159,               Type2.escape,
        Type2.escaped_add, 141,               142,
        Type2.escape,      Type2.escaped_mul, Type2.rlineto,
        Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 L 30.00 6.00 Z ", output.items);
}

test "Type2 escaped storage and conditional operators feed drawing operands" {
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
        139,                  139,           Type2.rmoveto,
        181,                  139,           Type2.escape,
        Type2.escaped_put,    139,           Type2.escape,
        Type2.escaped_get,    140,           141,
        140,                  141,           Type2.escape,
        Type2.escaped_ifelse, Type2.escape,  Type2.escaped_add,
        139,                  Type2.rlineto, Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 L 43.00 0.00 Z ", output.items);
}

test "Type2 escaped stack manipulation operators" {
    var state = Type2State{};
    state.stack[0] = 10;
    state.stack[1] = 20;
    state.stack[2] = 30;
    state.stack_len = 3;

    try executeType2Dup(&state);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 10, 20, 30, 30 }, state.stack[0..state.stack_len]);

    try executeType2Exch(&state);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 10, 20, 30, 30 }, state.stack[0..state.stack_len]);

    try pushType2Stack(&state, 2);
    try executeType2Index(&state);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 10, 20, 30, 30, 20 }, state.stack[0..state.stack_len]);

    try pushType2Stack(&state, 3);
    try pushType2Stack(&state, 1);
    try executeType2Roll(&state);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 10, 20, 20, 30, 30 }, state.stack[0..state.stack_len]);
}

test "Type2 hflex emits two cubic curves" {
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
        139,           139,          Type2.rmoveto,
        149,           159,          169,
        179,           189,          199,
        209,           Type2.escape, Type2.escaped_hflex,
        Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 C 10.00 0.00 30.00 30.00 70.00 30.00 C 120.00 30.00 180.00 0.00 250.00 0.00 Z ", output.items);
}

test "Type2 flex emits two cubic curves" {
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
        139,           139,          Type2.rmoveto,
        149,           139,          159,
        139,           169,          139,
        179,           139,          189,
        139,           199,          139,
        139,           Type2.escape, Type2.escaped_flex,
        Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 C 10.00 0.00 30.00 0.00 60.00 0.00 C 100.00 0.00 150.00 0.00 210.00 0.00 Z ", output.items);
}

test "Type2 hflex1 balances final y delta" {
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
        139,          139,                  Type2.rmoveto,
        149,          144,                  159,
        144,          169,                  179,
        189,          144,                  199,
        Type2.escape, Type2.escaped_hflex1, Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 C 10.00 5.00 30.00 10.00 60.00 10.00 C 100.00 10.00 150.00 15.00 210.00 0.00 Z ", output.items);
}

test "Type2 flex1 chooses final axis delta" {
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
        139,                 139,           Type2.rmoveto,
        149,                 144,           149,
        144,                 149,           144,
        149,                 144,           149,
        144,                 139,           Type2.escape,
        Type2.escaped_flex1, Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 C 10.00 5.00 20.00 10.00 30.00 15.00 C 40.00 20.00 50.00 25.00 50.00 0.00 Z ", output.items);
}
