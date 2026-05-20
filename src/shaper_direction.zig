const std = @import("std");
const font_cmap = @import("font_cmap.zig");
const font_parser = @import("font_parser.zig");
const types = @import("shaper_types.zig");

const ShapeDirection = types.ShapeDirection;
const ShapedGlyph = types.ShapedGlyph;

const RunDirection = enum {
    rtl,
    ltr,
};

const UnicodeRange = struct {
    const arabic_rtl_start = 0x0590;
    const arabic_rtl_end = 0x08FF;
    const arabic_presentation_a_start = 0xFB1D;
    const arabic_presentation_a_end = 0xFDFF;
    const arabic_presentation_b_start = 0xFE70;
    const arabic_presentation_b_end = 0xFEFF;
    const extended_arabic_rtl_start = 0x10800;
    const extended_arabic_rtl_end = 0x10FFF;

    const latin_ltr_start = 0x0041;
    const latin_ltr_end = 0x02AF;
    const greek_cyrillic_ltr_start = 0x0370;
    const greek_cyrillic_ltr_end = 0x052F;
    const broad_ltr_start = 0x0900;
    const broad_ltr_end = 0x1FFF;
    const cjk_ltr_start = 0x3040;
    const cjk_ltr_end = 0xA7FF;
    const hangul_ltr_start = 0xAC00;
    const hangul_ltr_end = 0xD7AF;

    const ascii_digit_start = 0x0030;
    const ascii_digit_end = 0x0039;
    const arabic_indic_digit_start = 0x0660;
    const arabic_indic_digit_end = 0x0669;
    const eastern_arabic_indic_digit_start = 0x06F0;
    const eastern_arabic_indic_digit_end = 0x06F9;
};

pub fn resolveDirection(direction: ShapeDirection, glyphs: []const ShapedGlyph) ShapeDirection {
    if (direction != .auto) return direction;

    for (glyphs) |glyph| {
        if (strongDirectionForCodepoint(glyph.codepoint)) |strong_direction| return strong_direction;
    }

    return .ltr;
}

pub fn applyRtlVisualOrder(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    glyphs: []ShapedGlyph,
    total_advance: i32,
) !void {
    try applyRtlMirroring(face, glyphs);

    var visual_glyphs = std.ArrayList(ShapedGlyph).empty;
    defer visual_glyphs.deinit(allocator);

    try appendRtlRunVisualGroups(allocator, &visual_glyphs, glyphs, 0, total_advance);

    for (visual_glyphs.items, 0..) |glyph, out_index| {
        glyphs[out_index] = glyph;
    }
}

pub fn applyVerticalLayout(glyphs: []ShapedGlyph) void {
    var pen_y: i32 = 0;
    for (glyphs) |*glyph| {
        glyph.y_offset += pen_y;
        const vertical_advance = if (glyph.y_advance != 0) glyph.y_advance else @as(i32, glyph.advance_width);
        glyph.y_advance = vertical_advance;
        glyph.x_advance = 0;
        pen_y += vertical_advance;
    }
}

pub fn applyMixedDirectionVisualOrder(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    glyphs: []ShapedGlyph,
) !void {
    try applyMixedRtlMirroring(face, glyphs);

    var visual_glyphs = std.ArrayList(ShapedGlyph).empty;
    defer visual_glyphs.deinit(allocator);

    var run_start: usize = 0;
    var run_direction: ShapeDirection = .ltr;
    var index: usize = 0;
    while (index < glyphs.len) : (index += 1) {
        if (strongDirectionForCodepoint(glyphs[index].codepoint)) |direction| {
            if (index == run_start) {
                run_direction = direction;
                continue;
            }
            if (direction != run_direction) {
                try appendVisualRun(allocator, &visual_glyphs, glyphs[run_start..index], run_direction);
                run_start = index;
                run_direction = direction;
            }
        }
    }

    try appendVisualRun(allocator, &visual_glyphs, glyphs[run_start..], run_direction);

    for (visual_glyphs.items, 0..) |glyph, out_index| {
        glyphs[out_index] = glyph;
    }
}

fn applyMixedRtlMirroring(face: font_parser.Face, glyphs: []ShapedGlyph) font_parser.ParserError!void {
    var run_start: usize = 0;
    var run_direction: ShapeDirection = .ltr;
    var index: usize = 0;
    while (index < glyphs.len) : (index += 1) {
        if (strongDirectionForCodepoint(glyphs[index].codepoint)) |direction| {
            if (index == run_start) {
                run_direction = direction;
                continue;
            }
            if (direction != run_direction) {
                if (run_direction == .rtl) try applyRtlMirroring(face, glyphs[run_start..index]);
                run_start = index;
                run_direction = direction;
            }
        }
    }

    if (run_direction == .rtl) try applyRtlMirroring(face, glyphs[run_start..]);
}

fn applyRtlMirroring(face: font_parser.Face, glyphs: []ShapedGlyph) font_parser.ParserError!void {
    for (glyphs) |*glyph| {
        const mirrored = mirroredCodepoint(glyph.codepoint) orelse continue;
        const info = try face.getGlyphInfo(mirrored);
        if (info.id == 0) continue;
        glyph.codepoint = mirrored;
        glyph.glyph_id = info.id;
    }
}

fn mirroredCodepoint(codepoint: u21) ?u21 {
    return switch (codepoint) {
        '(' => ')',
        ')' => '(',
        '[' => ']',
        ']' => '[',
        '{' => '}',
        '}' => '{',
        '<' => '>',
        '>' => '<',
        0x00AB => 0x00BB,
        0x00BB => 0x00AB,
        0x0F3A => 0x0F3B,
        0x0F3B => 0x0F3A,
        0x0F3C => 0x0F3D,
        0x0F3D => 0x0F3C,
        0x169B => 0x169C,
        0x169C => 0x169B,
        0x2045 => 0x2046,
        0x2046 => 0x2045,
        0x207D => 0x207E,
        0x207E => 0x207D,
        0x208D => 0x208E,
        0x208E => 0x208D,
        0x2308 => 0x2309,
        0x2309 => 0x2308,
        0x230A => 0x230B,
        0x230B => 0x230A,
        0x2329 => 0x232A,
        0x232A => 0x2329,
        0x2768 => 0x2769,
        0x2769 => 0x2768,
        0x276A => 0x276B,
        0x276B => 0x276A,
        0x276C => 0x276D,
        0x276D => 0x276C,
        0x276E => 0x276F,
        0x276F => 0x276E,
        0x2770 => 0x2771,
        0x2771 => 0x2770,
        0x2772 => 0x2773,
        0x2773 => 0x2772,
        0x2774 => 0x2775,
        0x2775 => 0x2774,
        0x27C5 => 0x27C6,
        0x27C6 => 0x27C5,
        0x27E6 => 0x27E7,
        0x27E7 => 0x27E6,
        0x27E8 => 0x27E9,
        0x27E9 => 0x27E8,
        0x27EA => 0x27EB,
        0x27EB => 0x27EA,
        0x27EC => 0x27ED,
        0x27ED => 0x27EC,
        0x27EE => 0x27EF,
        0x27EF => 0x27EE,
        0x2983 => 0x2984,
        0x2984 => 0x2983,
        0x2985 => 0x2986,
        0x2986 => 0x2985,
        0x2987 => 0x2988,
        0x2988 => 0x2987,
        0x2989 => 0x298A,
        0x298A => 0x2989,
        0x298B => 0x298C,
        0x298C => 0x298B,
        0x298D => 0x2990,
        0x298E => 0x298F,
        0x298F => 0x298E,
        0x2990 => 0x298D,
        0x2991 => 0x2992,
        0x2992 => 0x2991,
        0x2993 => 0x2994,
        0x2994 => 0x2993,
        0x2995 => 0x2996,
        0x2996 => 0x2995,
        0x2997 => 0x2998,
        0x2998 => 0x2997,
        0x29D8 => 0x29D9,
        0x29D9 => 0x29D8,
        0x29DA => 0x29DB,
        0x29DB => 0x29DA,
        0x29FC => 0x29FD,
        0x29FD => 0x29FC,
        0x2E22 => 0x2E23,
        0x2E23 => 0x2E22,
        0x2E24 => 0x2E25,
        0x2E25 => 0x2E24,
        0x2E26 => 0x2E27,
        0x2E27 => 0x2E26,
        0x2E28 => 0x2E29,
        0x2E29 => 0x2E28,
        0x3008 => 0x3009,
        0x3009 => 0x3008,
        0x300A => 0x300B,
        0x300B => 0x300A,
        0x300C => 0x300D,
        0x300D => 0x300C,
        0x300E => 0x300F,
        0x300F => 0x300E,
        0x3010 => 0x3011,
        0x3011 => 0x3010,
        0x3014 => 0x3015,
        0x3015 => 0x3014,
        0x3016 => 0x3017,
        0x3017 => 0x3016,
        0x3018 => 0x3019,
        0x3019 => 0x3018,
        0x301A => 0x301B,
        0x301B => 0x301A,
        else => null,
    };
}

fn appendVisualRun(
    allocator: std.mem.Allocator,
    visual_glyphs: *std.ArrayList(ShapedGlyph),
    run: []const ShapedGlyph,
    run_direction: ShapeDirection,
) !void {
    switch (run_direction) {
        .ltr, .auto, .ttb => {
            for (run) |glyph| {
                try visual_glyphs.append(allocator, glyph);
            }
        },
        .rtl => {
            try appendRtlRunVisualGroups(allocator, visual_glyphs, run, run[0].x_offset, runEnd(run));
        },
    }
}

fn appendRtlRunVisualGroups(
    allocator: std.mem.Allocator,
    visual_glyphs: *std.ArrayList(ShapedGlyph),
    run: []const ShapedGlyph,
    run_start: i32,
    run_end_value: i32,
) !void {
    if (run.len == 0) return;

    var groups = try collectDirectionalGroups(allocator, run);
    defer groups.deinit(allocator);

    var group_index = groups.items.len;
    while (group_index > 0) : (group_index -= 1) {
        const group = groups.items[group_index - 1];
        const group_start = run[group.start].x_offset;
        const group_end_value = run[group.end - 1].x_offset + run[group.end - 1].x_advance;
        const visual_group_start = run_start + (run_end_value - group_end_value);

        switch (group.direction) {
            .ltr => {
                for (run[group.start..group.end]) |glyph| {
                    var visual_glyph = glyph;
                    visual_glyph.x_offset = visual_group_start + (glyph.x_offset - group_start);
                    try visual_glyphs.append(allocator, visual_glyph);
                }
            },
            .rtl => {
                var glyph_index = group.end;
                while (glyph_index > group.start) : (glyph_index -= 1) {
                    const glyph = run[glyph_index - 1];
                    var visual_glyph = glyph;
                    visual_glyph.x_offset = visual_group_start + (group_end_value - (glyph.x_offset + glyph.x_advance));
                    try visual_glyphs.append(allocator, visual_glyph);
                }
            },
        }
    }
}

const DirectionalGroup = struct {
    start: usize,
    end: usize,
    direction: RunDirection,
};

fn collectDirectionalGroups(
    allocator: std.mem.Allocator,
    run: []const ShapedGlyph,
) !std.ArrayList(DirectionalGroup) {
    var groups = std.ArrayList(DirectionalGroup).empty;
    errdefer groups.deinit(allocator);

    var index: usize = 0;
    while (index < run.len) {
        const direction = runDirectionAt(run, index);
        const start = index;
        index += 1;
        while (index < run.len) : (index += 1) {
            const next_direction = runDirectionAt(run, index);
            if (next_direction != direction) break;
        }
        try groups.append(allocator, .{ .start = start, .end = index, .direction = direction });
    }

    return groups;
}

fn runDirectionAt(run: []const ShapedGlyph, index: usize) RunDirection {
    const codepoint = run[index].codepoint;
    if (isStrongLtrCodepoint(codepoint)) return .ltr;
    if (isWeakLtrCodepoint(codepoint)) return .ltr;
    if (isNumericSeparatorCodepoint(codepoint) and hasNumericBefore(run, index) and hasNumericAfter(run, index)) return .ltr;
    if (isNumericPrefixCodepoint(codepoint) and hasNumericAfter(run, index)) return .ltr;
    if (isNumericSuffixCodepoint(codepoint) and hasNumericBefore(run, index)) return .ltr;
    if (isLtrPhraseConnectorCodepoint(codepoint) and hasLtrBefore(run, index) and hasLtrAfter(run, index)) return .ltr;
    return .rtl;
}

fn runEnd(run: []const ShapedGlyph) i32 {
    var end = run[0].x_offset + run[0].x_advance;
    for (run[1..]) |glyph| {
        end = @max(end, glyph.x_offset + glyph.x_advance);
    }
    return end;
}

pub fn hasMixedStrongDirections(glyphs: []const ShapedGlyph) bool {
    var saw_ltr = false;
    var saw_rtl = false;

    for (glyphs) |glyph| {
        if (strongDirectionForCodepoint(glyph.codepoint)) |direction| {
            switch (direction) {
                .ltr => saw_ltr = true,
                .rtl => saw_rtl = true,
                .ttb => {},
                .auto => {},
            }
            if (saw_ltr and saw_rtl) return true;
        }
    }

    return false;
}

pub fn computeTotalAdvance(glyphs: []const ShapedGlyph, direction: ShapeDirection) i32 {
    var total_advance: i32 = 0;
    switch (direction) {
        .ttb => {
            for (glyphs) |glyph| {
                total_advance = @max(total_advance, glyph.y_offset + glyph.y_advance);
            }
        },
        .ltr, .rtl, .auto => {
            for (glyphs) |glyph| {
                total_advance = @max(total_advance, glyph.x_offset + glyph.x_advance);
            }
        },
    }
    return total_advance;
}

fn strongDirectionForCodepoint(codepoint: u21) ?ShapeDirection {
    if (isStrongRtlCodepoint(codepoint)) return .rtl;
    if (isStrongLtrCodepoint(codepoint)) return .ltr;
    return null;
}

fn isStrongRtlCodepoint(codepoint: u21) bool {
    return isInRange(codepoint, UnicodeRange.arabic_rtl_start, UnicodeRange.arabic_rtl_end) or
        isInRange(codepoint, UnicodeRange.arabic_presentation_a_start, UnicodeRange.arabic_presentation_a_end) or
        isInRange(codepoint, UnicodeRange.arabic_presentation_b_start, UnicodeRange.arabic_presentation_b_end) or
        isInRange(codepoint, UnicodeRange.extended_arabic_rtl_start, UnicodeRange.extended_arabic_rtl_end);
}

fn isStrongLtrCodepoint(codepoint: u21) bool {
    return isInRange(codepoint, UnicodeRange.latin_ltr_start, UnicodeRange.latin_ltr_end) or
        isInRange(codepoint, UnicodeRange.greek_cyrillic_ltr_start, UnicodeRange.greek_cyrillic_ltr_end) or
        isInRange(codepoint, UnicodeRange.broad_ltr_start, UnicodeRange.broad_ltr_end) or
        isInRange(codepoint, UnicodeRange.cjk_ltr_start, UnicodeRange.cjk_ltr_end) or
        isInRange(codepoint, UnicodeRange.hangul_ltr_start, UnicodeRange.hangul_ltr_end);
}

fn isWeakLtrCodepoint(codepoint: u21) bool {
    return isInRange(codepoint, UnicodeRange.ascii_digit_start, UnicodeRange.ascii_digit_end) or
        isInRange(codepoint, UnicodeRange.arabic_indic_digit_start, UnicodeRange.arabic_indic_digit_end) or
        isInRange(codepoint, UnicodeRange.eastern_arabic_indic_digit_start, UnicodeRange.eastern_arabic_indic_digit_end);
}

fn isNumericSeparatorCodepoint(codepoint: u21) bool {
    return codepoint == '.' or codepoint == ',' or codepoint == ':' or codepoint == '/' or
        codepoint == '-' or codepoint == 0x066B or codepoint == 0x066C;
}

fn isNumericPrefixCodepoint(codepoint: u21) bool {
    return codepoint == '+' or codepoint == '-' or codepoint == 0x2212;
}

fn isNumericSuffixCodepoint(codepoint: u21) bool {
    return codepoint == '%' or codepoint == 0x066A;
}

fn isLtrPhraseConnectorCodepoint(codepoint: u21) bool {
    return codepoint == ' ' or codepoint == 0x00A0 or codepoint == '-' or codepoint == '_' or
        codepoint == '\'' or codepoint == 0x2019 or codepoint == '.' or codepoint == ',' or
        codepoint == ':' or codepoint == '/' or codepoint == '&';
}

fn hasNumericBefore(run: []const ShapedGlyph, index: usize) bool {
    return index > 0 and isWeakLtrCodepoint(run[index - 1].codepoint);
}

fn hasNumericAfter(run: []const ShapedGlyph, index: usize) bool {
    return index + 1 < run.len and isWeakLtrCodepoint(run[index + 1].codepoint);
}

fn hasLtrBefore(run: []const ShapedGlyph, index: usize) bool {
    var cursor = index;
    while (cursor > 0) {
        cursor -= 1;
        const codepoint = run[cursor].codepoint;
        if (isStrongLtrCodepoint(codepoint) or isWeakLtrCodepoint(codepoint)) return true;
        if (!isLtrPhraseConnectorCodepoint(codepoint)) return false;
    }
    return false;
}

fn hasLtrAfter(run: []const ShapedGlyph, index: usize) bool {
    var cursor = index + 1;
    while (cursor < run.len) : (cursor += 1) {
        const codepoint = run[cursor].codepoint;
        if (isStrongLtrCodepoint(codepoint) or isWeakLtrCodepoint(codepoint)) return true;
        if (!isLtrPhraseConnectorCodepoint(codepoint)) return false;
    }
    return false;
}

fn isInRange(codepoint: u21, start: u21, end: u21) bool {
    return codepoint >= start and codepoint <= end;
}

test "automatic direction uses first strong direction" {
    const rtl = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 2, .cluster = 1, .x_offset = 100, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
    };
    const rtl_first_mixed = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'A', .glyph_id = 2, .cluster = 1, .x_offset = 100, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
    };
    const ltr_first_mixed = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D0, .glyph_id = 2, .cluster = 1, .x_offset = 80, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };

    try std.testing.expectEqual(ShapeDirection.rtl, resolveDirection(.auto, &rtl));
    try std.testing.expectEqual(ShapeDirection.rtl, resolveDirection(.auto, &rtl_first_mixed));
    try std.testing.expectEqual(ShapeDirection.ltr, resolveDirection(.auto, &ltr_first_mixed));
}

test "RTL visual order mirrors horizontal positions" {
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 2, .cluster = 1, .x_offset = 100, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
    };

    const face: font_parser.Face = undefined;
    try applyRtlVisualOrder(std.testing.allocator, face, &glyphs, 180);

    try std.testing.expectEqual(@as(u16, 2), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 1), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(i32, 80), glyphs[1].x_offset);
}

test "RTL visual order preserves numeric run order" {
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 2, .cluster = 1, .x_offset = 70, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = '1', .glyph_id = 3, .cluster = 2, .x_offset = 140, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = '2', .glyph_id = 4, .cluster = 3, .x_offset = 190, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D2, .glyph_id = 5, .cluster = 4, .x_offset = 240, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
    };

    const face: font_parser.Face = undefined;
    try applyRtlVisualOrder(std.testing.allocator, face, &glyphs, 310);

    try std.testing.expectEqual(@as(u16, 5), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 3), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(i32, 70), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(u16, 4), glyphs[2].glyph_id);
    try std.testing.expectEqual(@as(i32, 120), glyphs[2].x_offset);
    try std.testing.expectEqual(@as(u16, 2), glyphs[3].glyph_id);
    try std.testing.expectEqual(@as(i32, 170), glyphs[3].x_offset);
    try std.testing.expectEqual(@as(u16, 1), glyphs[4].glyph_id);
    try std.testing.expectEqual(@as(i32, 240), glyphs[4].x_offset);
}

test "RTL visual order preserves numeric separators inside numeric runs" {
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = '1', .glyph_id = 2, .cluster = 1, .x_offset = 70, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = ',', .glyph_id = 3, .cluster = 2, .x_offset = 120, .y_offset = 0, .x_advance = 20, .y_advance = 0, .advance_width = 20, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = '2', .glyph_id = 4, .cluster = 3, .x_offset = 140, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = '.', .glyph_id = 5, .cluster = 4, .x_offset = 190, .y_offset = 0, .x_advance = 20, .y_advance = 0, .advance_width = 20, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = '3', .glyph_id = 6, .cluster = 5, .x_offset = 210, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 7, .cluster = 6, .x_offset = 260, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
    };

    const face: font_parser.Face = undefined;
    try applyRtlVisualOrder(std.testing.allocator, face, &glyphs, 330);

    try std.testing.expectEqual(@as(u16, 7), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 2), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(i32, 70), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(u16, 3), glyphs[2].glyph_id);
    try std.testing.expectEqual(@as(i32, 120), glyphs[2].x_offset);
    try std.testing.expectEqual(@as(u16, 4), glyphs[3].glyph_id);
    try std.testing.expectEqual(@as(i32, 140), glyphs[3].x_offset);
    try std.testing.expectEqual(@as(u16, 5), glyphs[4].glyph_id);
    try std.testing.expectEqual(@as(i32, 190), glyphs[4].x_offset);
    try std.testing.expectEqual(@as(u16, 6), glyphs[5].glyph_id);
    try std.testing.expectEqual(@as(i32, 210), glyphs[5].x_offset);
    try std.testing.expectEqual(@as(u16, 1), glyphs[6].glyph_id);
    try std.testing.expectEqual(@as(i32, 260), glyphs[6].x_offset);
}

test "RTL visual order preserves LTR word order inside RTL paragraph" {
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'A', .glyph_id = 2, .cluster = 1, .x_offset = 70, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'B', .glyph_id = 3, .cluster = 2, .x_offset = 120, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 4, .cluster = 3, .x_offset = 170, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
    };

    const face: font_parser.Face = undefined;
    try applyRtlVisualOrder(std.testing.allocator, face, &glyphs, 240);

    try std.testing.expectEqual(@as(u16, 4), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 2), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(i32, 70), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(u16, 3), glyphs[2].glyph_id);
    try std.testing.expectEqual(@as(i32, 120), glyphs[2].x_offset);
    try std.testing.expectEqual(@as(u16, 1), glyphs[3].glyph_id);
    try std.testing.expectEqual(@as(i32, 170), glyphs[3].x_offset);
}

test "RTL visual order preserves LTR phrase connectors inside RTL paragraph" {
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'A', .glyph_id = 2, .cluster = 1, .x_offset = 70, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = '-', .glyph_id = 3, .cluster = 2, .x_offset = 120, .y_offset = 0, .x_advance = 20, .y_advance = 0, .advance_width = 20, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'B', .glyph_id = 4, .cluster = 3, .x_offset = 140, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = ' ', .glyph_id = 5, .cluster = 4, .x_offset = 190, .y_offset = 0, .x_advance = 20, .y_advance = 0, .advance_width = 20, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'C', .glyph_id = 6, .cluster = 5, .x_offset = 210, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 7, .cluster = 6, .x_offset = 260, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
    };

    const face: font_parser.Face = undefined;
    try applyRtlVisualOrder(std.testing.allocator, face, &glyphs, 330);

    try std.testing.expectEqual(@as(u16, 7), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 2), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(i32, 70), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(u16, 3), glyphs[2].glyph_id);
    try std.testing.expectEqual(@as(i32, 120), glyphs[2].x_offset);
    try std.testing.expectEqual(@as(u16, 4), glyphs[3].glyph_id);
    try std.testing.expectEqual(@as(i32, 140), glyphs[3].x_offset);
    try std.testing.expectEqual(@as(u16, 5), glyphs[4].glyph_id);
    try std.testing.expectEqual(@as(i32, 190), glyphs[4].x_offset);
    try std.testing.expectEqual(@as(u16, 6), glyphs[5].glyph_id);
    try std.testing.expectEqual(@as(i32, 210), glyphs[5].x_offset);
    try std.testing.expectEqual(@as(u16, 1), glyphs[6].glyph_id);
    try std.testing.expectEqual(@as(i32, 260), glyphs[6].x_offset);
}

test "RTL visual order treats standalone neutral punctuation as RTL run content" {
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = '.', .glyph_id = 2, .cluster = 1, .x_offset = 70, .y_offset = 0, .x_advance = 20, .y_advance = 0, .advance_width = 20, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 3, .cluster = 2, .x_offset = 90, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
    };

    const face: font_parser.Face = undefined;
    try applyRtlVisualOrder(std.testing.allocator, face, &glyphs, 160);

    try std.testing.expectEqual(@as(u16, 3), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 2), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(i32, 70), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(u16, 1), glyphs[2].glyph_id);
    try std.testing.expectEqual(@as(i32, 90), glyphs[2].x_offset);
}

test "RTL visual order mirrors paired punctuation glyphs" {
    var data = [_]u8{0} ** 92;
    writeU16(&data, 0, 0);
    writeU16(&data, 2, 1);
    writeU16(&data, 4, 3);
    writeU16(&data, 6, 10);
    writeU32(&data, 8, 12);
    writeU16(&data, 12, 12);
    writeU16(&data, 14, 0);
    writeU32(&data, 16, 28);
    writeU32(&data, 20, 0);
    writeU32(&data, 24, 1);
    writeU32(&data, 28, '(');
    writeU32(&data, 32, ')');
    writeU32(&data, 36, 10);
    const hmtx_offset = 44;
    var metric_index: usize = 0;
    while (metric_index < 12) : (metric_index += 1) {
        writeU16(&data, hmtx_offset + metric_index * 4, 40);
        writeI16(&data, hmtx_offset + metric_index * 4 + 2, 0);
    }
    const tables = [_]font_parser.TableMetadata{
        .{ .tag = "cmap".*, .offset = 0, .length = 44 },
        .{ .tag = "hmtx".*, .offset = hmtx_offset, .length = 48 },
    };
    const face = font_parser.Face{
        .data = &data,
        .units_per_em = 1000,
        .num_glyphs = 12,
        .tables = &tables,
        .number_of_h_metrics = 12,
        .number_of_v_metrics = null,
        .vorg_default_vert_origin_y = null,
        .vorg = null,
        .cmap = font_cmap.Selection{ .offset = 12, .format = 12 },
    };
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = '(', .glyph_id = 10, .cluster = 1, .x_offset = 70, .y_offset = 0, .x_advance = 40, .y_advance = 0, .advance_width = 40, .lsb = 0, .kern_adjustment = 0 },
    };

    try applyRtlVisualOrder(std.testing.allocator, face, &glyphs, 110);

    try std.testing.expectEqual(@as(u21, ')'), glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u16, 11), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u21, 0x05D0), glyphs[1].codepoint);
    try std.testing.expectEqual(@as(i32, 40), glyphs[1].x_offset);
}

test "RTL mirroring covers extended Unicode paired brackets" {
    try std.testing.expectEqual(@as(?u21, 0x27E9), mirroredCodepoint(0x27E8));
    try std.testing.expectEqual(@as(?u21, 0x27E8), mirroredCodepoint(0x27E9));
    try std.testing.expectEqual(@as(?u21, 0x3009), mirroredCodepoint(0x3008));
    try std.testing.expectEqual(@as(?u21, 0x3008), mirroredCodepoint(0x3009));
    try std.testing.expectEqual(@as(?u21, 0x2984), mirroredCodepoint(0x2983));
    try std.testing.expectEqual(@as(?u21, null), mirroredCodepoint('A'));
}

test "RTL visual order keeps punctuation when mirrored glyph is missing" {
    var data = [_]u8{0} ** 88;
    writeU16(&data, 0, 0);
    writeU16(&data, 2, 1);
    writeU16(&data, 4, 3);
    writeU16(&data, 6, 10);
    writeU32(&data, 8, 12);
    writeU16(&data, 12, 12);
    writeU16(&data, 14, 0);
    writeU32(&data, 16, 28);
    writeU32(&data, 20, 0);
    writeU32(&data, 24, 1);
    writeU32(&data, 28, '(');
    writeU32(&data, 32, '(');
    writeU32(&data, 36, 10);
    const hmtx_offset = 44;
    var metric_index: usize = 0;
    while (metric_index < 11) : (metric_index += 1) {
        writeU16(&data, hmtx_offset + metric_index * 4, 40);
        writeI16(&data, hmtx_offset + metric_index * 4 + 2, 0);
    }
    const tables = [_]font_parser.TableMetadata{
        .{ .tag = "cmap".*, .offset = 0, .length = 44 },
        .{ .tag = "hmtx".*, .offset = hmtx_offset, .length = 44 },
    };
    const face = font_parser.Face{
        .data = &data,
        .units_per_em = 1000,
        .num_glyphs = 11,
        .tables = &tables,
        .number_of_h_metrics = 11,
        .number_of_v_metrics = null,
        .vorg_default_vert_origin_y = null,
        .vorg = null,
        .cmap = font_cmap.Selection{ .offset = 12, .format = 12 },
    };
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = '(', .glyph_id = 10, .cluster = 1, .x_offset = 70, .y_offset = 0, .x_advance = 40, .y_advance = 0, .advance_width = 40, .lsb = 0, .kern_adjustment = 0 },
    };

    try applyRtlVisualOrder(std.testing.allocator, face, &glyphs, 110);

    try std.testing.expectEqual(@as(u21, '('), glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u16, 10), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u21, 0x05D0), glyphs[1].codepoint);
    try std.testing.expectEqual(@as(i32, 40), glyphs[1].x_offset);
}

test "mixed direction visual order reverses RTL runs inside LTR text" {
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D0, .glyph_id = 2, .cluster = 1, .x_offset = 80, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 3, .cluster = 2, .x_offset = 150, .y_offset = 0, .x_advance = 90, .y_advance = 0, .advance_width = 90, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'B', .glyph_id = 4, .cluster = 3, .x_offset = 240, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
    };

    const face: font_parser.Face = undefined;
    try applyMixedDirectionVisualOrder(std.testing.allocator, face, &glyphs);

    try std.testing.expectEqual(@as(u16, 1), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 3), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(i32, 80), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(u16, 2), glyphs[2].glyph_id);
    try std.testing.expectEqual(@as(i32, 170), glyphs[2].x_offset);
    try std.testing.expectEqual(@as(u16, 4), glyphs[3].glyph_id);
    try std.testing.expectEqual(@as(i32, 240), glyphs[3].x_offset);
}

fn writeU16(data: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, data[offset..][0..2], value, .big);
}

fn writeI16(data: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, data[offset..][0..2], value, .big);
}

fn writeU32(data: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, data[offset..][0..4], value, .big);
}

test "vertical layout stacks glyphs downward" {
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 12, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'B', .glyph_id = 2, .cluster = 1, .x_offset = 18, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
    };

    applyVerticalLayout(&glyphs);

    try std.testing.expectEqual(@as(i32, 0), glyphs[0].y_offset);
    try std.testing.expectEqual(@as(i32, 80), glyphs[0].y_advance);
    try std.testing.expectEqual(@as(i32, 80), glyphs[1].y_offset);
    try std.testing.expectEqual(@as(i32, 70), glyphs[1].y_advance);
    try std.testing.expectEqual(@as(i32, 150), computeTotalAdvance(&glyphs, .ttb));
}
