const std = @import("std");
const font_parser = @import("font_parser.zig");
const types = @import("shaper_types.zig");
const ot_layout = @import("ot_layout.zig");
const gsub = @import("gsub.zig");
const gpos = @import("gpos.zig");
const kern = @import("kern.zig");
const test_utils = @import("shaper_test_utils.zig");

pub const ShapeError = types.ShapeError;
pub const ShapeDirection = types.ShapeDirection;
pub const ShapeOptions = types.ShapeOptions;
pub const ShapedGlyph = types.ShapedGlyph;
pub const ShapedText = types.ShapedText;

const default_feature_tags = [_][4]u8{
    "ccmp".*,
    "locl".*,
    "liga".*,
    "clig".*,
    "calt".*,
    "kern".*,
    "mark".*,
    "mkmk".*,
};

const arabic_default_feature_tags = [_][4]u8{
    "ccmp".*,
    "locl".*,
    "isol".*,
    "init".*,
    "medi".*,
    "fina".*,
    "rlig".*,
    "calt".*,
    "kern".*,
    "mark".*,
    "mkmk".*,
};

const indic_default_feature_tags = [_][4]u8{
    "ccmp".*,
    "locl".*,
    "nukt".*,
    "akhn".*,
    "rphf".*,
    "blwf".*,
    "half".*,
    "pstf".*,
    "vatu".*,
    "pres".*,
    "abvs".*,
    "blws".*,
    "psts".*,
    "haln".*,
    "calt".*,
    "kern".*,
    "mark".*,
    "mkmk".*,
};

pub const ShapeEngine = struct {
    pub fn init() ShapeEngine {
        return .{};
    }

    pub fn shapeText(
        self: ShapeEngine,
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        text: []const u8,
    ) ShapeError!ShapedText {
        return self.shapeTextWithOptions(allocator, face, text, .{});
    }

    pub fn shapeTextWithOptions(
        self: ShapeEngine,
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        text: []const u8,
        options: ShapeOptions,
    ) ShapeError!ShapedText {
        _ = self;

        var view = std.unicode.Utf8View.init(text) catch return ShapeError.InvalidUtf8;

        var glyphs = std.ArrayList(ShapedGlyph).empty;
        errdefer glyphs.deinit(allocator);

        var iterator = view.iterator();
        var cluster: usize = 0;
        while (iterator.nextCodepoint()) |codepoint| : (cluster += 1) {
            const info = try face.getGlyphInfo(codepoint);
            try glyphs.append(allocator, .{
                .codepoint = codepoint,
                .glyph_id = info.id,
                .cluster = cluster,
                .x_offset = 0,
                .y_offset = 0,
                .x_advance = @as(i32, info.advance_width),
                .y_advance = 0,
                .advance_width = info.advance_width,
                .lsb = info.lsb,
                .kern_adjustment = 0,
            });
        }

        const layout_options = resolveLayoutOptions(options, glyphs.items);

        // 1. GSUB substitutions
        try gsub.Gsub.apply(allocator, face, &glyphs, layout_options);

        // Update metrics for potentially new glyph IDs from GSUB
        for (glyphs.items) |*glyph| {
            const metric = try face.getHMetric(glyph.glyph_id);
            glyph.advance_width = metric.advance_width;
            glyph.x_advance = @as(i32, metric.advance_width);
            glyph.lsb = metric.lsb;
        }

        // 2. GPOS positioning
        try gpos.Gpos.apply(allocator, face, glyphs.items, layout_options);
        const gpos_adjusted = kern.hasGposAdjustment(glyphs.items);

        // 3. Fallback to legacy kern if GPOS did not provide adjustments.
        if (!gpos_adjusted) {
            _ = try kern.applyKerning(face, glyphs.items);
        } else {
            var pen_x: i32 = 0;
            for (glyphs.items) |*glyph| {
                const x_off = glyph.x_offset;
                glyph.x_offset = pen_x + x_off;
                pen_x += glyph.x_advance;
            }
        }

        var total_advance: i32 = 0;
        if (glyphs.items.len > 0) {
            for (glyphs.items) |glyph| {
                total_advance = @max(total_advance, glyph.x_offset + glyph.x_advance);
            }
        }

        const resolved_direction = resolveDirection(options.direction, glyphs.items);
        if (resolved_direction == .rtl) {
            applyRtlVisualOrder(glyphs.items, total_advance);
        } else if (hasMixedStrongDirections(glyphs.items)) {
            try applyMixedDirectionVisualOrder(allocator, glyphs.items);
        }

        return .{
            .glyphs = try glyphs.toOwnedSlice(allocator),
            .total_advance = total_advance,
        };
    }
};

fn resolveLayoutOptions(options: ShapeOptions, glyphs: []const ShapedGlyph) ShapeOptions {
    var resolved = options;
    if (resolved.script_tag == null) {
        resolved.script_tag = inferScriptTag(glyphs);
    }
    if (resolved.language_tag == null) {
        resolved.language_tag = inferLanguageTag(glyphs);
    }
    if (resolved.feature_tags == null) {
        resolved.feature_tags = defaultFeatureTagsForScript(resolved.script_tag);
    }
    return resolved;
}

fn defaultFeatureTagsForScript(script_tag: ?[4]u8) []const [4]u8 {
    if (script_tag) |tag| {
        if (std.mem.eql(u8, &tag, &ot_layout.OtLayout.arabic_script_tag)) return &arabic_default_feature_tags;
        if (std.mem.eql(u8, &tag, &ot_layout.OtLayout.devanagari_script_tag)) return &indic_default_feature_tags;
    }
    return &default_feature_tags;
}

fn inferScriptTag(glyphs: []const ShapedGlyph) ?[4]u8 {
    for (glyphs) |glyph| {
        if (scriptTagForCodepoint(glyph.codepoint)) |tag| return tag;
    }
    return null;
}

fn inferLanguageTag(glyphs: []const ShapedGlyph) ?[4]u8 {
    for (glyphs) |glyph| {
        if (languageTagForCodepoint(glyph.codepoint)) |tag| return tag;
    }
    return null;
}

fn scriptTagForCodepoint(codepoint: u21) ?[4]u8 {
    if (isInRange(codepoint, 0x0041, 0x024F)) return ot_layout.OtLayout.latin_script_tag;
    if (isInRange(codepoint, 0x0370, 0x03FF)) return ot_layout.OtLayout.greek_script_tag;
    if (isInRange(codepoint, 0x0400, 0x052F)) return ot_layout.OtLayout.cyrillic_script_tag;
    if (isInRange(codepoint, 0x0590, 0x05FF)) return ot_layout.OtLayout.hebrew_script_tag;
    if (isInRange(codepoint, 0x0600, 0x06FF) or isInRange(codepoint, 0x0750, 0x077F) or isInRange(codepoint, 0x08A0, 0x08FF)) return ot_layout.OtLayout.arabic_script_tag;
    if (isInRange(codepoint, 0x0900, 0x097F)) return ot_layout.OtLayout.devanagari_script_tag;
    if (isInRange(codepoint, 0x0E00, 0x0E7F)) return ot_layout.OtLayout.thai_script_tag;
    if (isInRange(codepoint, 0x3040, 0x30FF) or isInRange(codepoint, 0x31F0, 0x31FF)) return ot_layout.OtLayout.kana_script_tag;
    if (isInRange(codepoint, 0x3400, 0x9FFF) or isInRange(codepoint, 0xF900, 0xFAFF)) return ot_layout.OtLayout.han_script_tag;
    if (isInRange(codepoint, 0xAC00, 0xD7AF) or isInRange(codepoint, 0x1100, 0x11FF) or isInRange(codepoint, 0x3130, 0x318F)) return ot_layout.OtLayout.hangul_script_tag;
    return null;
}

fn languageTagForCodepoint(codepoint: u21) ?[4]u8 {
    if (isTurkishSpecificLatin(codepoint)) return ot_layout.OtLayout.turkish_language_tag;
    if (isInRange(codepoint, 0x0590, 0x05FF)) return ot_layout.OtLayout.hebrew_language_tag;
    if (isInRange(codepoint, 0x0600, 0x06FF) or isInRange(codepoint, 0x0750, 0x077F) or isInRange(codepoint, 0x08A0, 0x08FF)) return ot_layout.OtLayout.arabic_language_tag;
    if (isInRange(codepoint, 0x0E00, 0x0E7F)) return ot_layout.OtLayout.thai_language_tag;
    if (isInRange(codepoint, 0x3040, 0x30FF) or isInRange(codepoint, 0x31F0, 0x31FF)) return ot_layout.OtLayout.japanese_language_tag;
    if (isInRange(codepoint, 0xAC00, 0xD7AF) or isInRange(codepoint, 0x1100, 0x11FF) or isInRange(codepoint, 0x3130, 0x318F)) return ot_layout.OtLayout.korean_language_tag;
    return null;
}

fn isTurkishSpecificLatin(codepoint: u21) bool {
    return codepoint == 0x011E or codepoint == 0x011F or
        codepoint == 0x0130 or codepoint == 0x0131 or
        codepoint == 0x015E or codepoint == 0x015F;
}

fn isInRange(codepoint: u21, start: u21, end: u21) bool {
    return codepoint >= start and codepoint <= end;
}

fn resolveDirection(direction: ShapeDirection, glyphs: []const ShapedGlyph) ShapeDirection {
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

fn applyRtlVisualOrder(glyphs: []ShapedGlyph, total_advance: i32) void {
    for (glyphs) |*glyph| {
        glyph.x_offset = total_advance - (glyph.x_offset + glyph.x_advance);
    }
    std.mem.reverse(ShapedGlyph, glyphs);
}

fn applyMixedDirectionVisualOrder(
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
        .ltr, .auto => {
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

fn hasMixedStrongDirections(glyphs: []const ShapedGlyph) bool {
    var saw_ltr = false;
    var saw_rtl = false;

    for (glyphs) |glyph| {
        if (strongDirectionForCodepoint(glyph.codepoint)) |direction| {
            switch (direction) {
                .ltr => saw_ltr = true,
                .rtl => saw_rtl = true,
                .auto => {},
            }
            if (saw_ltr and saw_rtl) return true;
        }
    }

    return false;
}

fn strongDirectionForCodepoint(codepoint: u21) ?ShapeDirection {
    if (isStrongRtlCodepoint(codepoint)) return .rtl;
    if (isStrongLtrCodepoint(codepoint)) return .ltr;
    return null;
}

fn isStrongRtlCodepoint(codepoint: u21) bool {
    return isInRange(codepoint, 0x0590, 0x08FF) or
        isInRange(codepoint, 0xFB1D, 0xFDFF) or
        isInRange(codepoint, 0xFE70, 0xFEFF) or
        isInRange(codepoint, 0x10800, 0x10FFF);
}

fn isStrongLtrCodepoint(codepoint: u21) bool {
    return isInRange(codepoint, 0x0041, 0x02AF) or
        isInRange(codepoint, 0x0370, 0x052F) or
        isInRange(codepoint, 0x0900, 0x1FFF) or
        isInRange(codepoint, 0x3040, 0xA7FF) or
        isInRange(codepoint, 0xAC00, 0xD7AF);
}

test "detects whether GPOS changed positioning" {
    const unchanged = [_]ShapedGlyph{.{
        .codepoint = 'A',
        .glyph_id = 1,
        .cluster = 0,
        .x_offset = 0,
        .y_offset = 0,
        .x_advance = 100,
        .y_advance = 0,
        .advance_width = 100,
        .lsb = 0,
        .kern_adjustment = 0,
    }};
    try std.testing.expect(!kern.hasGposAdjustment(&unchanged));

    const adjusted = [_]ShapedGlyph{.{
        .codepoint = 'A',
        .glyph_id = 1,
        .cluster = 0,
        .x_offset = 0,
        .y_offset = 0,
        .x_advance = 90,
        .y_advance = 0,
        .advance_width = 100,
        .lsb = 0,
        .kern_adjustment = 0,
    }};
    try std.testing.expect(kern.hasGposAdjustment(&adjusted));
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

test "OpenType layout lookup collection filters by feature tag" {
    var data = [_]u8{0} ** 90;
    test_utils.writeU16(&data, ot_layout.OtLayout.script_list_offset, 10);
    test_utils.writeU16(&data, ot_layout.OtLayout.feature_list_offset, 34);
    test_utils.writeU16(&data, ot_layout.OtLayout.lookup_list_offset, 80);

    test_utils.writeU16(&data, 10, 1);
    data[12..16].* = ot_layout.OtLayout.default_script_tag;
    test_utils.writeU16(&data, 16, 8);

    test_utils.writeU16(&data, 18, 4);
    test_utils.writeU16(&data, 20, 0);
    test_utils.writeU16(&data, 22, 0);
    test_utils.writeU16(&data, 24, ot_layout.OtLayout.required_feature_none);
    test_utils.writeU16(&data, 26, 2);
    test_utils.writeU16(&data, 28, 0);
    test_utils.writeU16(&data, 30, 1);

    test_utils.writeU16(&data, 34, 2);
    data[36..40].* = "liga".*;
    test_utils.writeU16(&data, 40, 14);
    data[42..46].* = "kern".*;
    test_utils.writeU16(&data, 46, 24);

    test_utils.writeU16(&data, 48, 0);
    test_utils.writeU16(&data, 50, 1);
    test_utils.writeU16(&data, 52, 7);
    test_utils.writeU16(&data, 58, 0);
    test_utils.writeU16(&data, 60, 1);
    test_utils.writeU16(&data, 62, 11);

    var selected = [_][4]u8{"kern".*};
    var lookup_indices = try ot_layout.OtLayout.collectLookupIndices(std.testing.allocator, &data, .{ .feature_tags = &selected });
    defer lookup_indices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lookup_indices.items.len);
    try std.testing.expectEqual(@as(u16, 11), lookup_indices.items[0]);
}

test "OpenType layout lookup collection can choose non-default language" {
    var data = [_]u8{0} ** 96;
    test_utils.writeU16(&data, ot_layout.OtLayout.script_list_offset, 10);
    test_utils.writeU16(&data, ot_layout.OtLayout.feature_list_offset, 48);
    test_utils.writeU16(&data, ot_layout.OtLayout.lookup_list_offset, 90);

    test_utils.writeU16(&data, 10, 1);
    data[12..16].* = ot_layout.OtLayout.latin_script_tag;
    test_utils.writeU16(&data, 16, 8);

    test_utils.writeU16(&data, 18, 0);
    test_utils.writeU16(&data, 20, 1);
    data[22..26].* = "TRK ".*;
    test_utils.writeU16(&data, 26, 18);

    test_utils.writeU16(&data, 36, 0);
    test_utils.writeU16(&data, 38, ot_layout.OtLayout.required_feature_none);
    test_utils.writeU16(&data, 40, 1);
    test_utils.writeU16(&data, 42, 1);

    test_utils.writeU16(&data, 48, 2);
    data[50..54].* = "liga".*;
    test_utils.writeU16(&data, 54, 14);
    data[56..60].* = "kern".*;
    test_utils.writeU16(&data, 60, 20);

    test_utils.writeU16(&data, 62, 0);
    test_utils.writeU16(&data, 64, 1);
    test_utils.writeU16(&data, 66, 3);
    test_utils.writeU16(&data, 68, 0);
    test_utils.writeU16(&data, 70, 1);
    test_utils.writeU16(&data, 72, 5);

    var lookup_indices = try ot_layout.OtLayout.collectLookupIndices(std.testing.allocator, &data, .{
        .script_tag = "latn".*,
        .language_tag = "TRK ".*,
    });
    defer lookup_indices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lookup_indices.items.len);
    try std.testing.expectEqual(@as(u16, 5), lookup_indices.items[0]);
}

test "shape options infer script from text when unspecified" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x304B, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{}, &glyphs);
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.kana_script_tag, &resolved.script_tag.?);
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.japanese_language_tag, &resolved.language_tag.?);
}

test "shape options keep caller-provided script tag" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x304B, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{ .script_tag = ot_layout.OtLayout.latin_script_tag }, &glyphs);
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.latin_script_tag, &resolved.script_tag.?);
}

test "shape options keep caller-provided language tag" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x304B, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{ .language_tag = ot_layout.OtLayout.turkish_language_tag }, &glyphs);
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.turkish_language_tag, &resolved.language_tag.?);
}

test "shape options assign default feature policy" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{}, &glyphs);
    try std.testing.expect(resolved.feature_tags != null);
    try std.testing.expectEqualSlices(u8, &"liga".*, &resolved.feature_tags.?[2]);
}

test "shape options keep caller-provided feature tags" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const selected = [_][4]u8{"salt".*};
    const resolved = resolveLayoutOptions(.{ .feature_tags = &selected }, &glyphs);
    try std.testing.expectEqualSlices(u8, &"salt".*, &resolved.feature_tags.?[0]);
}

test "default feature policy varies by script" {
    const arabic_tags = defaultFeatureTagsForScript(ot_layout.OtLayout.arabic_script_tag);
    try std.testing.expect(hasFeatureTag(arabic_tags, "init".*));
    try std.testing.expect(hasFeatureTag(arabic_tags, "fina".*));

    const indic_tags = defaultFeatureTagsForScript(ot_layout.OtLayout.devanagari_script_tag);
    try std.testing.expect(hasFeatureTag(indic_tags, "half".*));
    try std.testing.expect(hasFeatureTag(indic_tags, "haln".*));
}

test "script inference maps common Unicode ranges" {
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.latin_script_tag, &(scriptTagForCodepoint('A').?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.arabic_script_tag, &(scriptTagForCodepoint(0x0627).?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.han_script_tag, &(scriptTagForCodepoint(0x6F22).?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.hangul_script_tag, &(scriptTagForCodepoint(0xD55C).?));
}

fn hasFeatureTag(tags: []const [4]u8, needle: [4]u8) bool {
    for (tags) |tag| {
        if (std.mem.eql(u8, &tag, &needle)) return true;
    }
    return false;
}

test "language inference maps common Unicode ranges" {
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.turkish_language_tag, &(languageTagForCodepoint(0x0130).?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.arabic_language_tag, &(languageTagForCodepoint(0x0627).?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.japanese_language_tag, &(languageTagForCodepoint(0x304B).?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.korean_language_tag, &(languageTagForCodepoint(0xD55C).?));
}

test "OpenType layout lookup collection filters to default feature policy" {
    var data = [_]u8{0} ** 100;
    test_utils.writeU16(&data, ot_layout.OtLayout.script_list_offset, 10);
    test_utils.writeU16(&data, ot_layout.OtLayout.feature_list_offset, 34);
    test_utils.writeU16(&data, ot_layout.OtLayout.lookup_list_offset, 92);

    test_utils.writeU16(&data, 10, 1);
    data[12..16].* = ot_layout.OtLayout.default_script_tag;
    test_utils.writeU16(&data, 16, 8);

    test_utils.writeU16(&data, 18, 4);
    test_utils.writeU16(&data, 20, 0);
    test_utils.writeU16(&data, 22, 0);
    test_utils.writeU16(&data, 24, ot_layout.OtLayout.required_feature_none);
    test_utils.writeU16(&data, 26, 2);
    test_utils.writeU16(&data, 28, 0);
    test_utils.writeU16(&data, 30, 1);

    test_utils.writeU16(&data, 34, 2);
    data[36..40].* = "liga".*;
    test_utils.writeU16(&data, 40, 14);
    data[42..46].* = "salt".*;
    test_utils.writeU16(&data, 46, 20);

    test_utils.writeU16(&data, 48, 0);
    test_utils.writeU16(&data, 50, 1);
    test_utils.writeU16(&data, 52, 7);
    test_utils.writeU16(&data, 54, 0);
    test_utils.writeU16(&data, 56, 1);
    test_utils.writeU16(&data, 58, 11);

    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{}, &glyphs);
    var lookup_indices = try ot_layout.OtLayout.collectLookupIndices(std.testing.allocator, &data, resolved);
    defer lookup_indices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lookup_indices.items.len);
    try std.testing.expectEqual(@as(u16, 7), lookup_indices.items[0]);
}

test "OpenType layout lookup collection uses inferred language when present" {
    var data = [_]u8{0} ** 96;
    test_utils.writeU16(&data, ot_layout.OtLayout.script_list_offset, 10);
    test_utils.writeU16(&data, ot_layout.OtLayout.feature_list_offset, 48);
    test_utils.writeU16(&data, ot_layout.OtLayout.lookup_list_offset, 90);

    test_utils.writeU16(&data, 10, 1);
    data[12..16].* = ot_layout.OtLayout.latin_script_tag;
    test_utils.writeU16(&data, 16, 8);

    test_utils.writeU16(&data, 18, 0);
    test_utils.writeU16(&data, 20, 1);
    data[22..26].* = ot_layout.OtLayout.turkish_language_tag;
    test_utils.writeU16(&data, 26, 18);

    test_utils.writeU16(&data, 36, 0);
    test_utils.writeU16(&data, 38, ot_layout.OtLayout.required_feature_none);
    test_utils.writeU16(&data, 40, 1);
    test_utils.writeU16(&data, 42, 1);

    test_utils.writeU16(&data, 48, 2);
    data[50..54].* = "liga".*;
    test_utils.writeU16(&data, 54, 14);
    data[56..60].* = "locl".*;
    test_utils.writeU16(&data, 60, 20);

    test_utils.writeU16(&data, 62, 0);
    test_utils.writeU16(&data, 64, 1);
    test_utils.writeU16(&data, 66, 3);
    test_utils.writeU16(&data, 68, 0);
    test_utils.writeU16(&data, 70, 1);
    test_utils.writeU16(&data, 72, 5);

    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x0130, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{ .script_tag = ot_layout.OtLayout.latin_script_tag }, &glyphs);
    var lookup_indices = try ot_layout.OtLayout.collectLookupIndices(std.testing.allocator, &data, resolved);
    defer lookup_indices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lookup_indices.items.len);
    try std.testing.expectEqual(@as(u16, 5), lookup_indices.items[0]);
}

test "OpenType layout lookup collection falls back when requested script is absent" {
    var data = [_]u8{0} ** 80;
    test_utils.writeU16(&data, ot_layout.OtLayout.script_list_offset, 10);
    test_utils.writeU16(&data, ot_layout.OtLayout.feature_list_offset, 32);
    test_utils.writeU16(&data, ot_layout.OtLayout.lookup_list_offset, 72);

    test_utils.writeU16(&data, 10, 1);
    data[12..16].* = ot_layout.OtLayout.latin_script_tag;
    test_utils.writeU16(&data, 16, 8);

    test_utils.writeU16(&data, 18, 4);
    test_utils.writeU16(&data, 20, 0);
    test_utils.writeU16(&data, 22, 0);
    test_utils.writeU16(&data, 24, ot_layout.OtLayout.required_feature_none);
    test_utils.writeU16(&data, 26, 1);
    test_utils.writeU16(&data, 28, 0);

    test_utils.writeU16(&data, 32, 1);
    data[34..38].* = "kern".*;
    test_utils.writeU16(&data, 38, 8);
    test_utils.writeU16(&data, 40, 0);
    test_utils.writeU16(&data, 42, 1);
    test_utils.writeU16(&data, 44, 3);

    var lookup_indices = try ot_layout.OtLayout.collectLookupIndices(std.testing.allocator, &data, .{
        .script_tag = ot_layout.OtLayout.kana_script_tag,
    });
    defer lookup_indices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lookup_indices.items.len);
    try std.testing.expectEqual(@as(u16, 3), lookup_indices.items[0]);
}

test "shape engine rejects invalid utf8" {
    const engine = ShapeEngine.init();
    const face: font_parser.Face = undefined;
    try std.testing.expectError(
        ShapeError.InvalidUtf8,
        engine.shapeText(std.testing.allocator, face, "\xff"),
    );
}

test "gsub single substitution format 2" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(allocator);

    try glyphs.append(allocator, .{
        .codepoint = 'A',
        .glyph_id = 1,
        .cluster = 0,
        .x_offset = 0,
        .y_offset = 0,
        .x_advance = 100,
        .y_advance = 0,
        .advance_width = 100,
        .lsb = 0,
        .kern_adjustment = 0,
    });

    var subtable = [_]u8{0} ** 16;
    test_utils.writeU16(&subtable, 0, 2);
    test_utils.writeU16(&subtable, 2, 8);
    test_utils.writeU16(&subtable, 4, 1);
    test_utils.writeU16(&subtable, 6, 10);
    test_utils.writeU16(&subtable, 8, 1);
    test_utils.writeU16(&subtable, 10, 1);
    test_utils.writeU16(&subtable, 12, 1);

    try gsub.Gsub.applySingleSubstitution(&subtable, &glyphs);
    try std.testing.expectEqual(@as(u16, 10), glyphs.items[0].glyph_id);
}
