const std = @import("std");
const font_parser = @import("font_parser.zig");
const types = @import("cff_types.zig");

const Cff = types.Cff;
const CffError = types.CffError;
const Type2State = types.Type2State;

const stack_empty = 0;
const stack_single_operand = 1;
const stack_pair_operand_count = 2;
const ifelse_operand_count = 4;
const type2_true = 1;
const type2_false = 0;

pub fn executeAnd(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const rhs = pop(state);
    const lhs = pop(state);
    try push(state, if (lhs != type2_false and rhs != type2_false) type2_true else type2_false);
}

pub fn executeOr(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const rhs = pop(state);
    const lhs = pop(state);
    try push(state, if (lhs != type2_false or rhs != type2_false) type2_true else type2_false);
}

pub fn executeNot(state: *Type2State) CffError!void {
    if (state.stack_len < stack_single_operand) return font_parser.ParserError.InvalidTable;
    state.stack[state.stack_len - stack_single_operand] = if (state.stack[state.stack_len - stack_single_operand] == type2_false) type2_true else type2_false;
}

pub fn executeAbs(state: *Type2State) CffError!void {
    if (state.stack_len < stack_single_operand) return font_parser.ParserError.InvalidTable;
    const value = state.stack[state.stack_len - stack_single_operand];
    if (value == std.math.minInt(i32)) return font_parser.ParserError.InvalidTable;
    state.stack[state.stack_len - stack_single_operand] = if (value < type2_false) -value else value;
}

pub fn executeAdd(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const rhs = pop(state);
    const lhs = pop(state);
    try push(state, try checkedAdd(lhs, rhs));
}

pub fn executeSub(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const rhs = pop(state);
    const lhs = pop(state);
    try push(state, try checkedSub(lhs, rhs));
}

pub fn executeDiv(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const rhs = pop(state);
    const lhs = pop(state);
    if (rhs == type2_false) return font_parser.ParserError.InvalidTable;
    try push(state, @divTrunc(lhs, rhs));
}

pub fn executeNeg(state: *Type2State) CffError!void {
    if (state.stack_len < stack_single_operand) return font_parser.ParserError.InvalidTable;
    const value = state.stack[state.stack_len - stack_single_operand];
    if (value == std.math.minInt(i32)) return font_parser.ParserError.InvalidTable;
    state.stack[state.stack_len - stack_single_operand] = -value;
}

pub fn executeEq(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const rhs = pop(state);
    const lhs = pop(state);
    try push(state, if (lhs == rhs) type2_true else type2_false);
}

pub fn executeDrop(state: *Type2State) CffError!void {
    if (state.stack_len < stack_single_operand) return font_parser.ParserError.InvalidTable;
    _ = pop(state);
}

pub fn executePut(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const index = pop(state);
    const value = pop(state);
    if (index < type2_false or index >= state.transient.len) return font_parser.ParserError.InvalidTable;
    state.transient[@intCast(index)] = value;
}

pub fn executeGet(state: *Type2State) CffError!void {
    if (state.stack_len < stack_single_operand) return font_parser.ParserError.InvalidTable;
    const index = pop(state);
    if (index < type2_false or index >= state.transient.len) return font_parser.ParserError.InvalidTable;
    try push(state, state.transient[@intCast(index)]);
}

pub fn executeIfElse(state: *Type2State) CffError!void {
    if (state.stack_len < ifelse_operand_count) return font_parser.ParserError.InvalidTable;
    const value2 = pop(state);
    const value1 = pop(state);
    const s2 = pop(state);
    const s1 = pop(state);
    try push(state, if (value1 <= value2) s1 else s2);
}

pub fn executeRandom(state: *Type2State) CffError!void {
    try push(state, type2_true);
}

pub fn executeMul(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const rhs = pop(state);
    const lhs = pop(state);
    try push(state, try checkedMul(lhs, rhs));
}

pub fn executeSqrt(state: *Type2State) CffError!void {
    if (state.stack_len < stack_single_operand) return font_parser.ParserError.InvalidTable;
    const value = state.stack[state.stack_len - stack_single_operand];
    if (value < type2_false) return font_parser.ParserError.InvalidTable;
    state.stack[state.stack_len - stack_single_operand] = @intFromFloat(@sqrt(@as(f64, @floatFromInt(value))));
}

pub fn executeDup(state: *Type2State) CffError!void {
    if (state.stack_len < stack_single_operand) return font_parser.ParserError.InvalidTable;
    try push(state, state.stack[state.stack_len - stack_single_operand]);
}

pub fn executeExch(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const last = state.stack_len - stack_single_operand;
    const previous = state.stack_len - stack_pair_operand_count;
    const tmp = state.stack[last];
    state.stack[last] = state.stack[previous];
    state.stack[previous] = tmp;
}

pub fn executeIndex(state: *Type2State) CffError!void {
    if (state.stack_len < stack_single_operand) return font_parser.ParserError.InvalidTable;
    const raw_index = pop(state);
    const index: usize = if (raw_index < type2_false) stack_empty else @intCast(raw_index);
    if (index >= state.stack_len) return font_parser.ParserError.InvalidTable;
    try push(state, state.stack[state.stack_len - stack_single_operand - index]);
}

pub fn executeRoll(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const j = pop(state);
    const raw_n = pop(state);
    if (raw_n < type2_false) return font_parser.ParserError.InvalidTable;
    const n: usize = @intCast(raw_n);
    if (n == stack_empty) return;
    if (n > state.stack_len) return font_parser.ParserError.InvalidTable;

    const base = state.stack_len - n;
    const rotation = @mod(j, raw_n);
    var steps: usize = @intCast(rotation);
    while (steps > stack_empty) : (steps -= stack_single_operand) {
        const last = state.stack[state.stack_len - stack_single_operand];
        var index = state.stack_len - stack_single_operand;
        while (index > base) : (index -= 1) {
            state.stack[index] = state.stack[index - stack_single_operand];
        }
        state.stack[base] = last;
    }
}

pub fn executeCallOtherSubr(state: *Type2State) CffError!void {
    if (state.stack_len < stack_pair_operand_count) return font_parser.ParserError.InvalidTable;
    const arg_count_raw = pop(state);
    _ = pop(state);
    if (arg_count_raw < 0) return font_parser.ParserError.InvalidTable;
    const arg_count: usize = @intCast(arg_count_raw);
    if (state.stack_len < arg_count) return font_parser.ParserError.InvalidTable;
    if (state.othersubr_return_len + arg_count > state.othersubr_return_stack.len) return font_parser.ParserError.InvalidTable;

    var temp: [Cff.operand_stack_max]i32 = undefined;
    var index: usize = 0;
    while (index < arg_count) : (index += 1) {
        temp[index] = pop(state);
    }

    var reverse: usize = arg_count;
    while (reverse > 0) : (reverse -= 1) {
        state.othersubr_return_stack[state.othersubr_return_len] = temp[reverse - 1];
        state.othersubr_return_len += 1;
    }
}

pub fn executePop(state: *Type2State) CffError!void {
    if (state.othersubr_return_len == 0) return font_parser.ParserError.InvalidTable;
    const value = state.othersubr_return_stack[0];
    var index: usize = 1;
    while (index < state.othersubr_return_len) : (index += 1) {
        state.othersubr_return_stack[index - 1] = state.othersubr_return_stack[index];
    }
    state.othersubr_return_len -= 1;
    try push(state, value);
}

fn pop(state: *Type2State) i32 {
    state.stack_len -= 1;
    return state.stack[state.stack_len];
}

pub fn push(state: *Type2State, value: i32) CffError!void {
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

test "Type2 escaped stack manipulation operators" {
    var state = Type2State{};
    state.stack[0] = 10;
    state.stack[1] = 20;
    state.stack[2] = 30;
    state.stack_len = 3;

    try executeDup(&state);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 10, 20, 30, 30 }, state.stack[0..state.stack_len]);

    try executeExch(&state);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 10, 20, 30, 30 }, state.stack[0..state.stack_len]);

    try push(&state, 2);
    try executeIndex(&state);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 10, 20, 30, 30, 20 }, state.stack[0..state.stack_len]);

    try push(&state, 3);
    try push(&state, 1);
    try executeRoll(&state);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 10, 20, 20, 30, 30 }, state.stack[0..state.stack_len]);
}
