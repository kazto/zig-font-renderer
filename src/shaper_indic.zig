const std = @import("std");
const types = @import("shaper_types.zig");

const ShapedGlyph = types.ShapedGlyph;

pub fn applyIndicReordering(allocator: std.mem.Allocator, glyphs: []ShapedGlyph) std.mem.Allocator.Error!void {
    if (glyphs.len < 2) return;

    const placement_deltas = try computePlacementDeltas(allocator, glyphs);
    defer allocator.free(placement_deltas);

    var visual = std.ArrayList(ShapedGlyph).empty;
    defer visual.deinit(allocator);
    try visual.ensureTotalCapacity(allocator, glyphs.len);
    var visual_deltas = std.ArrayList(i32).empty;
    defer visual_deltas.deinit(allocator);
    try visual_deltas.ensureTotalCapacity(allocator, glyphs.len);

    var did_reorder = false;
    for (glyphs, 0..) |glyph_item, index| {
        const delta = placement_deltas[index];
        if (isIndicPreBaseMatra(glyph_item.codepoint)) {
            if (findPreviousIndicBase(visual.items)) |base_index| {
                try visual.insert(allocator, base_index, glyph_item);
                try visual_deltas.insert(allocator, base_index, delta);
                did_reorder = true;
                continue;
            }
        }
        try visual.append(allocator, glyph_item);
        try visual_deltas.append(allocator, delta);
    }

    if (moveInitialDevanagariRephaSequence(visual.items, visual_deltas.items)) {
        did_reorder = true;
    }

    if (!did_reorder) return;

    for (visual.items, 0..) |item, index| {
        glyphs[index] = item;
    }
    recomputeHorizontalOffsets(glyphs, visual_deltas.items);
}

fn computePlacementDeltas(allocator: std.mem.Allocator, glyphs: []const ShapedGlyph) std.mem.Allocator.Error![]i32 {
    const deltas = try allocator.alloc(i32, glyphs.len);
    var pen_x: i32 = 0;
    for (glyphs, 0..) |item, index| {
        deltas[index] = item.x_offset - pen_x;
        pen_x += item.x_advance;
    }
    return deltas;
}

fn recomputeHorizontalOffsets(glyphs: []ShapedGlyph, placement_deltas: []const i32) void {
    var pen_x: i32 = 0;
    for (glyphs, 0..) |*glyph_item, index| {
        const delta = placement_deltas[index];
        glyph_item.x_offset = pen_x + delta;
        pen_x += glyph_item.x_advance;
    }
}

fn findPreviousIndicBase(glyphs: []const ShapedGlyph) ?usize {
    var index = glyphs.len;
    while (index > 0) {
        index -= 1;
        const codepoint = glyphs[index].codepoint;
        if (isIndicMark(codepoint) or isIndicVirama(codepoint)) continue;
        if (isIndicConsonant(codepoint)) return index;
    }
    return null;
}

fn moveInitialDevanagariRephaSequence(glyphs: []ShapedGlyph, placement_deltas: []i32) bool {
    if (glyphs.len < 3) return false;
    if (!isDevanagariRa(glyphs[0].codepoint) or !isDevanagariVirama(glyphs[1].codepoint)) return false;

    var base_index: ?usize = null;
    var index: usize = 2;
    while (index < glyphs.len) : (index += 1) {
        const codepoint = glyphs[index].codepoint;
        if (isIndicMark(codepoint) or isIndicVirama(codepoint)) continue;
        if (isIndicConsonant(codepoint)) {
            base_index = index;
            break;
        }
    }

    const base = base_index orelse return false;
    const ra = glyphs[0];
    const virama = glyphs[1];
    const ra_delta = placement_deltas[0];
    const virama_delta = placement_deltas[1];

    index = 2;
    while (index <= base) : (index += 1) {
        glyphs[index - 2] = glyphs[index];
        placement_deltas[index - 2] = placement_deltas[index];
    }
    glyphs[base - 1] = ra;
    placement_deltas[base - 1] = ra_delta;
    glyphs[base] = virama;
    placement_deltas[base] = virama_delta;
    return true;
}

fn isIndicPreBaseMatra(codepoint: u21) bool {
    return codepoint == 0x093F or codepoint == 0x094E or
        codepoint == 0x09BF or codepoint == 0x09C7 or codepoint == 0x09C8 or
        codepoint == 0x0A3F or codepoint == 0x0ABF or codepoint == 0x0B3F or
        isInRange(codepoint, 0x0BC6, 0x0BC8) or
        codepoint == 0x0CC6 or codepoint == 0x0D46 or codepoint == 0x0D47 or
        isInRange(codepoint, 0x0E40, 0x0E44);
}

fn isIndicConsonant(codepoint: u21) bool {
    return isInRange(codepoint, 0x0915, 0x0939) or
        isInRange(codepoint, 0x0958, 0x095F) or
        isInRange(codepoint, 0x0995, 0x09B9) or
        isInRange(codepoint, 0x0A15, 0x0A39) or
        isInRange(codepoint, 0x0A95, 0x0AB9) or
        isInRange(codepoint, 0x0B15, 0x0B39) or
        isInRange(codepoint, 0x0B95, 0x0BB9) or
        isInRange(codepoint, 0x0C15, 0x0C39) or
        isInRange(codepoint, 0x0C95, 0x0CB9) or
        isInRange(codepoint, 0x0D15, 0x0D39);
}

fn isIndicMark(codepoint: u21) bool {
    return isInRange(codepoint, 0x0900, 0x0903) or
        isInRange(codepoint, 0x093A, 0x094F) or
        isInRange(codepoint, 0x0981, 0x0983) or
        isInRange(codepoint, 0x09BE, 0x09CC) or
        isInRange(codepoint, 0x0A01, 0x0A03) or
        isInRange(codepoint, 0x0A3E, 0x0A4D) or
        isInRange(codepoint, 0x0ABE, 0x0ACD) or
        isInRange(codepoint, 0x0B3E, 0x0B4D) or
        isInRange(codepoint, 0x0BBE, 0x0BCD) or
        isInRange(codepoint, 0x0C3E, 0x0C4D) or
        isInRange(codepoint, 0x0CBE, 0x0CCD) or
        isInRange(codepoint, 0x0D3E, 0x0D4D);
}

fn isIndicVirama(codepoint: u21) bool {
    return codepoint == 0x094D or codepoint == 0x09CD or codepoint == 0x0A4D or
        codepoint == 0x0ACD or codepoint == 0x0B4D or codepoint == 0x0BCD or
        codepoint == 0x0C4D or codepoint == 0x0CCD or codepoint == 0x0D4D;
}

fn isDevanagariRa(codepoint: u21) bool {
    return codepoint == 0x0930;
}

fn isDevanagariVirama(codepoint: u21) bool {
    return codepoint == 0x094D;
}

fn isInRange(codepoint: u21, start: u21, end: u21) bool {
    return codepoint >= start and codepoint <= end;
}

fn glyph(codepoint: u21, glyph_id: u16, cluster: usize, x_offset: i32, x_advance: i32) ShapedGlyph {
    return .{
        .codepoint = codepoint,
        .glyph_id = glyph_id,
        .cluster = cluster,
        .x_offset = x_offset,
        .y_offset = 0,
        .x_advance = x_advance,
        .y_advance = 0,
        .advance_width = @intCast(@max(x_advance, 0)),
        .lsb = 0,
        .kern_adjustment = 0,
    };
}

test "Indic reordering moves Devanagari pre-base matra before base" {
    var glyphs = [_]ShapedGlyph{
        glyph(0x0915, 10, 0, 0, 600),
        glyph(0x093F, 11, 1, 600, 200),
    };

    try applyIndicReordering(std.testing.allocator, &glyphs);

    try std.testing.expectEqual(@as(u16, 11), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 1), glyphs[0].cluster);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 10), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(usize, 0), glyphs[1].cluster);
    try std.testing.expectEqual(@as(i32, 200), glyphs[1].x_offset);
}

test "Indic reordering keeps post-base matras in place" {
    var glyphs = [_]ShapedGlyph{
        glyph(0x0915, 10, 0, 0, 600),
        glyph(0x093E, 11, 1, 600, 200),
    };

    try applyIndicReordering(std.testing.allocator, &glyphs);

    try std.testing.expectEqual(@as(u16, 10), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u16, 11), glyphs[1].glyph_id);
}

test "Indic reordering moves initial Devanagari repha sequence after base" {
    var glyphs = [_]ShapedGlyph{
        glyph(0x0930, 10, 0, 0, 300),
        glyph(0x094D, 11, 1, 300, 0),
        glyph(0x0915, 12, 2, 300, 600),
    };

    try applyIndicReordering(std.testing.allocator, &glyphs);

    try std.testing.expectEqual(@as(u16, 12), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 2), glyphs[0].cluster);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 10), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(usize, 0), glyphs[1].cluster);
    try std.testing.expectEqual(@as(i32, 600), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(u16, 11), glyphs[2].glyph_id);
    try std.testing.expectEqual(@as(usize, 1), glyphs[2].cluster);
    try std.testing.expectEqual(@as(i32, 900), glyphs[2].x_offset);
}

test "Indic reordering combines pre-base matra and initial Devanagari repha sequence" {
    var glyphs = [_]ShapedGlyph{
        glyph(0x0930, 10, 0, 0, 300),
        glyph(0x094D, 11, 1, 300, 0),
        glyph(0x0915, 12, 2, 300, 600),
        glyph(0x093F, 13, 3, 900, 200),
    };

    try applyIndicReordering(std.testing.allocator, &glyphs);

    try std.testing.expectEqual(@as(u16, 13), glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 3), glyphs[0].cluster);
    try std.testing.expectEqual(@as(i32, 0), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(u16, 12), glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(usize, 2), glyphs[1].cluster);
    try std.testing.expectEqual(@as(i32, 200), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(u16, 10), glyphs[2].glyph_id);
    try std.testing.expectEqual(@as(usize, 0), glyphs[2].cluster);
    try std.testing.expectEqual(@as(i32, 800), glyphs[2].x_offset);
    try std.testing.expectEqual(@as(u16, 11), glyphs[3].glyph_id);
    try std.testing.expectEqual(@as(usize, 1), glyphs[3].cluster);
    try std.testing.expectEqual(@as(i32, 1100), glyphs[3].x_offset);
}
