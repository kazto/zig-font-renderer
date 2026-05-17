const std = @import("std");
const font_parser = @import("font_parser.zig");
const types = @import("shaper_types.zig");
const ot_layout = @import("ot_layout.zig");
const gsub = @import("gsub.zig");
const gpos = @import("gpos.zig");
const kern = @import("kern.zig");
const shaper_direction = @import("shaper_direction.zig");
const shaper_features = @import("shaper_features.zig");
const test_utils = @import("shaper_test_utils.zig");

pub const ShapeError = types.ShapeError;
pub const ShapeDirection = types.ShapeDirection;
pub const ShapeOptions = types.ShapeOptions;
pub const ShapedGlyph = types.ShapedGlyph;
pub const ShapedText = types.ShapedText;

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

        const layout_options = shaper_features.resolveLayoutOptions(options, glyphs.items);

        // 1. GSUB substitutions
        try gsub.Gsub.apply(allocator, face, &glyphs, layout_options);

        // Update metrics for potentially new glyph IDs from GSUB
        for (glyphs.items) |*glyph| {
            const metric = try face.getHMetric(glyph.glyph_id);
            glyph.advance_width = metric.advance_width;
            glyph.x_advance = @as(i32, metric.advance_width);
            glyph.lsb = metric.lsb;
            if (options.direction == .ttb) {
                const vertical_metric = try face.getVMetric(glyph.glyph_id);
                glyph.y_advance = @as(i32, vertical_metric.advance_height);
            }
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

        const resolved_direction = shaper_direction.resolveDirection(options.direction, glyphs.items);
        const horizontal_total_advance = shaper_direction.computeTotalAdvance(glyphs.items, .ltr);
        if (resolved_direction == .rtl) {
            try shaper_direction.applyRtlVisualOrder(allocator, glyphs.items, horizontal_total_advance);
        } else if (resolved_direction == .ttb) {
            shaper_direction.applyVerticalLayout(glyphs.items);
        } else if (shaper_direction.hasMixedStrongDirections(glyphs.items)) {
            try shaper_direction.applyMixedDirectionVisualOrder(allocator, glyphs.items);
        }

        const total_advance = shaper_direction.computeTotalAdvance(glyphs.items, resolved_direction);

        return .{
            .glyphs = try glyphs.toOwnedSlice(allocator),
            .total_advance = total_advance,
        };
    }
};

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
    const resolved = shaper_features.resolveLayoutOptions(.{}, &glyphs);
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
    const resolved = shaper_features.resolveLayoutOptions(.{ .script_tag = ot_layout.OtLayout.latin_script_tag }, &glyphs);
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
