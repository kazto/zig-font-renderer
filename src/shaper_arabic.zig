const std = @import("std");
const types = @import("shaper_types.zig");

const ShapedGlyph = types.ShapedGlyph;

pub const JoiningForm = enum {
    none,
    isolated,
    initial,
    medial,
    final,
};

const JoiningType = enum {
    non_joining,
    right_joining,
    dual_joining,
    transparent,
};

pub fn computeJoiningForms(allocator: std.mem.Allocator, glyphs: []const ShapedGlyph) std.mem.Allocator.Error![]JoiningForm {
    const forms = try allocator.alloc(JoiningForm, glyphs.len);
    errdefer allocator.free(forms);

    for (glyphs, 0..) |item, index| {
        const current_type = joiningType(item.codepoint);
        if (current_type == .non_joining or current_type == .transparent) {
            forms[index] = .none;
            continue;
        }

        const joins_prev = canJoinWithPrevious(glyphs, index);
        const joins_next = canJoinWithNext(glyphs, index);
        forms[index] = if (joins_prev and joins_next)
            .medial
        else if (joins_prev)
            .final
        else if (joins_next)
            .initial
        else
            .isolated;
    }

    return forms;
}

fn canJoinWithPrevious(glyphs: []const ShapedGlyph, index: usize) bool {
    if (!canJoinPrevious(joiningType(glyphs[index].codepoint))) return false;

    var cursor = index;
    while (cursor > 0) {
        cursor -= 1;
        const previous_type = joiningType(glyphs[cursor].codepoint);
        if (previous_type == .transparent) continue;
        return canJoinNext(previous_type);
    }

    return false;
}

fn canJoinWithNext(glyphs: []const ShapedGlyph, index: usize) bool {
    if (!canJoinNext(joiningType(glyphs[index].codepoint))) return false;

    var cursor = index + 1;
    while (cursor < glyphs.len) : (cursor += 1) {
        const next_type = joiningType(glyphs[cursor].codepoint);
        if (next_type == .transparent) continue;
        return canJoinPrevious(next_type);
    }

    return false;
}

fn canJoinPrevious(joining_type: JoiningType) bool {
    return joining_type == .dual_joining or joining_type == .right_joining;
}

fn canJoinNext(joining_type: JoiningType) bool {
    return joining_type == .dual_joining;
}

fn joiningType(codepoint: u21) JoiningType {
    if (isTransparentArabicMark(codepoint)) return .transparent;
    if (isRightJoiningArabic(codepoint)) return .right_joining;
    if (isDualJoiningArabic(codepoint)) return .dual_joining;
    return .non_joining;
}

fn isTransparentArabicMark(codepoint: u21) bool {
    return isInRange(codepoint, 0x0610, 0x061A) or
        isInRange(codepoint, 0x064B, 0x065F) or
        codepoint == 0x0670 or
        isInRange(codepoint, 0x06D6, 0x06DC) or
        isInRange(codepoint, 0x06DF, 0x06E4) or
        isInRange(codepoint, 0x06E7, 0x06E8) or
        isInRange(codepoint, 0x06EA, 0x06ED) or
        isInRange(codepoint, 0x08D3, 0x08FF);
}

fn isRightJoiningArabic(codepoint: u21) bool {
    return codepoint == 0x0622 or codepoint == 0x0623 or codepoint == 0x0624 or
        codepoint == 0x0625 or codepoint == 0x0627 or codepoint == 0x0629 or
        codepoint == 0x062F or codepoint == 0x0630 or codepoint == 0x0631 or
        codepoint == 0x0632 or codepoint == 0x0648 or codepoint == 0x0671 or
        codepoint == 0x0672 or codepoint == 0x0673 or codepoint == 0x0675 or
        codepoint == 0x0676 or codepoint == 0x0677 or codepoint == 0x0688 or
        isInRange(codepoint, 0x0689, 0x0699) or
        isInRange(codepoint, 0x06C0, 0x06C4) or
        isInRange(codepoint, 0x06C6, 0x06CB) or
        codepoint == 0x06CD or codepoint == 0x06CF or
        isInRange(codepoint, 0x06D2, 0x06D3) or
        codepoint == 0x06EE or codepoint == 0x06EF;
}

fn isDualJoiningArabic(codepoint: u21) bool {
    return isInRange(codepoint, 0x0620, 0x0621) or
        codepoint == 0x0626 or
        isInRange(codepoint, 0x0628, 0x062C) or
        isInRange(codepoint, 0x0633, 0x063A) or
        isInRange(codepoint, 0x0641, 0x0647) or
        isInRange(codepoint, 0x0649, 0x064A) or
        isInRange(codepoint, 0x066E, 0x066F) or
        isInRange(codepoint, 0x0678, 0x0687) or
        isInRange(codepoint, 0x069A, 0x06BF) or
        codepoint == 0x06CC or codepoint == 0x06CE or
        codepoint == 0x06D0 or codepoint == 0x06D1 or
        isInRange(codepoint, 0x06FA, 0x06FC) or
        codepoint == 0x06FF or
        isInRange(codepoint, 0x0750, 0x077F) or
        isInRange(codepoint, 0x08A0, 0x08B4) or
        isInRange(codepoint, 0x08B6, 0x08C7);
}

fn isInRange(codepoint: u21, start: u21, end: u21) bool {
    return codepoint >= start and codepoint <= end;
}

fn glyph(codepoint: u21) ShapedGlyph {
    return .{ .codepoint = codepoint, .glyph_id = @intCast(codepoint & 0xffff), .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 };
}

test "Arabic joining forms classify isolated initial medial and final" {
    const glyphs = [_]ShapedGlyph{
        glyph(0x062F), // isolated right-joining dal
        glyph(0x0645), // initial dual-joining meem
        glyph(0x062F), // final right-joining dal
        glyph(0x0645), // initial dual-joining meem
        glyph(0x0645), // medial dual-joining meem
        glyph(0x0627), // final right-joining alef
    };
    const forms = try computeJoiningForms(std.testing.allocator, &glyphs);
    defer std.testing.allocator.free(forms);

    try std.testing.expectEqual(JoiningForm.isolated, forms[0]);
    try std.testing.expectEqual(JoiningForm.initial, forms[1]);
    try std.testing.expectEqual(JoiningForm.final, forms[2]);
    try std.testing.expectEqual(JoiningForm.initial, forms[3]);
    try std.testing.expectEqual(JoiningForm.medial, forms[4]);
    try std.testing.expectEqual(JoiningForm.final, forms[5]);
}

test "Arabic transparent marks do not break joining" {
    const glyphs = [_]ShapedGlyph{
        glyph(0x0645),
        glyph(0x0651),
        glyph(0x0645),
    };
    const forms = try computeJoiningForms(std.testing.allocator, &glyphs);
    defer std.testing.allocator.free(forms);

    try std.testing.expectEqual(JoiningForm.initial, forms[0]);
    try std.testing.expectEqual(JoiningForm.none, forms[1]);
    try std.testing.expectEqual(JoiningForm.final, forms[2]);
}
