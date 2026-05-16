const std = @import("std");
const types = @import("shaper_types.zig");

const ShapeDirection = types.ShapeDirection;
const ShapedGlyph = types.ShapedGlyph;

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
};

pub fn resolveDirection(direction: ShapeDirection, glyphs: []const ShapedGlyph) ShapeDirection {
    if (direction != .auto) return direction;

    var saw_rtl = false;
    for (glyphs) |glyph| {
        if (isStrongRtlCodepoint(glyph.codepoint)) {
            saw_rtl = true;
        } else if (isStrongLtrCodepoint(glyph.codepoint)) {
            return .ltr;
        }
    }

    return if (saw_rtl) .rtl else .ltr;
}

pub fn applyRtlVisualOrder(glyphs: []ShapedGlyph, total_advance: i32) void {
    for (glyphs) |*glyph| {
        glyph.x_offset = total_advance - (glyph.x_offset + glyph.x_advance);
    }
    std.mem.reverse(ShapedGlyph, glyphs);
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
    glyphs: []ShapedGlyph,
) !void {
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
            const run_start = run[0].x_offset;
            var run_end = run[0].x_offset + run[0].x_advance;
            for (run[1..]) |glyph| {
                run_end = @max(run_end, glyph.x_offset + glyph.x_advance);
            }

            var index: usize = run.len;
            while (index > 0) : (index -= 1) {
                const glyph = run[index - 1];
                var visual_glyph = glyph;
                visual_glyph.x_offset = run_start + (run_end - (glyph.x_offset + glyph.x_advance));
                try visual_glyphs.append(allocator, visual_glyph);
            }
        },
    }
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

fn isInRange(codepoint: u21, start: u21, end: u21) bool {
    return codepoint >= start and codepoint <= end;
}

test "automatic direction uses RTL for RTL-only text" {
    const rtl = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 2, .cluster = 1, .x_offset = 100, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
    };
    const mixed = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'A', .glyph_id = 2, .cluster = 1, .x_offset = 100, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
    };

    try std.testing.expectEqual(ShapeDirection.rtl, resolveDirection(.auto, &rtl));
    try std.testing.expectEqual(ShapeDirection.ltr, resolveDirection(.auto, &mixed));
}

test "RTL visual order mirrors horizontal positions" {
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x05D0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 2, .cluster = 1, .x_offset = 100, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
    };

    applyRtlVisualOrder(&glyphs, 180);

    try std.testing.expectEqual(@as(u16, 2), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 1), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(i32, 80), glyphs[1].x_offset);
}

test "mixed direction visual order reverses RTL runs inside LTR text" {
    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D0, .glyph_id = 2, .cluster = 1, .x_offset = 80, .y_offset = 0, .x_advance = 70, .y_advance = 0, .advance_width = 70, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x05D1, .glyph_id = 3, .cluster = 2, .x_offset = 150, .y_offset = 0, .x_advance = 90, .y_advance = 0, .advance_width = 90, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'B', .glyph_id = 4, .cluster = 3, .x_offset = 240, .y_offset = 0, .x_advance = 80, .y_advance = 0, .advance_width = 80, .lsb = 0, .kern_adjustment = 0 },
    };

    try applyMixedDirectionVisualOrder(std.testing.allocator, &glyphs);

    try std.testing.expectEqual(@as(u16, 1), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 3), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(i32, 80), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(u16, 2), glyphs[2].glyph_id);
    try std.testing.expectEqual(@as(i32, 170), glyphs[2].x_offset);
    try std.testing.expectEqual(@as(u16, 4), glyphs[3].glyph_id);
    try std.testing.expectEqual(@as(i32, 240), glyphs[3].x_offset);
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
