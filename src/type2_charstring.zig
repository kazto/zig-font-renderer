const std = @import("std");
const font_parser = @import("font_parser.zig");
const cff_index = @import("cff_index.zig");
const stack_ops = @import("type2_stack_ops.zig");
const types = @import("cff_types.zig");

const Cff = types.Cff;
const Type2 = types.Type2;
pub const Transform = types.Transform;
const CffContext = types.CffContext;
const CffIndex = types.CffIndex;
const Type2State = types.Type2State;
const CffError = types.CffError;
const isType2Number = cff_index.isType2Number;
const readType2Number = cff_index.readType2Number;
const getCffIndexObject = cff_index.getCffIndexObject;

const initial_subroutine_depth = 0;
const stack_empty = 0;
const stack_single_operand = 1;
const stack_pair_operand_count = 2;
const line_operand_pair_count = 2;
const curve_operand_count = 6;
const curve_with_line_min_operands = 8;
const alternating_curve_min_operands = 4;
const hflex_operand_count = 7;
const hflex1_operand_count = 9;
const flex1_operand_count = 11;
const flex_operand_count = 13;
const hint_stem_operand_count = 2;
const optional_width_operand_count = 1;
const hint_mask_rounding = 7;
const hint_mask_bits_per_byte = 8;
const type2_false = 0;
const zero_delta = 0;
const subr_bias_low_count_threshold = 1240;
const subr_bias_medium_count_threshold = 33900;
const subr_bias_low = 107;
const subr_bias_medium = 1131;
const subr_bias_high = 32768;

pub fn appendType2CharStringPath(writer: std.ArrayList(u8).Writer, charstring: []const u8, transform: Transform, context: CffContext) CffError!void {
    try appendType2CharStringPathWithSubrs(writer, charstring, transform, context, context.local_subrs);
}

pub fn appendType2CharStringPathWithSubrs(writer: std.ArrayList(u8).Writer, charstring: []const u8, transform: Transform, context: CffContext, local_subrs: ?CffIndex) CffError!void {
    var state = Type2State{};
    try executeType2CharString(writer, charstring, transform, context, local_subrs, &state, initial_subroutine_depth);
}

pub fn executeType2CharString(writer: std.ArrayList(u8).Writer, charstring: []const u8, transform: Transform, context: CffContext, local_subrs: ?CffIndex, state: *Type2State, depth: u8) CffError!void {
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
                try applyStemHintCount(state, context.is_cff2);
            },
            Type2.hintmask, Type2.cntrmask => {
                try applyStemHintCount(state, context.is_cff2);
                state.stack_len = stack_empty;
                const mask_len = (state.hint_count + hint_mask_rounding) / hint_mask_bits_per_byte;
                if (offset + mask_len > charstring.len) return font_parser.ParserError.InvalidTable;
                offset += mask_len;
            },
            Type2.rmoveto => {
                if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
                state.x += state.stack[state.stack_len - stack_pair_operand_count];
                state.y += state.stack[state.stack_len - stack_single_operand];
                const point = transform.apply(state.x, state.y);
                try writer.print("M {d:.2} {d:.2} ", .{ point.x, point.y });
                state.has_current_point = true;
                state.subpath_start_x = state.x;
                state.subpath_start_y = state.y;
                state.subpath_open = true;
                state.stack_len = stack_empty;
            },
            Type2.hmoveto => {
                if (state.stack_len < stack_single_operand) return font_parser.ParserError.InvalidTable;
                state.x += state.stack[state.stack_len - stack_single_operand];
                const point = transform.apply(state.x, state.y);
                try writer.print("M {d:.2} {d:.2} ", .{ point.x, point.y });
                state.has_current_point = true;
                state.subpath_start_x = state.x;
                state.subpath_start_y = state.y;
                state.subpath_open = true;
                state.stack_len = stack_empty;
            },
            Type2.vmoveto => {
                if (state.stack_len < stack_single_operand) return font_parser.ParserError.InvalidTable;
                state.y += state.stack[state.stack_len - stack_single_operand];
                const point = transform.apply(state.x, state.y);
                try writer.print("M {d:.2} {d:.2} ", .{ point.x, point.y });
                state.has_current_point = true;
                state.subpath_start_x = state.x;
                state.subpath_start_y = state.y;
                state.subpath_open = true;
                state.stack_len = stack_empty;
            },
            Type2.rlineto => {
                if (!state.has_current_point or state.stack_len < line_operand_pair_count or (state.stack_len % line_operand_pair_count) != stack_empty) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                while (index < state.stack_len) : (index += line_operand_pair_count) {
                    state.x += state.stack[index];
                    state.y += state.stack[index + stack_single_operand];
                    const point = transform.apply(state.x, state.y);
                    try writer.print("L {d:.2} {d:.2} ", .{ point.x, point.y });
                }
                state.stack_len = stack_empty;
            },
            Type2.hlineto, Type2.vlineto => {
                if (!state.has_current_point or state.stack_len == stack_empty) return font_parser.ParserError.InvalidTable;
                var horizontal = byte == Type2.hlineto;
                for (state.stack[0..state.stack_len]) |value| {
                    if (horizontal) state.x += value else state.y += value;
                    const point = transform.apply(state.x, state.y);
                    try writer.print("L {d:.2} {d:.2} ", .{ point.x, point.y });
                    horizontal = !horizontal;
                }
                state.stack_len = stack_empty;
            },
            Type2.rrcurveto => {
                if (!state.has_current_point or state.stack_len < curve_operand_count or (state.stack_len % curve_operand_count) != stack_empty) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                while (index < state.stack_len) : (index += curve_operand_count) {
                    try emitType2Curve(writer, transform, state, state.stack[index], state.stack[index + 1], state.stack[index + 2], state.stack[index + 3], state.stack[index + 4], state.stack[index + 5]);
                }
                state.stack_len = stack_empty;
            },
            Type2.closepath => {
                if (state.subpath_open) {
                    try writer.print("Z ", .{});
                    state.x = state.subpath_start_x;
                    state.y = state.subpath_start_y;
                    state.subpath_open = false;
                }
                state.stack_len = stack_empty;
            },
            Type2.rcurveline => {
                if (!state.has_current_point or state.stack_len < curve_with_line_min_operands or ((state.stack_len - line_operand_pair_count) % curve_operand_count) != stack_empty) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                while (index + line_operand_pair_count < state.stack_len) : (index += curve_operand_count) {
                    try emitType2Curve(writer, transform, state, state.stack[index], state.stack[index + 1], state.stack[index + 2], state.stack[index + 3], state.stack[index + 4], state.stack[index + 5]);
                }
                state.x += state.stack[state.stack_len - stack_pair_operand_count];
                state.y += state.stack[state.stack_len - stack_single_operand];
                const point = transform.apply(state.x, state.y);
                try writer.print("L {d:.2} {d:.2} ", .{ point.x, point.y });
                state.stack_len = stack_empty;
            },
            Type2.rlinecurve => {
                if (!state.has_current_point or state.stack_len < curve_with_line_min_operands or ((state.stack_len - curve_operand_count) % line_operand_pair_count) != stack_empty) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                while (index + curve_operand_count < state.stack_len) : (index += line_operand_pair_count) {
                    state.x += state.stack[index];
                    state.y += state.stack[index + stack_single_operand];
                    const point = transform.apply(state.x, state.y);
                    try writer.print("L {d:.2} {d:.2} ", .{ point.x, point.y });
                }
                try emitType2Curve(writer, transform, state, state.stack[index], state.stack[index + 1], state.stack[index + 2], state.stack[index + 3], state.stack[index + 4], state.stack[index + 5]);
                state.stack_len = stack_empty;
            },
            Type2.hhcurveto => {
                if (!state.has_current_point or state.stack_len < alternating_curve_min_operands) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                var dy1: i32 = zero_delta;
                if ((state.stack_len % alternating_curve_min_operands) == optional_width_operand_count) {
                    dy1 = state.stack[0];
                    index = optional_width_operand_count;
                }
                if (((state.stack_len - index) % alternating_curve_min_operands) != stack_empty) return font_parser.ParserError.InvalidTable;
                while (index < state.stack_len) : (index += alternating_curve_min_operands) {
                    try emitType2Curve(writer, transform, state, state.stack[index], dy1, state.stack[index + 1], state.stack[index + 2], state.stack[index + 3], zero_delta);
                    dy1 = zero_delta;
                }
                state.stack_len = stack_empty;
            },
            Type2.vvcurveto => {
                if (!state.has_current_point or state.stack_len < alternating_curve_min_operands) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                var dx1: i32 = zero_delta;
                if ((state.stack_len % alternating_curve_min_operands) == optional_width_operand_count) {
                    dx1 = state.stack[0];
                    index = optional_width_operand_count;
                }
                if (((state.stack_len - index) % alternating_curve_min_operands) != stack_empty) return font_parser.ParserError.InvalidTable;
                while (index < state.stack_len) : (index += alternating_curve_min_operands) {
                    try emitType2Curve(writer, transform, state, dx1, state.stack[index], state.stack[index + 1], state.stack[index + 2], zero_delta, state.stack[index + 3]);
                    dx1 = zero_delta;
                }
                state.stack_len = stack_empty;
            },
            Type2.hvcurveto, Type2.vhcurveto => {
                if (!state.has_current_point or state.stack_len < alternating_curve_min_operands) return font_parser.ParserError.InvalidTable;
                try emitType2AlternatingCurve(writer, transform, state, byte == Type2.hvcurveto);
                state.stack_len = stack_empty;
            },
            Type2.callsubr => try executeCffSubroutine(writer, transform, context, local_subrs, state, depth + 1),
            Type2.callgsubr => try executeCffSubroutine(writer, transform, context, context.global_subrs, state, depth + 1),
            Type2.return_op => return,
            Type2.endchar => {
                if (state.subpath_open) try writer.print("Z ", .{});
                return;
            },
            Type2.blend => return CffError.UnsupportedCffOperator,
            Type2.escape => {
                if (offset >= charstring.len) return font_parser.ParserError.InvalidTable;
                const escaped_operator = charstring[offset];
                offset += 1;
                switch (escaped_operator) {
                    Type2.escaped_dotsection => state.stack_len = stack_empty,
                    Type2.escaped_vstem3, Type2.escaped_hstem3 => try applyStemHintCount(state, context.is_cff2),
                    Type2.escaped_callothersubr => try stack_ops.executeCallOtherSubr(state),
                    Type2.escaped_pop => try stack_ops.executePop(state),
                    Type2.escaped_and => try stack_ops.executeAnd(state),
                    Type2.escaped_or => try stack_ops.executeOr(state),
                    Type2.escaped_not => try stack_ops.executeNot(state),
                    Type2.escaped_abs => try stack_ops.executeAbs(state),
                    Type2.escaped_add => try stack_ops.executeAdd(state),
                    Type2.escaped_sub => try stack_ops.executeSub(state),
                    Type2.escaped_div => try stack_ops.executeDiv(state),
                    Type2.escaped_neg => try stack_ops.executeNeg(state),
                    Type2.escaped_eq => try stack_ops.executeEq(state),
                    Type2.escaped_drop => try stack_ops.executeDrop(state),
                    Type2.escaped_put => try stack_ops.executePut(state),
                    Type2.escaped_get => try stack_ops.executeGet(state),
                    Type2.escaped_ifelse => try stack_ops.executeIfElse(state),
                    Type2.escaped_random => try stack_ops.executeRandom(state),
                    Type2.escaped_mul => try stack_ops.executeMul(state),
                    Type2.escaped_sqrt => try stack_ops.executeSqrt(state),
                    Type2.escaped_dup => try stack_ops.executeDup(state),
                    Type2.escaped_exch => try stack_ops.executeExch(state),
                    Type2.escaped_index => try stack_ops.executeIndex(state),
                    Type2.escaped_roll => try stack_ops.executeRoll(state),
                    Type2.escaped_setcurrentpoint => try executeType2SetCurrentPoint(state),
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

    if (context.is_cff2 and depth == initial_subroutine_depth and state.subpath_open) {
        try writer.print("Z ", .{});
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

fn applyStemHintCount(state: *Type2State, is_cff2: bool) CffError!void {
    if (is_cff2 and (state.stack_len % hint_stem_operand_count) != stack_empty) return font_parser.ParserError.InvalidTable;
    const width_operands: usize = if (!is_cff2 and (state.stack_len % hint_stem_operand_count) == optional_width_operand_count) optional_width_operand_count else stack_empty;
    state.hint_count += (state.stack_len - width_operands) / hint_stem_operand_count;
    state.stack_len = stack_empty;
}

fn executeType2SetCurrentPoint(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    state.x = state.stack[state.stack_len - stack_pair_operand_count];
    state.y = state.stack[state.stack_len - stack_single_operand];
    state.has_current_point = true;
    state.stack_len = stack_empty;
}

fn emitType2Flex(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != flex_operand_count) return font_parser.ParserError.InvalidTable;
    try emitType2Curve(writer, transform, state, state.stack[0], state.stack[1], state.stack[2], state.stack[3], state.stack[4], state.stack[5]);
    try emitType2Curve(writer, transform, state, state.stack[6], state.stack[7], state.stack[8], state.stack[9], state.stack[10], state.stack[11]);
    state.stack_len = stack_empty;
}

fn emitType2HFlex(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != hflex_operand_count) return font_parser.ParserError.InvalidTable;
    try emitType2Curve(writer, transform, state, state.stack[0], zero_delta, state.stack[1], state.stack[2], state.stack[3], zero_delta);
    try emitType2Curve(writer, transform, state, state.stack[4], zero_delta, state.stack[5], -state.stack[2], state.stack[6], zero_delta);
    state.stack_len = stack_empty;
}

fn emitType2HFlex1(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != hflex1_operand_count) return font_parser.ParserError.InvalidTable;
    const dy6 = -(state.stack[1] + state.stack[3] + state.stack[7]);
    try emitType2Curve(writer, transform, state, state.stack[0], state.stack[1], state.stack[2], state.stack[3], state.stack[4], zero_delta);
    try emitType2Curve(writer, transform, state, state.stack[5], zero_delta, state.stack[6], state.stack[7], state.stack[8], dy6);
    state.stack_len = stack_empty;
}

fn emitType2Flex1(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != flex1_operand_count) return font_parser.ParserError.InvalidTable;
    const dx_sum = state.stack[0] + state.stack[2] + state.stack[4] + state.stack[6] + state.stack[8];
    const dy_sum = state.stack[1] + state.stack[3] + state.stack[5] + state.stack[7] + state.stack[9];
    const dx6: i32 = if (absI32(dx_sum) > absI32(dy_sum)) state.stack[10] else -dx_sum;
    const dy6: i32 = if (absI32(dx_sum) > absI32(dy_sum)) -dy_sum else state.stack[10];

    try emitType2Curve(writer, transform, state, state.stack[0], state.stack[1], state.stack[2], state.stack[3], state.stack[4], state.stack[5]);
    try emitType2Curve(writer, transform, state, state.stack[6], state.stack[7], state.stack[8], state.stack[9], dx6, dy6);
    state.stack_len = stack_empty;
}

fn absI32(value: i32) i32 {
    return if (value < 0) -value else value;
}

fn emitType2AlternatingCurve(writer: std.ArrayList(u8).Writer, transform: Transform, state: *Type2State, starts_horizontal: bool) CffError!void {
    var index: usize = 0;
    var horizontal = starts_horizontal;
    while (index < state.stack_len) {
        const remaining = state.stack_len - index;
        if (remaining < alternating_curve_min_operands) return font_parser.ParserError.InvalidTable;
        if (horizontal) {
            const dx1 = state.stack[index];
            const dx2 = state.stack[index + 1];
            const dy2 = state.stack[index + 2];
            const dy3 = state.stack[index + 3];
            index += alternating_curve_min_operands;
            const dx3: i32 = if (state.stack_len - index == optional_width_operand_count) state.stack[index] else zero_delta;
            if (state.stack_len - index == optional_width_operand_count) index += optional_width_operand_count;
            try emitType2Curve(writer, transform, state, dx1, zero_delta, dx2, dy2, dx3, dy3);
        } else {
            const dy1 = state.stack[index];
            const dx2 = state.stack[index + 1];
            const dy2 = state.stack[index + 2];
            const dx3 = state.stack[index + 3];
            index += alternating_curve_min_operands;
            const dy3: i32 = if (state.stack_len - index == optional_width_operand_count) state.stack[index] else zero_delta;
            if (state.stack_len - index == optional_width_operand_count) index += optional_width_operand_count;
            try emitType2Curve(writer, transform, state, zero_delta, dy1, dx2, dy2, dx3, dy3);
        }
        horizontal = !horizontal;
    }
}

fn executeCffSubroutine(writer: std.ArrayList(u8).Writer, transform: Transform, context: CffContext, maybe_subrs: ?CffIndex, state: *Type2State, depth: u8) CffError!void {
    const subrs = maybe_subrs orelse return CffError.UnsupportedCffOperator;
    if (state.stack_len == stack_empty) return font_parser.ParserError.InvalidTable;
    const raw_index = state.stack[state.stack_len - stack_single_operand];
    state.stack_len -= stack_single_operand;
    const biased_index = raw_index + cffSubrBias(subrs.count);
    if (biased_index < type2_false or biased_index > std.math.maxInt(u16)) return font_parser.ParserError.InvalidTable;
    const subr = try getCffIndexObject(subrs, @intCast(biased_index));
    try executeType2CharString(writer, subr, transform, context, maybe_subrs, state, depth);
}

pub fn cffSubrBias(count: u32) i32 {
    if (count < subr_bias_low_count_threshold) return subr_bias_low;
    if (count < subr_bias_medium_count_threshold) return subr_bias_medium;
    return subr_bias_high;
}

const cff_context = @import("cff_context.zig");
const readCffIndex = cff_index.readCffIndex;
const readCff2Index = cff_index.readCff2Index;
const readCffTopDictInfo = cff_context.readCffTopDictInfo;
const readCff2TopDictInfo = cff_context.readCff2TopDictInfo;
const readCffFdSelect = cff_context.readCffFdSelect;

test "CFF INDEX reads object slices" {
    const data = [_]u8{
        0,   2,   1,
        1,   3,   4,
        'A', 'B', 'C',
    };
    const index = try readCffIndex(&data);
    try std.testing.expectEqual(@as(u32, 2), index.count);
    try std.testing.expectEqualSlices(u8, "AB", try getCffIndexObject(index, 0));
    try std.testing.expectEqualSlices(u8, "C", try getCffIndexObject(index, 1));
}

test "CFF2 INDEX reads object slices" {
    const data = [_]u8{
        0,   0, 0, 2,   1,
        1,   3, 4, 'A', 'B',
        'C',
    };
    const index = try readCff2Index(&data);
    try std.testing.expectEqual(@as(u32, 2), index.count);
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

test "CFF2 top dict reads CharStrings, FDArray, and FDSelect offsets" {
    const dict = [_]u8{
        150,                                    Cff.top_dict_charstrings_operator,
        189,                                    Type2.escape,
        Cff.top_dict_fd_array_escaped_operator, 199,
        Type2.escape,                           Cff.top_dict_fd_select_escaped_operator,
    };
    const info = try readCff2TopDictInfo(&dict);
    try std.testing.expectEqual(@as(?usize, 11), info.charstrings_offset);
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

test "Type2 hstem3 and vstem3 contribute to hintmask length" {
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
        139,           139,                  139,            139,           139,           139,
        Type2.escape,  Type2.escaped_hstem3, Type2.hintmask, 0x00,          139,           139,
        Type2.rmoveto, 189,                  139,            Type2.rlineto, Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 L 50.00 0.00 Z ", output.items);
}

test "Type2 setcurrentpoint updates the current point" {
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
        139,                           139,           Type2.rmoveto,
        149,                           159,           Type2.escape,
        Type2.escaped_setcurrentpoint, 141,           142,
        Type2.rlineto,                 Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 L 12.00 23.00 Z ", output.items);
}

test "Type2 callothersubr and pop preserve operands" {
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
        149,               159,               139,
        141,               Type2.escape,      Type2.escaped_callothersubr,
        Type2.escape,      Type2.escaped_pop, Type2.escape,
        Type2.escaped_pop, 141,               142,
        Type2.rlineto,     Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 L 10.00 20.00 L 12.00 23.00 Z ", output.items);
}

test "Type2 closepath closes the active contour once" {
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
        139,             139,           Type2.rmoveto,
        189,             139,           Type2.rlineto,
        Type2.closepath, Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 L 50.00 0.00 Z ", output.items);
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
