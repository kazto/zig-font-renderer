const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");
const chained_contextual = @import("gsub_chained_contextual.zig");
const gsub_alternate = @import("gsub_alternate.zig");
const gsub_contextual = @import("gsub_contextual.zig");
const gsub_ligature = @import("gsub_ligature.zig");
const gsub_lookup = @import("gsub_lookup.zig");
const gsub_single = @import("gsub_single.zig");
const ot_layout = @import("ot_layout.zig");
const shaper_arabic = @import("shaper_arabic.zig");
const types = @import("shaper_types.zig");
const test_utils = @import("shaper_test_utils.zig");

const readU16 = binary_reader.readU16;
const LayoutError = types.LayoutError;
const ShapeOptions = types.ShapeOptions;
const ShapedGlyph = types.ShapedGlyph;
const GsubLookupType = gsub_lookup.GsubLookupType;

const ArabicFeature = struct {
    tag: [4]u8,
    form: shaper_arabic.JoiningForm,
};

const arabic_positional_features = [_]ArabicFeature{
    .{ .tag = "isol".*, .form = .isolated },
    .{ .tag = "init".*, .form = .initial },
    .{ .tag = "medi".*, .form = .medial },
    .{ .tag = "fina".*, .form = .final },
};

pub const Gsub = struct {
    pub const max_recursion_depth = 16;

    const subst_record_size = 4;
    const subst_record_sequence_index_offset = 0;
    const subst_record_lookup_index_offset = 2;

    pub fn applyAlternateSubstitution(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        try gsub_alternate.apply(subtable, glyphs);
    }

    pub fn applyContextualSubstitution(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        try gsub_contextual.apply(allocator, face, lookup_list, subtable, glyphs, depth, applySubstitutionRecords);
    }

    pub fn applyContextualFormat1(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        try gsub_contextual.applyFormat1(allocator, face, lookup_list, subtable, glyphs, depth, applySubstitutionRecords);
    }

    pub fn applyContextualFormat2(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        try gsub_contextual.applyFormat2(allocator, face, lookup_list, subtable, glyphs, depth, applySubstitutionRecords);
    }

    pub fn applyContextualFormat3(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        try gsub_contextual.applyFormat3(allocator, face, lookup_list, subtable, glyphs, depth, applySubstitutionRecords);
    }

    pub fn apply(allocator: std.mem.Allocator, face: font_parser.Face, glyphs: *std.ArrayList(ShapedGlyph), options: ShapeOptions) LayoutError!void {
        const data = face.getTable(ot_layout.TableTags.gsub) orelse return;
        if (data.len < ot_layout.OtLayout.header_min_size) return font_parser.ParserError.InvalidTable;

        const lookup_list_off = try readU16(data, ot_layout.OtLayout.lookup_list_offset);
        const lookup_list_data = try ot_layout.sliceFrom(data, lookup_list_off);

        if (isArabicScript(options.script_tag) and options.feature_tags != null) {
            try applyArabicJoiningFeatures(allocator, face, data, lookup_list_data, glyphs, options);
            return;
        }

        var lookup_indices = try ot_layout.OtLayout.collectLookupIndices(allocator, data, options);
        defer lookup_indices.deinit(allocator);
        for (lookup_indices.items) |lookup_index| {
            try applyLookup(allocator, face, lookup_list_data, lookup_index, glyphs, 0);
        }
    }

    fn applyArabicJoiningFeatures(allocator: std.mem.Allocator, face: font_parser.Face, data: []const u8, lookup_list_data: []const u8, glyphs: *std.ArrayList(ShapedGlyph), options: ShapeOptions) LayoutError!void {
        const joining_forms = try shaper_arabic.computeJoiningForms(allocator, glyphs.items);
        defer allocator.free(joining_forms);

        for (arabic_positional_features) |feature| {
            if (!featureIsEnabled(options.feature_tags.?, feature.tag)) continue;
            var selected = [_][4]u8{feature.tag};
            var feature_options = options;
            feature_options.feature_tags = &selected;

            var lookup_indices = try ot_layout.OtLayout.collectLookupIndices(allocator, data, feature_options);
            defer lookup_indices.deinit(allocator);
            for (lookup_indices.items) |lookup_index| {
                try applyLookupForJoiningForm(allocator, face, lookup_list_data, lookup_index, glyphs, joining_forms, feature.form, 0);
            }
        }

        var remaining_features = std.ArrayList([4]u8).empty;
        defer remaining_features.deinit(allocator);
        for (options.feature_tags.?) |tag| {
            if (!isArabicPositionalFeature(tag)) {
                try remaining_features.append(allocator, tag);
            }
        }
        if (remaining_features.items.len == 0) return;

        var remaining_options = options;
        remaining_options.feature_tags = remaining_features.items;
        var lookup_indices = try ot_layout.OtLayout.collectLookupIndices(allocator, data, remaining_options);
        defer lookup_indices.deinit(allocator);
        for (lookup_indices.items) |lookup_index| {
            try applyLookup(allocator, face, lookup_list_data, lookup_index, glyphs, 0);
        }
    }

    pub fn applyLookup(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, index: u16, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        if (depth >= max_recursion_depth) return font_parser.ParserError.InvalidTable;
        const lookup_off = try ot_layout.OtLayout.getLookupOffset(lookup_list, index);
        const lookup_data = try ot_layout.sliceFrom(lookup_list, lookup_off);
        const lookup_type = try readU16(lookup_data, ot_layout.OtLayout.lookup_type_offset);
        const subtable_count = try readU16(lookup_data, ot_layout.OtLayout.lookup_subtable_count_offset);

        for (0..subtable_count) |i| {
            const subtable_off = try readU16(lookup_data, ot_layout.OtLayout.lookup_subtable_offsets_offset + i * 2);
            const subtable_data = try ot_layout.sliceFrom(lookup_data, subtable_off);

            if (lookup_type == @intFromEnum(GsubLookupType.single_substitution)) {
                try gsub_single.apply(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GsubLookupType.alternate_substitution)) {
                try gsub_alternate.apply(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GsubLookupType.ligature_substitution)) {
                try gsub_ligature.apply(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GsubLookupType.contextual_substitution)) {
                try applyContextualSubstitution(allocator, face, lookup_list, subtable_data, glyphs, depth);
            } else if (lookup_type == @intFromEnum(GsubLookupType.chained_contextual_substitution)) {
                try applyChainedContextualSubstitution(allocator, face, lookup_list, subtable_data, glyphs, depth);
            }
        }
    }

    fn applyLookupForJoiningForm(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, index: u16, glyphs: *std.ArrayList(ShapedGlyph), forms: []const shaper_arabic.JoiningForm, target_form: shaper_arabic.JoiningForm, depth: usize) LayoutError!void {
        if (depth >= max_recursion_depth) return font_parser.ParserError.InvalidTable;
        _ = allocator;
        _ = face;

        const lookup_off = try ot_layout.OtLayout.getLookupOffset(lookup_list, index);
        const lookup_data = try ot_layout.sliceFrom(lookup_list, lookup_off);
        const lookup_type = try readU16(lookup_data, ot_layout.OtLayout.lookup_type_offset);
        if (lookup_type != @intFromEnum(GsubLookupType.single_substitution)) return;

        const subtable_count = try readU16(lookup_data, ot_layout.OtLayout.lookup_subtable_count_offset);
        for (0..subtable_count) |i| {
            const subtable_off = try readU16(lookup_data, ot_layout.OtLayout.lookup_subtable_offsets_offset + i * 2);
            const subtable_data = try ot_layout.sliceFrom(lookup_data, subtable_off);
            try gsub_single.applyForJoiningForm(subtable_data, glyphs, forms, target_form);
        }
    }

    pub fn applyLigatureSubstitution(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        try gsub_ligature.apply(subtable, glyphs);
    }

    pub fn applySingleSubstitution(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        try gsub_single.apply(subtable, glyphs);
    }

    fn applySubstitutionRecords(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subst_records: []const u8, subst_count: u16, glyphs: *std.ArrayList(ShapedGlyph), start: usize, depth: usize) LayoutError!void {
        for (0..subst_count) |j| {
            const record_offset = j * subst_record_size;
            const subst_rel_idx = try readU16(subst_records, record_offset + subst_record_sequence_index_offset);
            const lookup_index = try readU16(subst_records, record_offset + subst_record_lookup_index_offset);

            if (start + subst_rel_idx < glyphs.items.len) {
                var sub_glyphs = std.ArrayList(ShapedGlyph).empty;
                defer sub_glyphs.deinit(allocator);
                try sub_glyphs.appendSlice(allocator, glyphs.items[start + subst_rel_idx ..]);

                try applyLookup(allocator, face, lookup_list, lookup_index, &sub_glyphs, depth + 1);

                const replace_start = start + subst_rel_idx;
                const old_len = glyphs.items.len - replace_start;
                try glyphs.replaceRange(allocator, replace_start, old_len, sub_glyphs.items);
            }
        }
    }

    pub fn applyChainedContextualSubstitution(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        try chained_contextual.apply(allocator, face, lookup_list, subtable, glyphs, depth, applySubstitutionRecords);
    }
};

fn isArabicScript(script_tag: ?[4]u8) bool {
    const tag = script_tag orelse return false;
    return std.mem.eql(u8, &tag, &ot_layout.OtLayout.arabic_script_tag);
}

fn featureIsEnabled(tags: []const [4]u8, needle: [4]u8) bool {
    for (tags) |tag| {
        if (std.mem.eql(u8, &tag, &needle)) return true;
    }
    return false;
}

fn isArabicPositionalFeature(tag: [4]u8) bool {
    for (arabic_positional_features) |feature| {
        if (std.mem.eql(u8, &tag, &feature.tag)) return true;
    }
    return false;
}

fn writeFeatureTable(data: []u8, offset: usize, lookup_index: u16) void {
    test_utils.writeU16(data, offset, 0);
    test_utils.writeU16(data, offset + 2, 1);
    test_utils.writeU16(data, offset + 4, lookup_index);
}

fn writeSingleLookup(data: []u8, offset: usize, source_gid: u16, target_gid: u16) void {
    test_utils.writeU16(data, offset, @intFromEnum(GsubLookupType.single_substitution));
    test_utils.writeU16(data, offset + 2, 0);
    test_utils.writeU16(data, offset + 4, 1);
    test_utils.writeU16(data, offset + 6, 8);

    const subtable_offset = offset + 8;
    test_utils.writeU16(data, subtable_offset, 2);
    test_utils.writeU16(data, subtable_offset + 2, 8);
    test_utils.writeU16(data, subtable_offset + 4, 1);
    test_utils.writeU16(data, subtable_offset + 6, target_gid);
    test_utils.writeU16(data, subtable_offset + 8, 1);
    test_utils.writeU16(data, subtable_offset + 10, 1);
    test_utils.writeU16(data, subtable_offset + 12, source_gid);
}

test "gsub alternate substitution" {
    var subtable = [_]u8{0} ** 20;
    test_utils.writeU16(&subtable, 0, 1); // format
    test_utils.writeU16(&subtable, 2, 8); // coverage_off
    test_utils.writeU16(&subtable, 4, 1); // alt_set_count
    test_utils.writeU16(&subtable, 6, 14); // alt_set_off[0]

    // Coverage (GID 10)
    test_utils.writeU16(&subtable, 8, 1);
    test_utils.writeU16(&subtable, 10, 1);
    test_utils.writeU16(&subtable, 12, 10);

    // AlternateSet (GID 20, 30)
    test_utils.writeU16(&subtable, 14, 2); // count
    test_utils.writeU16(&subtable, 16, 20); // alt[0]
    test_utils.writeU16(&subtable, 18, 30); // alt[1]

    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'A', .glyph_id = 10, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });

    try Gsub.applyAlternateSubstitution(&subtable, &glyphs);
    try std.testing.expectEqual(@as(u16, 20), glyphs.items[0].glyph_id);
}

test "Arabic positional features apply only to matching joining forms" {
    var data = [_]u8{0} ** 220;
    test_utils.writeU16(&data, ot_layout.OtLayout.script_list_offset, 10);
    test_utils.writeU16(&data, ot_layout.OtLayout.feature_list_offset, 40);
    test_utils.writeU16(&data, ot_layout.OtLayout.lookup_list_offset, 96);

    test_utils.writeU16(&data, 10, 1);
    data[12..16].* = ot_layout.OtLayout.arabic_script_tag;
    test_utils.writeU16(&data, 16, 8);
    test_utils.writeU16(&data, 18, 4);
    test_utils.writeU16(&data, 20, 0);
    test_utils.writeU16(&data, 22, 0);
    test_utils.writeU16(&data, 24, ot_layout.OtLayout.required_feature_none);
    test_utils.writeU16(&data, 26, 4);
    test_utils.writeU16(&data, 28, 0);
    test_utils.writeU16(&data, 30, 1);
    test_utils.writeU16(&data, 32, 2);
    test_utils.writeU16(&data, 34, 3);

    test_utils.writeU16(&data, 40, 4);
    data[42..46].* = "isol".*;
    test_utils.writeU16(&data, 46, 26);
    data[48..52].* = "init".*;
    test_utils.writeU16(&data, 52, 32);
    data[54..58].* = "medi".*;
    test_utils.writeU16(&data, 58, 38);
    data[60..64].* = "fina".*;
    test_utils.writeU16(&data, 64, 44);

    writeFeatureTable(&data, 66, 0);
    writeFeatureTable(&data, 72, 1);
    writeFeatureTable(&data, 78, 2);
    writeFeatureTable(&data, 84, 3);

    test_utils.writeU16(&data, 96, 4);
    test_utils.writeU16(&data, 98, 10);
    test_utils.writeU16(&data, 100, 32);
    test_utils.writeU16(&data, 102, 54);
    test_utils.writeU16(&data, 104, 76);
    writeSingleLookup(&data, 106, 10, 99);
    writeSingleLookup(&data, 128, 10, 11);
    writeSingleLookup(&data, 150, 10, 12);
    writeSingleLookup(&data, 172, 20, 21);

    const tables = [_]font_parser.TableMetadata{.{
        .tag = ot_layout.TableTags.gsub,
        .offset = 0,
        .length = data.len,
    }};
    const face = font_parser.Face{
        .data = &data,
        .units_per_em = 1000,
        .num_glyphs = 128,
        .tables = &tables,
        .number_of_h_metrics = 1,
        .number_of_v_metrics = null,
        .vorg_default_vert_origin_y = null,
        .vorg = null,
        .cmap = null,
    };

    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, .{ .codepoint = 0x0645, .glyph_id = 10, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 0x0645, .glyph_id = 10, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 0x0627, .glyph_id = 20, .cluster = 2, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });

    const features = [_][4]u8{ "isol".*, "init".*, "medi".*, "fina".* };
    try Gsub.apply(std.testing.allocator, face, &glyphs, .{
        .script_tag = ot_layout.OtLayout.arabic_script_tag,
        .feature_tags = &features,
    });

    try std.testing.expectEqual(@as(u16, 11), glyphs.items[0].glyph_id);
    try std.testing.expectEqual(@as(u16, 12), glyphs.items[1].glyph_id);
    try std.testing.expectEqual(@as(u16, 21), glyphs.items[2].glyph_id);
}

test "gsub chained contextual substitution format 3" {
    var subtable = [_]u8{0} ** 60;
    test_utils.writeU16(&subtable, 0, 3); // format
    test_utils.writeU16(&subtable, 2, 1); // backtrack_count
    test_utils.writeU16(&subtable, 4, 20); // backtrack_coverages[0]
    test_utils.writeU16(&subtable, 6, 1); // input_count
    test_utils.writeU16(&subtable, 8, 26); // input_coverages[0]
    test_utils.writeU16(&subtable, 10, 1); // lookahead_count
    test_utils.writeU16(&subtable, 12, 32); // lookahead_coverages[0]
    test_utils.writeU16(&subtable, 14, 1); // subst_count
    test_utils.writeU16(&subtable, 16, 0); // subst_index 0
    test_utils.writeU16(&subtable, 18, 0); // lookup_index 0

    // Backtrack Coverage (GID 1)
    test_utils.writeU16(&subtable, 20, 1);
    test_utils.writeU16(&subtable, 22, 1);
    test_utils.writeU16(&subtable, 24, 1);

    // Input Coverage (GID 2)
    test_utils.writeU16(&subtable, 26, 1);
    test_utils.writeU16(&subtable, 28, 1);
    test_utils.writeU16(&subtable, 30, 2);

    // Lookahead Coverage (GID 3)
    test_utils.writeU16(&subtable, 32, 1);
    test_utils.writeU16(&subtable, 34, 1);
    test_utils.writeU16(&subtable, 36, 3);

    // Sub-lookup: Single Substitution (GID 2 -> GID 4)
    var sub_lookup = [_]u8{0} ** 12;
    test_utils.writeU16(&sub_lookup, 0, 1); // format
    test_utils.writeU16(&sub_lookup, 2, 6); // coverage_off
    test_utils.writeI16(&sub_lookup, 4, 2); // delta (2 -> 4)
    test_utils.writeU16(&sub_lookup, 6, 1); // coverage format
    test_utils.writeU16(&sub_lookup, 8, 1); // count
    test_utils.writeU16(&sub_lookup, 10, 2); // GID 2

    // Lookup List containing the sub-lookup
    var lookup_list = [_]u8{0} ** 30;
    test_utils.writeU16(&lookup_list, 0, 1); // count
    test_utils.writeU16(&lookup_list, 2, 4); // offset to lookup 0
    // Lookup 0
    test_utils.writeU16(&lookup_list, 4, 1); // type (Single)
    test_utils.writeU16(&lookup_list, 6, 0); // flag
    test_utils.writeU16(&lookup_list, 8, 1); // subtable count
    test_utils.writeU16(&lookup_list, 10, 8); // subtable offset (relative to 4, so at 12)
    @memcpy(lookup_list[12 .. 12 + sub_lookup.len], &sub_lookup);

    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'B', .glyph_id = 2, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'C', .glyph_id = 3, .cluster = 2, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });

    const face: font_parser.Face = undefined;
    try Gsub.applyChainedContextualSubstitution(std.testing.allocator, face, &lookup_list, &subtable, &glyphs, 0);

    try std.testing.expectEqual(@as(u16, 4), glyphs.items[1].glyph_id);
}

test "gsub chained contextual substitution format 1" {
    var subtable = [_]u8{0} ** 40;
    test_utils.writeU16(&subtable, 0, 1); // format
    test_utils.writeU16(&subtable, 2, 8); // coverage_off
    test_utils.writeU16(&subtable, 4, 1); // rule_set_count
    test_utils.writeU16(&subtable, 6, 14); // rule_set_offsets[0]

    // Coverage (input GID 2)
    test_utils.writeU16(&subtable, 8, 1);
    test_utils.writeU16(&subtable, 10, 1);
    test_utils.writeU16(&subtable, 12, 2);

    // ChainRuleSet
    test_utils.writeU16(&subtable, 14, 1); // rule_count
    test_utils.writeU16(&subtable, 16, 4); // rule offset relative to set

    // ChainSubRule: backtrack 1, input 2, lookahead 3 -> lookup 0 on input
    test_utils.writeU16(&subtable, 18, 1); // backtrack_count
    test_utils.writeU16(&subtable, 20, 1); // backtrack glyph
    test_utils.writeU16(&subtable, 22, 1); // input_count
    test_utils.writeU16(&subtable, 24, 1); // lookahead_count
    test_utils.writeU16(&subtable, 26, 3); // lookahead glyph
    test_utils.writeU16(&subtable, 28, 1); // subst_count
    test_utils.writeU16(&subtable, 30, 0); // sequence_index
    test_utils.writeU16(&subtable, 32, 0); // lookup_index

    var sub_lookup = [_]u8{0} ** 12;
    test_utils.writeU16(&sub_lookup, 0, 1);
    test_utils.writeU16(&sub_lookup, 2, 6);
    test_utils.writeI16(&sub_lookup, 4, 2);
    test_utils.writeU16(&sub_lookup, 6, 1);
    test_utils.writeU16(&sub_lookup, 8, 1);
    test_utils.writeU16(&sub_lookup, 10, 2);

    var lookup_list = [_]u8{0} ** 30;
    test_utils.writeU16(&lookup_list, 0, 1);
    test_utils.writeU16(&lookup_list, 2, 4);
    test_utils.writeU16(&lookup_list, 4, 1);
    test_utils.writeU16(&lookup_list, 6, 0);
    test_utils.writeU16(&lookup_list, 8, 1);
    test_utils.writeU16(&lookup_list, 10, 8);
    @memcpy(lookup_list[12 .. 12 + sub_lookup.len], &sub_lookup);

    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'B', .glyph_id = 2, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'C', .glyph_id = 3, .cluster = 2, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });

    const face: font_parser.Face = undefined;
    try Gsub.applyChainedContextualSubstitution(std.testing.allocator, face, &lookup_list, &subtable, &glyphs, 0);

    try std.testing.expectEqual(@as(u16, 4), glyphs.items[1].glyph_id);
}

test "gsub chained contextual substitution format 2" {
    var subtable = [_]u8{0} ** 74;
    test_utils.writeU16(&subtable, 0, 2); // format
    test_utils.writeU16(&subtable, 2, 16); // coverage_off
    test_utils.writeU16(&subtable, 4, 22); // backtrack_class_def_off
    test_utils.writeU16(&subtable, 6, 32); // input_class_def_off
    test_utils.writeU16(&subtable, 8, 42); // lookahead_class_def_off
    test_utils.writeU16(&subtable, 10, 2); // class_set_count
    test_utils.writeU16(&subtable, 12, 0); // class 0 set
    test_utils.writeU16(&subtable, 14, 52); // class 1 set

    // Coverage (input GID 2)
    test_utils.writeU16(&subtable, 16, 1);
    test_utils.writeU16(&subtable, 18, 1);
    test_utils.writeU16(&subtable, 20, 2);

    // ClassDef Format 2 for backtrack GID 1 -> class 1
    test_utils.writeU16(&subtable, 22, 2);
    test_utils.writeU16(&subtable, 24, 1);
    test_utils.writeU16(&subtable, 26, 1);
    test_utils.writeU16(&subtable, 28, 1);
    test_utils.writeU16(&subtable, 30, 1);

    // ClassDef Format 2 for input GID 2 -> class 1
    test_utils.writeU16(&subtable, 32, 2);
    test_utils.writeU16(&subtable, 34, 1);
    test_utils.writeU16(&subtable, 36, 2);
    test_utils.writeU16(&subtable, 38, 2);
    test_utils.writeU16(&subtable, 40, 1);

    // ClassDef Format 2 for lookahead GID 3 -> class 1
    test_utils.writeU16(&subtable, 42, 2);
    test_utils.writeU16(&subtable, 44, 1);
    test_utils.writeU16(&subtable, 46, 3);
    test_utils.writeU16(&subtable, 48, 3);
    test_utils.writeU16(&subtable, 50, 1);

    // ChainSubClassSet for input class 1
    test_utils.writeU16(&subtable, 52, 1); // class_rule_count
    test_utils.writeU16(&subtable, 54, 4); // class_rule offset relative to set

    // ChainSubClassRule: backtrack class 1, input class 1, lookahead class 1
    test_utils.writeU16(&subtable, 56, 1); // backtrack_count
    test_utils.writeU16(&subtable, 58, 1); // backtrack class
    test_utils.writeU16(&subtable, 60, 1); // input_count
    test_utils.writeU16(&subtable, 62, 1); // lookahead_count
    test_utils.writeU16(&subtable, 64, 1); // lookahead class
    test_utils.writeU16(&subtable, 66, 1); // subst_count
    test_utils.writeU16(&subtable, 68, 0); // sequence_index
    test_utils.writeU16(&subtable, 70, 0); // lookup_index

    var sub_lookup = [_]u8{0} ** 12;
    test_utils.writeU16(&sub_lookup, 0, 1);
    test_utils.writeU16(&sub_lookup, 2, 6);
    test_utils.writeI16(&sub_lookup, 4, 2);
    test_utils.writeU16(&sub_lookup, 6, 1);
    test_utils.writeU16(&sub_lookup, 8, 1);
    test_utils.writeU16(&sub_lookup, 10, 2);

    var lookup_list = [_]u8{0} ** 30;
    test_utils.writeU16(&lookup_list, 0, 1);
    test_utils.writeU16(&lookup_list, 2, 4);
    test_utils.writeU16(&lookup_list, 4, 1);
    test_utils.writeU16(&lookup_list, 6, 0);
    test_utils.writeU16(&lookup_list, 8, 1);
    test_utils.writeU16(&lookup_list, 10, 8);
    @memcpy(lookup_list[12 .. 12 + sub_lookup.len], &sub_lookup);

    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'B', .glyph_id = 2, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'C', .glyph_id = 3, .cluster = 2, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });

    const face: font_parser.Face = undefined;
    try Gsub.applyChainedContextualSubstitution(std.testing.allocator, face, &lookup_list, &subtable, &glyphs, 0);

    try std.testing.expectEqual(@as(u16, 4), glyphs.items[1].glyph_id);
}

test "gsub contextual substitution format 1" {
    var subtable = [_]u8{0} ** 32;
    test_utils.writeU16(&subtable, 0, 1); // format
    test_utils.writeU16(&subtable, 2, 8); // coverage_off
    test_utils.writeU16(&subtable, 4, 1); // rule_set_count
    test_utils.writeU16(&subtable, 6, 14); // rule_set_offsets[0]

    // Coverage (first glyph GID 10)
    test_utils.writeU16(&subtable, 8, 1);
    test_utils.writeU16(&subtable, 10, 1);
    test_utils.writeU16(&subtable, 12, 10);

    // RuleSet
    test_utils.writeU16(&subtable, 14, 1); // rule_count
    test_utils.writeU16(&subtable, 16, 4); // rule offset relative to RuleSet

    // ContextRule: 10 11 -> apply lookup 0 to second glyph
    test_utils.writeU16(&subtable, 18, 2); // glyph_count
    test_utils.writeU16(&subtable, 20, 1); // subst_count
    test_utils.writeU16(&subtable, 22, 11); // input_sequence[0]
    test_utils.writeU16(&subtable, 24, 1); // sequence_index
    test_utils.writeU16(&subtable, 26, 0); // lookup_index

    var sub_lookup = [_]u8{0} ** 12;
    test_utils.writeU16(&sub_lookup, 0, 1); // format
    test_utils.writeU16(&sub_lookup, 2, 6); // coverage_off
    test_utils.writeI16(&sub_lookup, 4, 9); // delta (11 -> 20)
    test_utils.writeU16(&sub_lookup, 6, 1);
    test_utils.writeU16(&sub_lookup, 8, 1);
    test_utils.writeU16(&sub_lookup, 10, 11);

    var lookup_list = [_]u8{0} ** 30;
    test_utils.writeU16(&lookup_list, 0, 1);
    test_utils.writeU16(&lookup_list, 2, 4);
    test_utils.writeU16(&lookup_list, 4, 1);
    test_utils.writeU16(&lookup_list, 6, 0);
    test_utils.writeU16(&lookup_list, 8, 1);
    test_utils.writeU16(&lookup_list, 10, 8);
    @memcpy(lookup_list[12 .. 12 + sub_lookup.len], &sub_lookup);

    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'A', .glyph_id = 10, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'B', .glyph_id = 11, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });

    const face: font_parser.Face = undefined;
    try Gsub.applyContextualSubstitution(std.testing.allocator, face, &lookup_list, &subtable, &glyphs, 0);

    try std.testing.expectEqual(@as(u16, 10), glyphs.items[0].glyph_id);
    try std.testing.expectEqual(@as(u16, 20), glyphs.items[1].glyph_id);
}

test "gsub contextual substitution handles length-changing sublookups" {
    var subtable = [_]u8{0} ** 32;
    test_utils.writeU16(&subtable, 0, 1); // format
    test_utils.writeU16(&subtable, 2, 8); // coverage_off
    test_utils.writeU16(&subtable, 4, 1); // rule_set_count
    test_utils.writeU16(&subtable, 6, 14); // rule_set_offsets[0]

    // Coverage (first glyph GID 10)
    test_utils.writeU16(&subtable, 8, 1);
    test_utils.writeU16(&subtable, 10, 1);
    test_utils.writeU16(&subtable, 12, 10);

    // RuleSet
    test_utils.writeU16(&subtable, 14, 1); // rule_count
    test_utils.writeU16(&subtable, 16, 4); // rule offset relative to RuleSet

    // ContextRule: 10 11 -> apply lookup 0 at sequence start
    test_utils.writeU16(&subtable, 18, 2); // glyph_count
    test_utils.writeU16(&subtable, 20, 1); // subst_count
    test_utils.writeU16(&subtable, 22, 11); // input_sequence[0]
    test_utils.writeU16(&subtable, 24, 0); // sequence_index
    test_utils.writeU16(&subtable, 26, 0); // lookup_index

    var ligature = [_]u8{0} ** 24;
    test_utils.writeU16(&ligature, 2, 8); // coverage_off
    test_utils.writeU16(&ligature, 4, 1); // ligature_set_count
    test_utils.writeU16(&ligature, 6, 14); // ligature_set_offsets[0]
    test_utils.writeU16(&ligature, 8, 1); // coverage format
    test_utils.writeU16(&ligature, 10, 1); // coverage count
    test_utils.writeU16(&ligature, 12, 10); // first glyph
    test_utils.writeU16(&ligature, 14, 1); // ligature_count
    test_utils.writeU16(&ligature, 16, 4); // ligature offset relative to set
    test_utils.writeU16(&ligature, 18, 50); // ligature glyph
    test_utils.writeU16(&ligature, 20, 2); // component count
    test_utils.writeU16(&ligature, 22, 11); // second component

    var lookup_list = [_]u8{0} ** 42;
    test_utils.writeU16(&lookup_list, 0, 1);
    test_utils.writeU16(&lookup_list, 2, 4);
    test_utils.writeU16(&lookup_list, 4, 4); // Ligature Substitution
    test_utils.writeU16(&lookup_list, 6, 0);
    test_utils.writeU16(&lookup_list, 8, 1);
    test_utils.writeU16(&lookup_list, 10, 8);
    @memcpy(lookup_list[12 .. 12 + ligature.len], &ligature);

    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'A', .glyph_id = 10, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'B', .glyph_id = 11, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'C', .glyph_id = 12, .cluster = 2, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });

    const face: font_parser.Face = undefined;
    try Gsub.applyContextualSubstitution(std.testing.allocator, face, &lookup_list, &subtable, &glyphs, 0);

    try std.testing.expectEqual(@as(usize, 2), glyphs.items.len);
    try std.testing.expectEqual(@as(u16, 50), glyphs.items[0].glyph_id);
    try std.testing.expectEqual(@as(u16, 12), glyphs.items[1].glyph_id);
}

test "gsub contextual substitution format 2" {
    var subtable = [_]u8{0} ** 52;
    test_utils.writeU16(&subtable, 0, 2); // format
    test_utils.writeU16(&subtable, 2, 12); // coverage_off
    test_utils.writeU16(&subtable, 4, 18); // class_def_off
    test_utils.writeU16(&subtable, 6, 2); // class_set_count
    test_utils.writeU16(&subtable, 8, 0); // class 0 has no set
    test_utils.writeU16(&subtable, 10, 34); // class 1 set

    // Coverage (first glyph GID 10)
    test_utils.writeU16(&subtable, 12, 1);
    test_utils.writeU16(&subtable, 14, 1);
    test_utils.writeU16(&subtable, 16, 10);

    // ClassDef Format 2: GID 10 -> class 1, GID 11 -> class 2
    test_utils.writeU16(&subtable, 18, 2);
    test_utils.writeU16(&subtable, 20, 2);
    test_utils.writeU16(&subtable, 22, 10);
    test_utils.writeU16(&subtable, 24, 10);
    test_utils.writeU16(&subtable, 26, 1);
    test_utils.writeU16(&subtable, 28, 11);
    test_utils.writeU16(&subtable, 30, 11);
    test_utils.writeU16(&subtable, 32, 2);

    // ClassSet for class 1
    test_utils.writeU16(&subtable, 34, 1); // class_rule_count
    test_utils.writeU16(&subtable, 36, 4); // class_rule offset relative to ClassSet

    // ClassRule: class 1 then class 2 -> apply lookup 0 to second glyph
    test_utils.writeU16(&subtable, 38, 2); // glyph_count
    test_utils.writeU16(&subtable, 40, 1); // subst_count
    test_utils.writeU16(&subtable, 42, 2); // input class for second glyph
    test_utils.writeU16(&subtable, 44, 1); // sequence_index
    test_utils.writeU16(&subtable, 46, 0); // lookup_index

    var sub_lookup = [_]u8{0} ** 12;
    test_utils.writeU16(&sub_lookup, 0, 1); // format
    test_utils.writeU16(&sub_lookup, 2, 6); // coverage_off
    test_utils.writeI16(&sub_lookup, 4, 9); // delta (11 -> 20)
    test_utils.writeU16(&sub_lookup, 6, 1);
    test_utils.writeU16(&sub_lookup, 8, 1);
    test_utils.writeU16(&sub_lookup, 10, 11);

    var lookup_list = [_]u8{0} ** 30;
    test_utils.writeU16(&lookup_list, 0, 1);
    test_utils.writeU16(&lookup_list, 2, 4);
    test_utils.writeU16(&lookup_list, 4, 1);
    test_utils.writeU16(&lookup_list, 6, 0);
    test_utils.writeU16(&lookup_list, 8, 1);
    test_utils.writeU16(&lookup_list, 10, 8);
    @memcpy(lookup_list[12 .. 12 + sub_lookup.len], &sub_lookup);

    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'A', .glyph_id = 10, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'B', .glyph_id = 11, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });

    const face: font_parser.Face = undefined;
    try Gsub.applyContextualSubstitution(std.testing.allocator, face, &lookup_list, &subtable, &glyphs, 0);

    try std.testing.expectEqual(@as(u16, 10), glyphs.items[0].glyph_id);
    try std.testing.expectEqual(@as(u16, 20), glyphs.items[1].glyph_id);
}

test "gsub recursive lookup depth is rejected" {
    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });

    const face: font_parser.Face = undefined;
    try std.testing.expectError(
        font_parser.ParserError.InvalidTable,
        Gsub.applyLookup(std.testing.allocator, face, &[_]u8{}, 0, &glyphs, Gsub.max_recursion_depth),
    );
}
