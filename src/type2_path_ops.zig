const std = @import("std");
const font_parser = @import("font_parser.zig");
const types = @import("cff_types.zig");

const CffError = types.CffError;
const Transform = types.Transform;
const Type2State = types.Type2State;

const stack_empty = 0;
const stack_single_operand = 1;
const stack_pair_operand_count = 2;
const curve_operand_count = 6;
const alternating_curve_min_operands = 4;
const hflex_operand_count = 7;
const hflex1_operand_count = 9;
const flex1_operand_count = 11;
const flex_operand_count = 13;
const optional_width_operand_count = 1;
const zero_delta = 0;

pub fn emitCurve(writer: *std.Io.Writer, transform: Transform, state: *Type2State, dx1: i32, dy1: i32, dx2: i32, dy2: i32, dx3: i32, dy3: i32) CffError!void {
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

pub fn executeSetCurrentPoint(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    state.x = state.stack[state.stack_len - stack_pair_operand_count];
    state.y = state.stack[state.stack_len - stack_single_operand];
    state.has_current_point = true;
    state.stack_len = stack_empty;
}

pub fn emitFlex(writer: *std.Io.Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != flex_operand_count) return font_parser.ParserError.InvalidTable;
    try emitCurve(writer, transform, state, state.stack[0], state.stack[1], state.stack[2], state.stack[3], state.stack[4], state.stack[5]);
    try emitCurve(writer, transform, state, state.stack[6], state.stack[7], state.stack[8], state.stack[9], state.stack[10], state.stack[11]);
    state.stack_len = stack_empty;
}

pub fn emitHFlex(writer: *std.Io.Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != hflex_operand_count) return font_parser.ParserError.InvalidTable;
    try emitCurve(writer, transform, state, state.stack[0], zero_delta, state.stack[1], state.stack[2], state.stack[3], zero_delta);
    try emitCurve(writer, transform, state, state.stack[4], zero_delta, state.stack[5], -state.stack[2], state.stack[6], zero_delta);
    state.stack_len = stack_empty;
}

pub fn emitHFlex1(writer: *std.Io.Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != hflex1_operand_count) return font_parser.ParserError.InvalidTable;
    const dy6 = -(state.stack[1] + state.stack[3] + state.stack[7]);
    try emitCurve(writer, transform, state, state.stack[0], state.stack[1], state.stack[2], state.stack[3], state.stack[4], zero_delta);
    try emitCurve(writer, transform, state, state.stack[5], zero_delta, state.stack[6], state.stack[7], state.stack[8], dy6);
    state.stack_len = stack_empty;
}

pub fn emitFlex1(writer: *std.Io.Writer, transform: Transform, state: *Type2State) CffError!void {
    if (!state.has_current_point or state.stack_len != flex1_operand_count) return font_parser.ParserError.InvalidTable;
    const dx_sum = state.stack[0] + state.stack[2] + state.stack[4] + state.stack[6] + state.stack[8];
    const dy_sum = state.stack[1] + state.stack[3] + state.stack[5] + state.stack[7] + state.stack[9];
    const dx6: i32 = if (absI32(dx_sum) > absI32(dy_sum)) state.stack[10] else -dx_sum;
    const dy6: i32 = if (absI32(dx_sum) > absI32(dy_sum)) -dy_sum else state.stack[10];

    try emitCurve(writer, transform, state, state.stack[0], state.stack[1], state.stack[2], state.stack[3], state.stack[4], state.stack[5]);
    try emitCurve(writer, transform, state, state.stack[6], state.stack[7], state.stack[8], state.stack[9], dx6, dy6);
    state.stack_len = stack_empty;
}

pub fn emitAlternatingCurve(writer: *std.Io.Writer, transform: Transform, state: *Type2State, starts_horizontal: bool) CffError!void {
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
            try emitCurve(writer, transform, state, dx1, zero_delta, dx2, dy2, dx3, dy3);
        } else {
            const dy1 = state.stack[index];
            const dx2 = state.stack[index + 1];
            const dy2 = state.stack[index + 2];
            const dx3 = state.stack[index + 3];
            index += alternating_curve_min_operands;
            const dy3: i32 = if (state.stack_len - index == optional_width_operand_count) state.stack[index] else zero_delta;
            if (state.stack_len - index == optional_width_operand_count) index += optional_width_operand_count;
            try emitCurve(writer, transform, state, zero_delta, dy1, dx2, dy2, dx3, dy3);
        }
        horizontal = !horizontal;
    }
}

fn absI32(value: i32) i32 {
    return if (value < 0) -value else value;
}

test "Type2 flex1 chooses final axis delta" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const writer = &output.writer;
    var state = Type2State{
        .stack = undefined,
        .stack_len = flex1_operand_count,
        .has_current_point = true,
    };
    @memcpy(state.stack[0..flex1_operand_count], &[_]i32{
        10, 5, 10, 5, 10, 5, 10, 5, 10, 5, 0,
    });

    try emitFlex1(writer, Transform{}, &state);

    try std.testing.expectEqualStrings("C 10.00 5.00 20.00 10.00 30.00 15.00 C 40.00 20.00 50.00 25.00 50.00 0.00 ", output.written());
    try std.testing.expectEqual(@as(usize, 0), state.stack_len);
}
