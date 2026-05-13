const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");
const ot_layout = @import("ot_layout.zig");
const types = @import("shaper_types.zig");
const test_utils = @import("shaper_test_utils.zig");

const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;
const LayoutError = types.LayoutError;
const ShapeOptions = types.ShapeOptions;
const ShapedGlyph = types.ShapedGlyph;

const GsubLookupType = enum(u16) {
    single_substitution = 1,
    alternate_substitution = 3,
    ligature_substitution = 4,
    contextual_substitution = 5,
    chained_contextual_substitution = 6,
};

pub const Gsub = struct {
    pub const max_recursion_depth = 16;

    const single_format_offset = 0;
    const single_coverage_offset = 2;
    const single_f1_delta_offset = 4;
    const single_f2_count_offset = 4;
    const single_f2_substitutes_offset = 6;

    const lig_coverage_offset = 2;
    const lig_set_count_offset = 4;
    const lig_set_offsets_offset = 6;
    const lig_set_ligature_count_offset = 0;
    const lig_set_lig_offsets_offset = 2;
    const lig_glyph_offset = 0;
    const lig_comp_count_offset = 2;
    const lig_comp_ids_offset = 4;

    const alt_format_offset = 0;
    const alt_coverage_offset = 2;
    const alt_set_count_offset = 4;
    const alt_set_offsets_offset = 6;
    const alt_set_glyph_count_offset = 0;
    const alt_set_alternate_glyphs_offset = 2;

    pub fn applyAlternateSubstitution(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        const format = try readU16(subtable, alt_format_offset);
        if (format != 1) return;

        const coverage_off = try readU16(subtable, alt_coverage_offset);
        const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);
        const alt_set_count = try readU16(subtable, alt_set_count_offset);

        for (glyphs.items) |*glyph| {
            const index = try ot_layout.Coverage.getIndex(coverage_data, glyph.glyph_id) orelse continue;
            if (index >= alt_set_count) return font_parser.ParserError.InvalidTable;

            const alt_set_off = try readU16(subtable, alt_set_offsets_offset + @as(usize, index) * 2);
            const alt_set_data = try ot_layout.sliceFrom(subtable, alt_set_off);
            const glyph_count = try readU16(alt_set_data, alt_set_glyph_count_offset);
            if (glyph_count == 0) continue;

            // Default to the first alternate
            glyph.glyph_id = try readU16(alt_set_data, alt_set_alternate_glyphs_offset);
        }
    }

    pub fn applyContextualSubstitution(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        const format = try readU16(subtable, 0);
        if (format == 3) {
            try applyContextualFormat3(allocator, face, lookup_list, subtable, glyphs, depth);
        }
    }

    pub fn applyContextualFormat3(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        var offset: usize = 2;

        const input_count = try readU16(subtable, offset);
        offset += 2;
        const input_coverages = try ot_layout.sliceRange(subtable, offset, @as(usize, input_count) * 2);
        offset += @as(usize, input_count) * 2;

        const subst_count = try readU16(subtable, offset);
        offset += 2;
        const subst_records = try ot_layout.sliceRange(subtable, offset, @as(usize, subst_count) * 4);

        var i: usize = 0;
        while (i < glyphs.items.len) {
            if (try matchChainedContextFormat3(subtable, &[_]u8{}, input_coverages, &[_]u8{}, glyphs.items, i)) {
                for (0..subst_count) |j| {
                    const subst_rel_idx = try readU16(subst_records, j * 4);
                    const lookup_index = try readU16(subst_records, j * 4 + 2);

                    if (i + subst_rel_idx < glyphs.items.len) {
                        var sub_glyphs = std.ArrayList(ShapedGlyph).empty;
                        defer sub_glyphs.deinit(allocator);
                        try sub_glyphs.appendSlice(allocator, glyphs.items[i + subst_rel_idx ..]);
                        try applyLookup(allocator, face, lookup_list, lookup_index, &sub_glyphs, depth + 1);
                        const old_len = glyphs.items.len - (i + subst_rel_idx);
                        const new_len = sub_glyphs.items.len;
                        if (new_len == old_len) {
                            @memcpy(glyphs.items[i + subst_rel_idx ..], sub_glyphs.items);
                        }
                    }
                }
                i += input_count;
            } else {
                i += 1;
            }
        }
    }

    pub fn apply(allocator: std.mem.Allocator, face: font_parser.Face, glyphs: *std.ArrayList(ShapedGlyph), options: ShapeOptions) LayoutError!void {
        const data = face.getTable(ot_layout.TableTags.gsub) orelse return;
        if (data.len < ot_layout.OtLayout.header_min_size) return font_parser.ParserError.InvalidTable;

        const lookup_list_off = try readU16(data, ot_layout.OtLayout.lookup_list_offset);
        const lookup_list_data = try ot_layout.sliceFrom(data, lookup_list_off);

        var lookup_indices = try ot_layout.OtLayout.collectLookupIndices(allocator, data, options);
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
                try applySingleSubstitution(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GsubLookupType.alternate_substitution)) {
                try applyAlternateSubstitution(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GsubLookupType.ligature_substitution)) {
                try applyLigatureSubstitution(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GsubLookupType.contextual_substitution)) {
                try applyContextualSubstitution(allocator, face, lookup_list, subtable_data, glyphs, depth);
            } else if (lookup_type == @intFromEnum(GsubLookupType.chained_contextual_substitution)) {
                try applyChainedContextualSubstitution(allocator, face, lookup_list, subtable_data, glyphs, depth);
            }
        }
    }

    pub fn applyLigatureSubstitution(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        const coverage_off = try readU16(subtable, lig_coverage_offset);
        const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);
        const ligature_set_count = try readU16(subtable, lig_set_count_offset);

        var i: usize = 0;
        while (i < glyphs.items.len) {
            const index = try ot_layout.Coverage.getIndex(coverage_data, glyphs.items[i].glyph_id) orelse {
                i += 1;
                continue;
            };

            if (index >= ligature_set_count) return font_parser.ParserError.InvalidTable;
            const ligature_set_off = try readU16(subtable, lig_set_offsets_offset + @as(usize, index) * 2);
            const ligature_set_data = try ot_layout.sliceFrom(subtable, ligature_set_off);
            const ligature_count = try readU16(ligature_set_data, lig_set_ligature_count_offset);

            var matched = false;
            for (0..ligature_count) |j| {
                const ligature_off = try readU16(ligature_set_data, lig_set_lig_offsets_offset + j * 2);
                const ligature_data = try ot_layout.sliceFrom(ligature_set_data, ligature_off);
                const lig_glyph = try readU16(ligature_data, lig_glyph_offset);
                const comp_count = try readU16(ligature_data, lig_comp_count_offset);

                if (i + comp_count <= glyphs.items.len) {
                    var match = true;
                    for (1..comp_count) |k| {
                        const comp_glyph = try readU16(ligature_data, lig_comp_ids_offset + (k - 1) * 2);
                        if (glyphs.items[i + k].glyph_id != comp_glyph) {
                            match = false;
                            break;
                        }
                    }

                    if (match) {
                        const first = glyphs.items[i];
                        glyphs.items[i] = .{
                            .codepoint = 0,
                            .glyph_id = lig_glyph,
                            .cluster = first.cluster,
                            .x_offset = 0,
                            .y_offset = 0,
                            .x_advance = 0,
                            .y_advance = 0,
                            .advance_width = 0,
                            .lsb = 0,
                            .kern_adjustment = 0,
                        };

                        for (1..comp_count) |_| {
                            _ = glyphs.orderedRemove(i + 1);
                        }
                        matched = true;
                        break;
                    }
                }
            }

            if (!matched) {
                i += 1;
            }
        }
    }

    pub fn applySingleSubstitution(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        const format = try readU16(subtable, single_format_offset);
        const coverage_off = try readU16(subtable, single_coverage_offset);
        const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);

        for (glyphs.items) |*glyph| {
            if (try ot_layout.Coverage.getIndex(coverage_data, glyph.glyph_id)) |index| {
                if (format == 1) {
                    const delta = try readI16(subtable, single_f1_delta_offset);
                    glyph.glyph_id = @intCast(@mod(@as(i32, glyph.glyph_id) + delta, 65536));
                } else if (format == 2) {
                    const count = try readU16(subtable, single_f2_count_offset);
                    if (index >= count) return font_parser.ParserError.InvalidTable;
                    glyph.glyph_id = try readU16(subtable, single_f2_substitutes_offset + @as(usize, index) * 2);
                }
            }
        }
    }

    pub fn applyChainedContextualSubstitution(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        const format = try readU16(subtable, 0);
        if (format == 3) {
            try applyChainedContextualFormat3(allocator, face, lookup_list, subtable, glyphs, depth);
        }
    }

    pub fn applyChainedContextualFormat3(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        var offset: usize = 2;

        const backtrack_count = try readU16(subtable, offset);
        offset += 2;
        const backtrack_coverages = try ot_layout.sliceRange(subtable, offset, @as(usize, backtrack_count) * 2);
        offset += @as(usize, backtrack_count) * 2;

        const input_count = try readU16(subtable, offset);
        offset += 2;
        const input_coverages = try ot_layout.sliceRange(subtable, offset, @as(usize, input_count) * 2);
        offset += @as(usize, input_count) * 2;

        const lookahead_count = try readU16(subtable, offset);
        offset += 2;
        const lookahead_coverages = try ot_layout.sliceRange(subtable, offset, @as(usize, lookahead_count) * 2);
        offset += @as(usize, lookahead_count) * 2;

        const subst_count = try readU16(subtable, offset);
        offset += 2;
        const subst_records = try ot_layout.sliceRange(subtable, offset, @as(usize, subst_count) * 4);

        var i: usize = 0;
        while (i < glyphs.items.len) {
            if (try matchChainedContextFormat3(subtable, backtrack_coverages, input_coverages, lookahead_coverages, glyphs.items, i)) {
                for (0..subst_count) |j| {
                    const subst_rel_idx = try readU16(subst_records, j * 4);
                    const lookup_index = try readU16(subst_records, j * 4 + 2);

                    if (i + subst_rel_idx < glyphs.items.len) {
                        var sub_glyphs = std.ArrayList(ShapedGlyph).empty;
                        defer sub_glyphs.deinit(allocator);
                        try sub_glyphs.appendSlice(allocator, glyphs.items[i + subst_rel_idx ..]);

                        try applyLookup(allocator, face, lookup_list, lookup_index, &sub_glyphs, depth + 1);

                        const old_len = glyphs.items.len - (i + subst_rel_idx);
                        const new_len = sub_glyphs.items.len;

                        if (new_len == old_len) {
                            @memcpy(glyphs.items[i + subst_rel_idx ..], sub_glyphs.items);
                        }
                    }
                }
                i += input_count;
            } else {
                i += 1;
            }
        }
    }

    pub fn matchChainedContextFormat3(subtable: []const u8, backtrack: []const u8, input: []const u8, lookahead: []const u8, glyphs: []const ShapedGlyph, pos: usize) font_parser.ParserError!bool {
        const backtrack_count = @as(u16, @intCast(backtrack.len / 2));
        const input_count = @as(u16, @intCast(input.len / 2));
        const lookahead_count = @as(u16, @intCast(lookahead.len / 2));

        if (pos + input_count > glyphs.len) return false;
        for (0..input_count) |j| {
            const coverage_off = try readU16(input, j * 2);
            const coverage = try ot_layout.sliceFrom(subtable, coverage_off);
            if (try ot_layout.Coverage.getIndex(coverage, glyphs[pos + j].glyph_id) == null) return false;
        }

        if (pos < backtrack_count) return false;
        for (0..backtrack_count) |j| {
            const coverage_off = try readU16(backtrack, j * 2);
            const coverage = try ot_layout.sliceFrom(subtable, coverage_off);
            if (try ot_layout.Coverage.getIndex(coverage, glyphs[pos - 1 - j].glyph_id) == null) return false;
        }

        if (pos + input_count + lookahead_count > glyphs.len) return false;
        for (0..lookahead_count) |j| {
            const coverage_off = try readU16(lookahead, j * 2);
            const coverage = try ot_layout.sliceFrom(subtable, coverage_off);
            if (try ot_layout.Coverage.getIndex(coverage, glyphs[pos + input_count + j].glyph_id) == null) return false;
        }

        return true;
    }
};

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
