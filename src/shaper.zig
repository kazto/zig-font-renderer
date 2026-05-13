const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");

const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;

const LayoutError = font_parser.ParserError || std.mem.Allocator.Error;

const TableTags = struct {
    const kern = "kern".*;
    const gsub = "GSUB".*;
    const gpos = "GPOS".*;
};

const OtLayout = struct {
    const default_script_tag = "DFLT".*;
    const latin_script_tag = "latn".*;
    const required_feature_none = 0xffff;

    const header_min_size = 10;
    const script_list_offset = 4;
    const feature_list_offset = 6;
    const lookup_list_offset = 8;

    const script_default_lang_sys_offset = 0;
    const script_lang_sys_count_offset = 2;
    const script_lang_sys_records_offset = 4;
    const script_lang_sys_record_size = 6;
    const script_lang_sys_tag_offset = 0;
    const script_lang_sys_offset_offset = 4;

    const lang_sys_required_feature_index_offset = 2;
    const lang_sys_feature_count_offset = 4;
    const lang_sys_feature_indices_offset = 6;
    const feature_data_lookup_count_offset = 2;
    const feature_data_lookup_indices_offset = 4;

    const lookup_type_offset = 0;
    const lookup_subtable_count_offset = 4;
    const lookup_subtable_offsets_offset = 6;

    const script_list_count_offset = 0;
    const script_record_size = 6;
    const script_tag_offset = 0;
    const script_offset_offset = 4;

    const feature_list_count_offset = 0;
    const feature_record_size = 6;
    const feature_tag_offset = 0;
    const feature_offset_offset = 4;

    const lookup_list_count_offset = 0;
    const lookup_offset_size = 2;
    const lookup_list_header_size = 2;

    fn findScriptOffset(data: []const u8, tag: [4]u8) font_parser.ParserError!?u16 {
        if (data.len < 2) return font_parser.ParserError.InvalidTable;
        const count = try readU16(data, script_list_count_offset);
        if (2 + @as(usize, count) * script_record_size > data.len) return font_parser.ParserError.InvalidTable;
        for (0..count) |i| {
            const offset = 2 + i * script_record_size;
            if (std.mem.eql(u8, data[offset + script_tag_offset ..][0..4], &tag)) {
                return try readU16(data, offset + script_offset_offset);
            }
        }
        return null;
    }

    fn findLangSysOffset(script_data: []const u8, tag: [4]u8) font_parser.ParserError!?u16 {
        if (script_data.len < script_lang_sys_records_offset) return font_parser.ParserError.InvalidTable;
        const count = try readU16(script_data, script_lang_sys_count_offset);
        if (script_lang_sys_records_offset + @as(usize, count) * script_lang_sys_record_size > script_data.len) return font_parser.ParserError.InvalidTable;

        for (0..count) |i| {
            const offset = script_lang_sys_records_offset + i * script_lang_sys_record_size;
            if (std.mem.eql(u8, script_data[offset + script_lang_sys_tag_offset ..][0..4], &tag)) {
                return try readU16(script_data, offset + script_lang_sys_offset_offset);
            }
        }
        return null;
    }

    fn getFeatureRecordOffset(feature_list: []const u8, feature_index: u16) font_parser.ParserError!usize {
        if (feature_list.len < feature_list_count_offset + 2) return font_parser.ParserError.InvalidTable;
        const feature_count = try readU16(feature_list, feature_list_count_offset);
        if (feature_index >= feature_count) return font_parser.ParserError.InvalidTable;
        const feature_offset = feature_list_count_offset + 2 + @as(usize, feature_index) * feature_record_size;
        if (feature_offset + feature_record_size > feature_list.len) return font_parser.ParserError.InvalidTable;
        return feature_offset;
    }

    fn featureMatches(feature_list: []const u8, feature_index: u16, selected_tags: ?[]const [4]u8) font_parser.ParserError!bool {
        const tags = selected_tags orelse return true;
        const feature_record_offset = try getFeatureRecordOffset(feature_list, feature_index);
        const feature_tag = feature_list[feature_record_offset + feature_tag_offset ..][0..4];
        for (tags) |tag| {
            if (std.mem.eql(u8, feature_tag, &tag)) return true;
        }
        return false;
    }

    fn appendLookupIndicesForFeature(feature_list: []const u8, feature_index: u16, lookup_indices: *std.ArrayList(u16), allocator: std.mem.Allocator) LayoutError!void {
        const feature_record_offset = try getFeatureRecordOffset(feature_list, feature_index);
        const feature_data_off = try readU16(feature_list, feature_record_offset + feature_offset_offset);
        const feature_data = try sliceFrom(feature_list, feature_data_off);
        const lookup_count = try readU16(feature_data, feature_data_lookup_count_offset);

        for (0..lookup_count) |i| {
            const lookup_index = try readU16(feature_data, feature_data_lookup_indices_offset + i * 2);
            try lookup_indices.append(allocator, lookup_index);
        }
    }

    fn collectLookupIndices(allocator: std.mem.Allocator, data: []const u8, options: ShapeOptions) LayoutError!std.ArrayList(u16) {
        var result = std.ArrayList(u16).empty;
        errdefer result.deinit(allocator);

        if (data.len < header_min_size) return font_parser.ParserError.InvalidTable;

        const script_list_off = try readU16(data, script_list_offset);
        const feature_list_off = try readU16(data, feature_list_offset);
        const script_list_data = try sliceFrom(data, script_list_off);
        const feature_list_data = try sliceFrom(data, feature_list_off);

        const script_off_val = if (options.script_tag) |script_tag|
            try findScriptOffset(script_list_data, script_tag)
        else blk: {
            var script_off = try findScriptOffset(script_list_data, default_script_tag);
            if (script_off == null) script_off = try findScriptOffset(script_list_data, latin_script_tag);
            break :blk script_off;
        };
        const actual_script_off = script_off_val orelse return result;
        const script_data = try sliceFrom(script_list_data, actual_script_off);

        const lang_sys_off_val = if (options.language_tag) |language_tag|
            try findLangSysOffset(script_data, language_tag)
        else
            null;
        const lang_sys_off = lang_sys_off_val orelse try readU16(script_data, script_default_lang_sys_offset);
        if (lang_sys_off == 0) return result;

        const lang_sys_data = try sliceFrom(script_data, lang_sys_off);
        const required_feature_index = try readU16(lang_sys_data, lang_sys_required_feature_index_offset);
        if (required_feature_index != required_feature_none) {
            try appendLookupIndicesForFeature(feature_list_data, required_feature_index, &result, allocator);
        }

        const feature_count = try readU16(lang_sys_data, lang_sys_feature_count_offset);
        for (0..feature_count) |i| {
            const feature_index = try readU16(lang_sys_data, lang_sys_feature_indices_offset + i * 2);
            if (try featureMatches(feature_list_data, feature_index, options.feature_tags)) {
                try appendLookupIndicesForFeature(feature_list_data, feature_index, &result, allocator);
            }
        }

        return result;
    }

    fn getLookupOffset(data: []const u8, index: u16) font_parser.ParserError!u16 {
        if (data.len < lookup_list_header_size) return font_parser.ParserError.InvalidTable;
        const count = try readU16(data, lookup_list_count_offset);
        if (index >= count) return font_parser.ParserError.InvalidTable;
        if (lookup_list_header_size + @as(usize, count) * lookup_offset_size > data.len) return font_parser.ParserError.InvalidTable;
        return try readU16(data, lookup_list_header_size + @as(usize, index) * lookup_offset_size);
    }
};

const GsubLookupType = enum(u16) {
    single_substitution = 1,
    alternate_substitution = 3,
    ligature_substitution = 4,
    contextual_substitution = 5,
    chained_contextual_substitution = 6,
};

const Gsub = struct {
    const max_recursion_depth = 16;

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

    fn applyAlternateSubstitution(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        const format = try readU16(subtable, alt_format_offset);
        if (format != 1) return;

        const coverage_off = try readU16(subtable, alt_coverage_offset);
        const coverage_data = try sliceFrom(subtable, coverage_off);
        const alt_set_count = try readU16(subtable, alt_set_count_offset);

        for (glyphs.items) |*glyph| {
            const index = try Coverage.getIndex(coverage_data, glyph.glyph_id) orelse continue;
            if (index >= alt_set_count) return font_parser.ParserError.InvalidTable;

            const alt_set_off = try readU16(subtable, alt_set_offsets_offset + @as(usize, index) * 2);
            const alt_set_data = try sliceFrom(subtable, alt_set_off);
            const glyph_count = try readU16(alt_set_data, alt_set_glyph_count_offset);
            if (glyph_count == 0) continue;

            // Default to the first alternate
            glyph.glyph_id = try readU16(alt_set_data, alt_set_alternate_glyphs_offset);
        }
    }

    fn applyContextualSubstitution(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        const format = try readU16(subtable, 0);
        if (format == 3) {
            try applyContextualFormat3(allocator, face, lookup_list, subtable, glyphs, depth);
        }
    }

    fn applyContextualFormat3(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        var offset: usize = 2;

        const input_count = try readU16(subtable, offset);
        offset += 2;
        const input_coverages = try sliceRange(subtable, offset, @as(usize, input_count) * 2);
        offset += @as(usize, input_count) * 2;

        const subst_count = try readU16(subtable, offset);
        offset += 2;
        const subst_records = try sliceRange(subtable, offset, @as(usize, subst_count) * 4);

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

    fn apply(allocator: std.mem.Allocator, face: font_parser.Face, glyphs: *std.ArrayList(ShapedGlyph), options: ShapeOptions) LayoutError!void {
        const data = face.getTable(TableTags.gsub) orelse return;
        if (data.len < OtLayout.header_min_size) return font_parser.ParserError.InvalidTable;

        const lookup_list_off = try readU16(data, OtLayout.lookup_list_offset);
        const lookup_list_data = try sliceFrom(data, lookup_list_off);

        var lookup_indices = try OtLayout.collectLookupIndices(allocator, data, options);
        defer lookup_indices.deinit(allocator);
        for (lookup_indices.items) |lookup_index| {
            try applyLookup(allocator, face, lookup_list_data, lookup_index, glyphs, 0);
        }
    }

    fn applyLookup(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, index: u16, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        if (depth >= max_recursion_depth) return font_parser.ParserError.InvalidTable;
        const lookup_off = try OtLayout.getLookupOffset(lookup_list, index);
        const lookup_data = try sliceFrom(lookup_list, lookup_off);
        const lookup_type = try readU16(lookup_data, OtLayout.lookup_type_offset);
        const subtable_count = try readU16(lookup_data, OtLayout.lookup_subtable_count_offset);

        for (0..subtable_count) |i| {
            const subtable_off = try readU16(lookup_data, OtLayout.lookup_subtable_offsets_offset + i * 2);
            const subtable_data = try sliceFrom(lookup_data, subtable_off);

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

    fn applyLigatureSubstitution(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        const coverage_off = try readU16(subtable, lig_coverage_offset);
        const coverage_data = try sliceFrom(subtable, coverage_off);
        const ligature_set_count = try readU16(subtable, lig_set_count_offset);

        var i: usize = 0;
        while (i < glyphs.items.len) {
            const index = try Coverage.getIndex(coverage_data, glyphs.items[i].glyph_id) orelse {
                i += 1;
                continue;
            };

            if (index >= ligature_set_count) return font_parser.ParserError.InvalidTable;
            const ligature_set_off = try readU16(subtable, lig_set_offsets_offset + @as(usize, index) * 2);
            const ligature_set_data = try sliceFrom(subtable, ligature_set_off);
            const ligature_count = try readU16(ligature_set_data, lig_set_ligature_count_offset);

            var matched = false;
            for (0..ligature_count) |j| {
                const ligature_off = try readU16(ligature_set_data, lig_set_lig_offsets_offset + j * 2);
                const ligature_data = try sliceFrom(ligature_set_data, ligature_off);
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

    fn applySingleSubstitution(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        const format = try readU16(subtable, single_format_offset);
        const coverage_off = try readU16(subtable, single_coverage_offset);
        const coverage_data = try sliceFrom(subtable, coverage_off);

        for (glyphs.items) |*glyph| {
            if (try Coverage.getIndex(coverage_data, glyph.glyph_id)) |index| {
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

    fn applyChainedContextualSubstitution(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        const format = try readU16(subtable, 0);
        if (format == 3) {
            try applyChainedContextualFormat3(allocator, face, lookup_list, subtable, glyphs, depth);
        }
    }

    fn applyChainedContextualFormat3(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph), depth: usize) LayoutError!void {
        var offset: usize = 2;

        const backtrack_count = try readU16(subtable, offset);
        offset += 2;
        const backtrack_coverages = try sliceRange(subtable, offset, @as(usize, backtrack_count) * 2);
        offset += @as(usize, backtrack_count) * 2;

        const input_count = try readU16(subtable, offset);
        offset += 2;
        const input_coverages = try sliceRange(subtable, offset, @as(usize, input_count) * 2);
        offset += @as(usize, input_count) * 2;

        const lookahead_count = try readU16(subtable, offset);
        offset += 2;
        const lookahead_coverages = try sliceRange(subtable, offset, @as(usize, lookahead_count) * 2);
        offset += @as(usize, lookahead_count) * 2;

        const subst_count = try readU16(subtable, offset);
        offset += 2;
        const subst_records = try sliceRange(subtable, offset, @as(usize, subst_count) * 4);

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

    fn matchChainedContextFormat3(subtable: []const u8, backtrack: []const u8, input: []const u8, lookahead: []const u8, glyphs: []const ShapedGlyph, pos: usize) font_parser.ParserError!bool {
        const backtrack_count = @as(u16, @intCast(backtrack.len / 2));
        const input_count = @as(u16, @intCast(input.len / 2));
        const lookahead_count = @as(u16, @intCast(lookahead.len / 2));

        if (pos + input_count > glyphs.len) return false;
        for (0..input_count) |j| {
            const coverage_off = try readU16(input, j * 2);
            const coverage = try sliceFrom(subtable, coverage_off);
            if (try Coverage.getIndex(coverage, glyphs[pos + j].glyph_id) == null) return false;
        }

        if (pos < backtrack_count) return false;
        for (0..backtrack_count) |j| {
            const coverage_off = try readU16(backtrack, j * 2);
            const coverage = try sliceFrom(subtable, coverage_off);
            if (try Coverage.getIndex(coverage, glyphs[pos - 1 - j].glyph_id) == null) return false;
        }

        if (pos + input_count + lookahead_count > glyphs.len) return false;
        for (0..lookahead_count) |j| {
            const coverage_off = try readU16(lookahead, j * 2);
            const coverage = try sliceFrom(subtable, coverage_off);
            if (try Coverage.getIndex(coverage, glyphs[pos + input_count + j].glyph_id) == null) return false;
        }

        return true;
    }
};

const GposLookupType = enum(u16) {
    single_adjustment = 1,
    pair_adjustment = 2,
    mark_to_base_attachment = 4,
    mark_to_ligature_attachment = 5,
    mark_to_mark_attachment = 6,
};

const ValueFormat = struct {
    const x_placement = 0x0001;
    const y_placement = 0x0002;
    const x_advance = 0x0004;
    const y_advance = 0x0008;
    const record_unit = 2;

    fn getRecordSize(format: u16) usize {
        var size: usize = 0;
        if (format & x_placement != 0) size += record_unit;
        if (format & y_placement != 0) size += record_unit;
        if (format & x_advance != 0) size += record_unit;
        if (format & y_advance != 0) size += record_unit;
        return size;
    }

    fn readRecord(data: []const u8, format: u16, glyph: *ShapedGlyph) font_parser.ParserError!void {
        var offset: usize = 0;
        if (format & x_placement != 0) {
            glyph.x_offset += try readI16(data, offset);
            offset += record_unit;
        }
        if (format & y_placement != 0) {
            glyph.y_offset += try readI16(data, offset);
            offset += record_unit;
        }
        if (format & x_advance != 0) {
            glyph.x_advance += try readI16(data, offset);
            offset += record_unit;
        }
        if (format & y_advance != 0) {
            glyph.y_advance += try readI16(data, offset);
            offset += record_unit;
        }
    }
};

const Gpos = struct {
    const single_format_offset = 0;
    const single_coverage_offset = 2;
    const single_f1_value_format_offset = 4;
    const single_f1_value_record_offset = 6;
    const single_f2_value_format_offset = 4;
    const single_f2_count_offset = 6;
    const single_f2_value_records_offset = 8;

    const pair_format_offset = 0;
    const pair_coverage_offset = 2;
    const pair_value_format1_offset = 4;
    const pair_value_format2_offset = 6;
    const pair_f1_set_count_offset = 8;
    const pair_f1_set_offsets_offset = 10;
    const pair_f2_class_def1_offset = 8;
    const pair_f2_class_def2_offset = 10;
    const pair_f2_class1_count_offset = 12;
    const pair_f2_class2_count_offset = 14;
    const pair_f2_records_offset = 16;
    const pair_set_count_offset = 0;
    const pair_set_records_offset = 2;
    const pair_record_gid2_offset = 0;
    const pair_record_values_offset = 2;

    const mark_base_format_offset = 0;
    const mark_base_mark_coverage_offset = 2;
    const mark_base_base_coverage_offset = 4;
    const mark_base_class_count_offset = 6;
    const mark_base_mark_array_offset = 8;
    const mark_base_base_array_offset = 10;

    const mark_mark_format_offset = 0;
    const mark_mark_mark1_coverage_offset = 2;
    const mark_mark_mark2_coverage_offset = 4;
    const mark_mark_class_count_offset = 6;
    const mark_mark_mark1_array_offset = 8;
    const mark_mark_mark2_array_offset = 10;

    const mark_lig_format_offset = 0;
    const mark_lig_mark_coverage_offset = 2;
    const mark_lig_lig_coverage_offset = 4;
    const mark_lig_class_count_offset = 6;
    const mark_lig_mark_array_offset = 8;
    const mark_lig_lig_array_offset = 10;

    const mark_array_count_offset = 0;
    const mark_record_size = 4;
    const mark_record_class_offset = 0;
    const mark_record_anchor_offset = 2;

    const base_array_count_offset = 0;
    const base_record_anchor_size = 2;

    const anchor_format_offset = 0;
    const anchor_x_offset = 2;
    const anchor_y_offset = 4;

    fn apply(allocator: std.mem.Allocator, face: font_parser.Face, glyphs: []ShapedGlyph, options: ShapeOptions) LayoutError!void {
        const data = face.getTable(TableTags.gpos) orelse return;
        if (data.len < OtLayout.header_min_size) return font_parser.ParserError.InvalidTable;

        const lookup_list_off = try readU16(data, OtLayout.lookup_list_offset);
        const lookup_list_data = try sliceFrom(data, lookup_list_off);

        var lookup_indices = try OtLayout.collectLookupIndices(allocator, data, options);
        defer lookup_indices.deinit(allocator);
        for (lookup_indices.items) |lookup_index| {
            try applyLookup(allocator, face, lookup_list_data, lookup_index, glyphs);
        }
    }

    fn applyLookup(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, index: u16, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        _ = allocator;
        _ = face;
        const lookup_off = try OtLayout.getLookupOffset(lookup_list, index);
        const lookup_data = try sliceFrom(lookup_list, lookup_off);
        const lookup_type = try readU16(lookup_data, OtLayout.lookup_type_offset);
        const subtable_count = try readU16(lookup_data, OtLayout.lookup_subtable_count_offset);

        for (0..subtable_count) |i| {
            const subtable_off = try readU16(lookup_data, OtLayout.lookup_subtable_offsets_offset + i * 2);
            const subtable_data = try sliceFrom(lookup_data, subtable_off);

            if (lookup_type == @intFromEnum(GposLookupType.single_adjustment)) {
                try applySingleAdjustment(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GposLookupType.pair_adjustment)) {
                try applyPairAdjustment(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GposLookupType.mark_to_base_attachment)) {
                try applyMarkToBase(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GposLookupType.mark_to_ligature_attachment)) {
                try applyMarkToLigature(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GposLookupType.mark_to_mark_attachment)) {
                try applyMarkToMark(subtable_data, glyphs);
            }
        }
    }

    fn applySingleAdjustment(subtable: []const u8, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        const format = try readU16(subtable, single_format_offset);
        const coverage_off = try readU16(subtable, single_coverage_offset);
        const coverage_data = try sliceFrom(subtable, coverage_off);

        if (format == 1) {
            const value_format = try readU16(subtable, single_f1_value_format_offset);
            const value_record = try sliceFrom(subtable, single_f1_value_record_offset);
            for (glyphs) |*glyph| {
                if (try Coverage.getIndex(coverage_data, glyph.glyph_id)) |_| {
                    try ValueFormat.readRecord(value_record, value_format, glyph);
                }
            }
        } else if (format == 2) {
            const value_format = try readU16(subtable, single_f2_value_format_offset);
            const count = try readU16(subtable, single_f2_count_offset);
            const record_size = ValueFormat.getRecordSize(value_format);
            for (glyphs) |*glyph| {
                if (try Coverage.getIndex(coverage_data, glyph.glyph_id)) |index| {
                    if (index >= count) return font_parser.ParserError.InvalidTable;
                    const record_offset = single_f2_value_records_offset + @as(usize, index) * record_size;
                    try ValueFormat.readRecord(try sliceFrom(subtable, record_offset), value_format, glyph);
                }
            }
        }
    }

    fn applyPairAdjustment(subtable: []const u8, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        const format = try readU16(subtable, pair_format_offset);
        const coverage_off = try readU16(subtable, pair_coverage_offset);
        const coverage_data = try sliceFrom(subtable, coverage_off);
        const value_format1 = try readU16(subtable, pair_value_format1_offset);
        const value_format2 = try readU16(subtable, pair_value_format2_offset);

        var i: usize = 0;
        while (i + 1 < glyphs.len) : (i += 1) {
            const index = try Coverage.getIndex(coverage_data, glyphs[i].glyph_id) orelse continue;

            if (format == 1) {
                const pair_set_count = try readU16(subtable, pair_f1_set_count_offset);
                if (index >= pair_set_count) return font_parser.ParserError.InvalidTable;
                const pair_set_off = try readU16(subtable, pair_f1_set_offsets_offset + @as(usize, index) * 2);
                const pair_set_data = try sliceFrom(subtable, pair_set_off);
                const pair_value_count = try readU16(pair_set_data, pair_set_count_offset);
                const record_size = pair_set_records_offset + ValueFormat.getRecordSize(value_format1) + ValueFormat.getRecordSize(value_format2);

                for (0..pair_value_count) |j| {
                    const record_off = pair_set_records_offset + j * record_size;
                    const second_gid = try readU16(pair_set_data, record_off + pair_record_gid2_offset);
                    if (second_gid == glyphs[i + 1].glyph_id) {
                        try ValueFormat.readRecord(try sliceFrom(pair_set_data, record_off + pair_record_values_offset), value_format1, &glyphs[i]);
                        try ValueFormat.readRecord(try sliceFrom(pair_set_data, record_off + pair_record_values_offset + ValueFormat.getRecordSize(value_format1)), value_format2, &glyphs[i + 1]);
                        break;
                    }
                }
            } else if (format == 2) {
                const class_def1_off = try readU16(subtable, pair_f2_class_def1_offset);
                const class_def2_off = try readU16(subtable, pair_f2_class_def2_offset);
                const class1_count = try readU16(subtable, pair_f2_class1_count_offset);
                const class2_count = try readU16(subtable, pair_f2_class2_count_offset);

                const class1 = try ClassDef.getClass(try sliceFrom(subtable, class_def1_off), glyphs[i].glyph_id);
                const class2 = try ClassDef.getClass(try sliceFrom(subtable, class_def2_off), glyphs[i + 1].glyph_id);

                if (class1 < class1_count and class2 < class2_count) {
                    const record_size1 = ValueFormat.getRecordSize(value_format1);
                    const record_size2 = ValueFormat.getRecordSize(value_format2);
                    const record_size = record_size1 + record_size2;
                    const record_off = pair_f2_records_offset + (@as(usize, class1) * @as(usize, class2_count) + @as(usize, class2)) * record_size;
                    try ValueFormat.readRecord(try sliceFrom(subtable, record_off), value_format1, &glyphs[i]);
                    try ValueFormat.readRecord(try sliceFrom(subtable, record_off + record_size1), value_format2, &glyphs[i + 1]);
                }
            }
        }
    }

    fn applyMarkToBase(subtable: []const u8, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        if (subtable.len < mark_base_base_array_offset + 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(subtable, mark_base_format_offset);
        if (format != 1) return;

        const mark_coverage_off = try readU16(subtable, mark_base_mark_coverage_offset);
        const base_coverage_off = try readU16(subtable, mark_base_base_coverage_offset);
        const class_count = try readU16(subtable, mark_base_class_count_offset);
        const mark_array_off = try readU16(subtable, mark_base_mark_array_offset);
        const base_array_off = try readU16(subtable, mark_base_base_array_offset);

        const mark_coverage = try sliceFrom(subtable, mark_coverage_off);
        const base_coverage = try sliceFrom(subtable, base_coverage_off);
        const mark_array = try sliceFrom(subtable, mark_array_off);
        const base_array = try sliceFrom(subtable, base_array_off);

        for (0..glyphs.len) |i| {
            const mark_index = try Coverage.getIndex(mark_coverage, glyphs[i].glyph_id) orelse continue;

            var base_idx: ?usize = null;
            if (i > 0) {
                var j = i - 1;
                while (true) {
                    if (try Coverage.getIndex(mark_coverage, glyphs[j].glyph_id) == null) {
                        base_idx = j;
                        break;
                    }
                    if (j == 0) break;
                    j -= 1;
                }
            }

            const b_idx = base_idx orelse continue;
            const base_index = try Coverage.getIndex(base_coverage, glyphs[b_idx].glyph_id) orelse continue;

            const mark_count = try readU16(mark_array, mark_array_count_offset);
            if (mark_index >= mark_count) return font_parser.ParserError.InvalidTable;
            const mark_record_off = mark_array_count_offset + 2 + @as(usize, mark_index) * mark_record_size;
            const mark_class = try readU16(mark_array, mark_record_off + mark_record_class_offset);
            const mark_anchor_off = try readU16(mark_array, mark_record_off + mark_record_anchor_offset);
            if (mark_class >= class_count) return font_parser.ParserError.InvalidTable;

            const mark_anchor_data = try sliceFrom(mark_array, mark_anchor_off);
            const mark_anchor = try readAnchor(mark_anchor_data);

            const base_count = try readU16(base_array, base_array_count_offset);
            if (base_index >= base_count) return font_parser.ParserError.InvalidTable;
            const base_record_size = @as(usize, class_count) * base_record_anchor_size;
            const base_record_off = base_array_count_offset + 2 + @as(usize, base_index) * base_record_size;
            const base_anchor_off = try readU16(base_array, base_record_off + @as(usize, mark_class) * base_record_anchor_size);
            if (base_anchor_off == 0) continue;

            const base_anchor_data = try sliceFrom(base_array, base_anchor_off);
            const base_anchor = try readAnchor(base_anchor_data);

            var rel_pen_x: i32 = 0;
            for (glyphs[b_idx..i]) |g| {
                rel_pen_x += g.x_advance;
            }

            glyphs[i].x_offset = glyphs[b_idx].x_offset + base_anchor.x - (rel_pen_x + mark_anchor.x);
            glyphs[i].y_offset = glyphs[b_idx].y_offset + base_anchor.y - mark_anchor.y;
            glyphs[i].x_advance = 0;
        }
    }

    fn applyMarkToMark(subtable: []const u8, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        if (subtable.len < mark_mark_mark2_array_offset + 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(subtable, mark_mark_format_offset);
        if (format != 1) return;

        const mark1_coverage_off = try readU16(subtable, mark_mark_mark1_coverage_offset);
        const mark2_coverage_off = try readU16(subtable, mark_mark_mark2_coverage_offset);
        const class_count = try readU16(subtable, mark_mark_class_count_offset);
        const mark1_array_off = try readU16(subtable, mark_mark_mark1_array_offset);
        const mark2_array_off = try readU16(subtable, mark_mark_mark2_array_offset);

        const mark1_coverage = try sliceFrom(subtable, mark1_coverage_off);
        const mark2_coverage = try sliceFrom(subtable, mark2_coverage_off);
        const mark1_array = try sliceFrom(subtable, mark1_array_off);
        const mark2_array = try sliceFrom(subtable, mark2_array_off);

        for (0..glyphs.len) |i| {
            const mark2_index = try Coverage.getIndex(mark2_coverage, glyphs[i].glyph_id) orelse continue;

            var base_idx: ?usize = null;
            if (i > 0) {
                var j = i - 1;
                while (true) {
                    if (try Coverage.getIndex(mark1_coverage, glyphs[j].glyph_id)) |_| {
                        base_idx = j;
                        break;
                    }
                    if (j == 0) break;
                    j -= 1;
                }
            }

            const m1_idx = base_idx orelse continue;
            const mark1_index = try Coverage.getIndex(mark1_coverage, glyphs[m1_idx].glyph_id) orelse continue;

            const mark2_count = try readU16(mark2_array, mark_array_count_offset);
            if (mark2_index >= mark2_count) return font_parser.ParserError.InvalidTable;
            const mark2_record_off = mark_array_count_offset + 2 + @as(usize, mark2_index) * mark_record_size;
            const mark2_class = try readU16(mark2_array, mark2_record_off + mark_record_class_offset);
            const mark2_anchor_off = try readU16(mark2_array, mark2_record_off + mark_record_anchor_offset);
            if (mark2_class >= class_count) return font_parser.ParserError.InvalidTable;

            const mark2_anchor_data = try sliceFrom(mark2_array, mark2_anchor_off);
            const mark2_anchor = try readAnchor(mark2_anchor_data);

            const mark1_count = try readU16(mark1_array, base_array_count_offset);
            if (mark1_index >= mark1_count) return font_parser.ParserError.InvalidTable;
            const mark1_record_size = @as(usize, class_count) * base_record_anchor_size;
            const mark1_record_off = base_array_count_offset + 2 + @as(usize, mark1_index) * mark1_record_size;
            const mark1_anchor_off = try readU16(mark1_array, mark1_record_off + @as(usize, mark2_class) * base_record_anchor_size);
            if (mark1_anchor_off == 0) continue;

            const mark1_anchor_data = try sliceFrom(mark1_array, mark1_anchor_off);
            const mark1_anchor = try readAnchor(mark1_anchor_data);

            var rel_pen_x: i32 = 0;
            for (glyphs[m1_idx..i]) |g| {
                rel_pen_x += g.x_advance;
            }

            glyphs[i].x_offset = glyphs[m1_idx].x_offset + mark1_anchor.x - (rel_pen_x + mark2_anchor.x);
            glyphs[i].y_offset = glyphs[m1_idx].y_offset + mark1_anchor.y - mark2_anchor.y;
            glyphs[i].x_advance = 0;
        }
    }

    fn applyMarkToLigature(subtable: []const u8, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        if (subtable.len < mark_lig_lig_array_offset + 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(subtable, mark_lig_format_offset);
        if (format != 1) return;

        const mark_coverage_off = try readU16(subtable, mark_lig_mark_coverage_offset);
        const lig_coverage_off = try readU16(subtable, mark_lig_lig_coverage_offset);
        const class_count = try readU16(subtable, mark_lig_class_count_offset);
        const mark_array_off = try readU16(subtable, mark_lig_mark_array_offset);
        const lig_array_off = try readU16(subtable, mark_lig_lig_array_offset);

        const mark_coverage = try sliceFrom(subtable, mark_coverage_off);
        const lig_coverage = try sliceFrom(subtable, lig_coverage_off);
        const mark_array = try sliceFrom(subtable, mark_array_off);
        const lig_array = try sliceFrom(subtable, lig_array_off);

        for (0..glyphs.len) |i| {
            const mark_index = try Coverage.getIndex(mark_coverage, glyphs[i].glyph_id) orelse continue;

            var lig_idx: ?usize = null;
            var component_idx: u16 = 0;
            if (i > 0) {
                var j = i - 1;
                while (true) {
                    if (try Coverage.getIndex(lig_coverage, glyphs[j].glyph_id)) |_| {
                        lig_idx = j;
                        break;
                    }
                    // If we see another mark that is NOT part of this lookup's coverage,
                    // we might need to skip it or count it for component matching.
                    // Simplified: every mark between ligature and current mark counts as a component increment.
                    component_idx += 1;
                    if (j == 0) break;
                    j -= 1;
                }
            }

            const l_idx = lig_idx orelse continue;
            const lig_index = try Coverage.getIndex(lig_coverage, glyphs[l_idx].glyph_id) orelse continue;

            const mark_count = try readU16(mark_array, mark_array_count_offset);
            if (mark_index >= mark_count) return font_parser.ParserError.InvalidTable;
            const mark_record_off = mark_array_count_offset + 2 + @as(usize, mark_index) * mark_record_size;
            const mark_class = try readU16(mark_array, mark_record_off + mark_record_class_offset);
            const mark_anchor_off = try readU16(mark_array, mark_record_off + mark_record_anchor_offset);
            if (mark_class >= class_count) return font_parser.ParserError.InvalidTable;

            const mark_anchor_data = try sliceFrom(mark_array, mark_anchor_off);
            const mark_anchor = try readAnchor(mark_anchor_data);

            const lig_count = try readU16(lig_array, 0);
            if (lig_index >= lig_count) return font_parser.ParserError.InvalidTable;
            const lig_attach_off = try readU16(lig_array, 2 + @as(usize, lig_index) * 2);
            const lig_attach_data = try sliceFrom(lig_array, lig_attach_off);
            const comp_count = try readU16(lig_attach_data, 0);
            if (comp_count == 0) return font_parser.ParserError.InvalidTable;

            // Limit component_idx to available components
            const actual_comp_idx = if (component_idx < comp_count) component_idx else comp_count - 1;

            const comp_record_size = @as(usize, class_count) * 2;
            const comp_record_off = 2 + @as(usize, actual_comp_idx) * comp_record_size;
            const anchor_off = try readU16(lig_attach_data, comp_record_off + @as(usize, mark_class) * 2);
            if (anchor_off == 0) continue;

            const anchor_data = try sliceFrom(lig_attach_data, anchor_off);
            const base_anchor = try readAnchor(anchor_data);

            var rel_pen_x: i32 = 0;
            for (glyphs[l_idx..i]) |g| {
                rel_pen_x += g.x_advance;
            }

            glyphs[i].x_offset = glyphs[l_idx].x_offset + base_anchor.x - (rel_pen_x + mark_anchor.x);
            glyphs[i].y_offset = glyphs[l_idx].y_offset + base_anchor.y - mark_anchor.y;
            glyphs[i].x_advance = 0;
        }
    }

    fn readAnchor(data: []const u8) font_parser.ParserError!struct { x: i16, y: i16 } {
        if (data.len < 6) return font_parser.ParserError.InvalidTable;
        const format = try readU16(data, anchor_format_offset);
        if (format < 1 or format > 3) return font_parser.ParserError.InvalidTable;
        return .{
            .x = try readI16(data, anchor_x_offset),
            .y = try readI16(data, anchor_y_offset),
        };
    }
};

const Kern = struct {
    const version_offset = 0;
    const n_tables_offset = 2;
    const header_size = 4;
    const subtable_header_size = 6;
    const subtable_length_offset = 2;
    const subtable_coverage_offset = 4;
    const version0 = 0;
};

const KernCoverage = struct {
    const horizontal_mask = 0x0001;
    const format_shift = 8;
    const format0 = 0;
};

const KernFormat0 = struct {
    const min_size = 14;
    const n_pairs_offset = 6;
    const pair_records_offset = 14;
    const pair_record_size = 6;
    const left_glyph_offset = 0;
    const right_glyph_offset = 2;
    const value_offset = 4;
};

pub const ShapeError = font_parser.ParserError || std.mem.Allocator.Error || error{
    InvalidUtf8,
};

pub const ShapeOptions = struct {
    script_tag: ?[4]u8 = null,
    language_tag: ?[4]u8 = null,
    feature_tags: ?[]const [4]u8 = null,
};

pub const ShapedGlyph = struct {
    codepoint: u21,
    glyph_id: u16,
    cluster: usize,
    x_offset: i32,
    y_offset: i32,
    x_advance: i32,
    y_advance: i32,
    advance_width: u16,
    lsb: i16,
    kern_adjustment: i16,
};

pub const ShapedText = struct {
    glyphs: []ShapedGlyph,
    total_advance: i32,

    pub fn deinit(self: *ShapedText, allocator: std.mem.Allocator) void {
        allocator.free(self.glyphs);
        self.* = undefined;
    }
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

        // 1. GSUB substitutions
        try Gsub.apply(allocator, face, &glyphs, options);

        // Update metrics for potentially new glyph IDs from GSUB
        for (glyphs.items) |*glyph| {
            const metric = try face.getHMetric(glyph.glyph_id);
            glyph.advance_width = metric.advance_width;
            glyph.x_advance = @as(i32, metric.advance_width);
            glyph.lsb = metric.lsb;
        }

        // 2. GPOS positioning
        try Gpos.apply(allocator, face, glyphs.items, options);
        const gpos_adjusted = hasGposAdjustment(glyphs.items);

        // 3. Fallback to legacy kern if GPOS did not provide adjustments.
        if (!gpos_adjusted) {
            _ = try applyKerning(face, glyphs.items);
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

        return .{
            .glyphs = try glyphs.toOwnedSlice(allocator),
            .total_advance = total_advance,
        };
    }
};

fn hasGposAdjustment(glyphs: []const ShapedGlyph) bool {
    for (glyphs) |glyph| {
        if (glyph.x_offset != 0 or glyph.y_offset != 0 or glyph.y_advance != 0) return true;
        if (glyph.x_advance != @as(i32, glyph.advance_width)) return true;
    }
    return false;
}

fn applyKerning(face: font_parser.Face, glyphs: []ShapedGlyph) font_parser.ParserError!i32 {
    if (glyphs.len == 0) return 0;

    var index: usize = 0;
    while (index + 1 < glyphs.len) : (index += 1) {
        const adjustment = try getLegacyKernAdjustment(face, glyphs[index].glyph_id, glyphs[index + 1].glyph_id);
        glyphs[index].kern_adjustment = adjustment;
        glyphs[index].x_advance = @as(i32, glyphs[index].advance_width) + @as(i32, adjustment);
    }

    var pen_x: i32 = 0;
    for (glyphs) |*glyph| {
        glyph.x_offset = pen_x;
        pen_x += glyph.x_advance;
    }
    return pen_x;
}

fn getLegacyKernAdjustment(face: font_parser.Face, left: u16, right: u16) font_parser.ParserError!i16 {
    const kern = face.getTable(TableTags.kern) orelse return 0;
    if (kern.len < Kern.header_size) return font_parser.ParserError.InvalidTable;

    const version = try readU16(kern, Kern.version_offset);
    if (version != Kern.version0) return 0;

    const n_tables = try readU16(kern, Kern.n_tables_offset);
    var offset: usize = Kern.header_size;
    var total: i32 = 0;

    var table_index: usize = 0;
    while (table_index < n_tables) : (table_index += 1) {
        if (offset + Kern.subtable_header_size > kern.len) return font_parser.ParserError.InvalidTable;

        const length = try readU16(kern, offset + Kern.subtable_length_offset);
        const coverage = try readU16(kern, offset + Kern.subtable_coverage_offset);
        if (length < Kern.subtable_header_size or offset + length > kern.len) return font_parser.ParserError.InvalidTable;

        const format = @as(u8, @intCast(coverage >> KernCoverage.format_shift));
        const horizontal = (coverage & KernCoverage.horizontal_mask) != 0;
        if (format == KernCoverage.format0 and horizontal) {
            total += try lookupKernFormat0(kern[offset .. offset + length], left, right);
        }

        offset += length;
    }

    if (total < std.math.minInt(i16) or total > std.math.maxInt(i16)) {
        return font_parser.ParserError.InvalidTable;
    }
    return @as(i16, @intCast(total));
}

fn lookupKernFormat0(subtable: []const u8, left: u16, right: u16) font_parser.ParserError!i16 {
    if (subtable.len < KernFormat0.min_size) return font_parser.ParserError.InvalidTable;

    const n_pairs = try readU16(subtable, KernFormat0.n_pairs_offset);
    if (KernFormat0.pair_records_offset + @as(usize, n_pairs) * KernFormat0.pair_record_size > subtable.len) return font_parser.ParserError.InvalidTable;

    const target = (@as(u32, left) << 16) | @as(u32, right);
    var low: usize = 0;
    var high: usize = n_pairs;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const pair_offset = KernFormat0.pair_records_offset + mid * KernFormat0.pair_record_size;
        const pair = (@as(u32, try readU16(subtable, pair_offset + KernFormat0.left_glyph_offset)) << 16) |
            @as(u32, try readU16(subtable, pair_offset + KernFormat0.right_glyph_offset));

        if (target < pair) {
            high = mid;
        } else if (target > pair) {
            low = mid + 1;
        } else {
            return try readI16(subtable, pair_offset + KernFormat0.value_offset);
        }
    }

    return 0;
}

fn sliceFrom(data: []const u8, offset: usize) font_parser.ParserError![]const u8 {
    if (offset > data.len) return font_parser.ParserError.InvalidTable;
    return data[offset..];
}

fn sliceRange(data: []const u8, offset: usize, len: usize) font_parser.ParserError![]const u8 {
    if (offset > data.len or len > data.len - offset) return font_parser.ParserError.InvalidTable;
    return data[offset .. offset + len];
}

const Coverage = struct {
    const format_offset = 0;
    const format1 = 1;
    const format2 = 2;
    const format1_count_offset = 2;
    const format1_glyphs_offset = 4;
    const format2_count_offset = 2;
    const format2_ranges_offset = 4;
    const range_record_size = 6;
    const range_start_offset = 0;
    const range_end_offset = 2;
    const range_index_offset = 4;

    fn getIndex(data: []const u8, glyph_id: u16) font_parser.ParserError!?u16 {
        if (data.len < 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(data, format_offset);
        if (format == format1) {
            const count = try readU16(data, format1_count_offset);
            if (format1_glyphs_offset + @as(usize, count) * 2 > data.len) return font_parser.ParserError.InvalidTable;
            var low: usize = 0;
            var high: usize = count;
            while (low < high) {
                const mid = low + (high - low) / 2;
                const gid = try readU16(data, format1_glyphs_offset + mid * 2);
                if (glyph_id < gid) {
                    high = mid;
                } else if (glyph_id > gid) {
                    low = mid + 1;
                } else {
                    return @as(u16, @intCast(mid));
                }
            }
        } else if (format == format2) {
            const count = try readU16(data, format2_count_offset);
            if (format2_ranges_offset + @as(usize, count) * range_record_size > data.len) return font_parser.ParserError.InvalidTable;
            var low: usize = 0;
            var high: usize = count;
            while (low < high) {
                const mid = low + (high - low) / 2;
                const range_offset = format2_ranges_offset + mid * range_record_size;
                const start = try readU16(data, range_offset + range_start_offset);
                const end = try readU16(data, range_offset + range_end_offset);
                const start_index = try readU16(data, range_offset + range_index_offset);
                if (glyph_id < start) {
                    high = mid;
                } else if (glyph_id > end) {
                    low = mid + 1;
                } else {
                    return start_index + (glyph_id - start);
                }
            }
        }
        return null;
    }
};

const ClassDef = struct {
    const format1 = 1;
    const format2 = 2;
    const format1_start_offset = 2;
    const format1_count_offset = 4;
    const format1_classes_offset = 6;
    const format2_count_offset = 2;
    const format2_ranges_offset = 4;
    const range_record_size = 6;
    const range_start_offset = 0;
    const range_end_offset = 2;
    const range_class_offset = 4;

    fn getClass(data: []const u8, glyph_id: u16) font_parser.ParserError!u16 {
        if (data.len < 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(data, 0);
        if (format == format1) {
            const start = try readU16(data, format1_start_offset);
            const count = try readU16(data, format1_count_offset);
            if (format1_classes_offset + @as(usize, count) * 2 > data.len) return font_parser.ParserError.InvalidTable;
            if (glyph_id >= start and glyph_id < start + count) {
                return try readU16(data, format1_classes_offset + @as(usize, glyph_id - start) * 2);
            }
        } else if (format == format2) {
            const count = try readU16(data, format2_count_offset);
            if (format2_ranges_offset + @as(usize, count) * range_record_size > data.len) return font_parser.ParserError.InvalidTable;
            var low: usize = 0;
            var high: usize = count;
            while (low < high) {
                const mid = low + (high - low) / 2;
                const range_offset = format2_ranges_offset + mid * range_record_size;
                const start = try readU16(data, range_offset + range_start_offset);
                const end = try readU16(data, range_offset + range_end_offset);
                const class = try readU16(data, range_offset + range_class_offset);
                if (glyph_id < start) {
                    high = mid;
                } else if (glyph_id > end) {
                    low = mid + 1;
                } else {
                    return class;
                }
            }
        }
        return 0;
    }
};

test "gsub alternate substitution" {
    var subtable = [_]u8{0} ** 20;
    writeU16(&subtable, 0, 1); // format
    writeU16(&subtable, 2, 8); // coverage_off
    writeU16(&subtable, 4, 1); // alt_set_count
    writeU16(&subtable, 6, 14); // alt_set_off[0]

    // Coverage (GID 10)
    writeU16(&subtable, 8, 1);
    writeU16(&subtable, 10, 1);
    writeU16(&subtable, 12, 10);

    // AlternateSet (GID 20, 30)
    writeU16(&subtable, 14, 2); // count
    writeU16(&subtable, 16, 20); // alt[0]
    writeU16(&subtable, 18, 30); // alt[1]

    var glyphs = std.ArrayList(ShapedGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, .{ .codepoint = 'A', .glyph_id = 10, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 });

    try Gsub.applyAlternateSubstitution(&subtable, &glyphs);
    try std.testing.expectEqual(@as(u16, 20), glyphs.items[0].glyph_id);
}

test "gsub chained contextual substitution format 3" {
    var subtable = [_]u8{0} ** 60;
    writeU16(&subtable, 0, 3); // format
    writeU16(&subtable, 2, 1); // backtrack_count
    writeU16(&subtable, 4, 20); // backtrack_coverages[0]
    writeU16(&subtable, 6, 1); // input_count
    writeU16(&subtable, 8, 26); // input_coverages[0]
    writeU16(&subtable, 10, 1); // lookahead_count
    writeU16(&subtable, 12, 32); // lookahead_coverages[0]
    writeU16(&subtable, 14, 1); // subst_count
    writeU16(&subtable, 16, 0); // subst_index 0
    writeU16(&subtable, 18, 0); // lookup_index 0

    // Backtrack Coverage (GID 1)
    writeU16(&subtable, 20, 1);
    writeU16(&subtable, 22, 1);
    writeU16(&subtable, 24, 1);

    // Input Coverage (GID 2)
    writeU16(&subtable, 26, 1);
    writeU16(&subtable, 28, 1);
    writeU16(&subtable, 30, 2);

    // Lookahead Coverage (GID 3)
    writeU16(&subtable, 32, 1);
    writeU16(&subtable, 34, 1);
    writeU16(&subtable, 36, 3);

    // Sub-lookup: Single Substitution (GID 2 -> GID 4)
    var sub_lookup = [_]u8{0} ** 12;
    writeU16(&sub_lookup, 0, 1); // format
    writeU16(&sub_lookup, 2, 6); // coverage_off
    writeI16(&sub_lookup, 4, 2); // delta (2 -> 4)
    writeU16(&sub_lookup, 6, 1); // coverage format
    writeU16(&sub_lookup, 8, 1); // count
    writeU16(&sub_lookup, 10, 2); // GID 2

    // Lookup List containing the sub-lookup
    var lookup_list = [_]u8{0} ** 30;
    writeU16(&lookup_list, 0, 1); // count
    writeU16(&lookup_list, 2, 4); // offset to lookup 0
    // Lookup 0
    writeU16(&lookup_list, 4, 1); // type (Single)
    writeU16(&lookup_list, 6, 0); // flag
    writeU16(&lookup_list, 8, 1); // subtable count
    writeU16(&lookup_list, 10, 8); // subtable offset (relative to 4, so at 12)
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

test "gpos mark to base attachment" {
    var subtable = [_]u8{0} ** 52;
    writeU16(&subtable, 0, 1); // format
    writeU16(&subtable, 2, 12); // mark_coverage_off
    writeU16(&subtable, 4, 18); // base_coverage_off
    writeU16(&subtable, 6, 1); // class_count
    writeU16(&subtable, 8, 24); // mark_array_off
    writeU16(&subtable, 10, 40); // base_array_off

    // MarkCoverage (GID 2)
    writeU16(&subtable, 12, 1);
    writeU16(&subtable, 14, 1);
    writeU16(&subtable, 16, 2);

    // BaseCoverage (GID 1)
    writeU16(&subtable, 18, 1);
    writeU16(&subtable, 20, 1);
    writeU16(&subtable, 22, 1);

    // MarkArray (starts at 24)
    writeU16(&subtable, 24, 1); // count
    writeU16(&subtable, 26, 0); // class
    writeU16(&subtable, 28, 6); // anchor_off (relative to 24, so at 30)
    // MarkAnchor (relative to 24, so at 30)
    writeU16(&subtable, 30, 1); // anchor format
    writeI16(&subtable, 32, 10); // x
    writeI16(&subtable, 34, 50); // y

    // BaseArray (starts at 40)
    writeU16(&subtable, 40, 1); // count
    writeU16(&subtable, 42, 4); // anchor_off (relative to 40, so at 44)
    // BaseAnchor (relative to 40, so at 44)
    writeU16(&subtable, 44, 1); // anchor format
    writeI16(&subtable, 46, 30); // x
    writeI16(&subtable, 48, 100); // y

    var glyphs = [_]ShapedGlyph{
        .{
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
        },
        .{
            .codepoint = 0x301,
            .glyph_id = 2,
            .cluster = 1,
            .x_offset = 0,
            .y_offset = 0,
            .x_advance = 50,
            .y_advance = 0,
            .advance_width = 50,
            .lsb = 0,
            .kern_adjustment = 0,
        },
    };

    try Gpos.applyMarkToBase(&subtable, &glyphs);

    try std.testing.expectEqual(@as(i32, -80), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(i32, 50), glyphs[1].y_offset);
    try std.testing.expectEqual(@as(i32, 0), glyphs[1].x_advance);
}

test "gpos mark to mark attachment" {
    var subtable = [_]u8{0} ** 50;
    writeU16(&subtable, 0, 1);
    writeU16(&subtable, 2, 12);
    writeU16(&subtable, 4, 18);
    writeU16(&subtable, 6, 1);
    writeU16(&subtable, 8, 24);
    writeU16(&subtable, 10, 36);

    writeU16(&subtable, 12, 1);
    writeU16(&subtable, 14, 1);
    writeU16(&subtable, 16, 2);

    writeU16(&subtable, 18, 1);
    writeU16(&subtable, 20, 1);
    writeU16(&subtable, 22, 3);

    writeU16(&subtable, 24, 1);
    writeU16(&subtable, 26, 4);
    writeU16(&subtable, 28, 1);
    writeI16(&subtable, 30, 30);
    writeI16(&subtable, 32, 100);

    writeU16(&subtable, 36, 1);
    writeU16(&subtable, 38, 0);
    writeU16(&subtable, 40, 6);
    writeU16(&subtable, 42, 1);
    writeI16(&subtable, 44, 5);
    writeI16(&subtable, 46, 20);

    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x301, .glyph_id = 2, .cluster = 0, .x_offset = -80, .y_offset = 50, .x_advance = 0, .y_advance = 0, .advance_width = 0, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x300, .glyph_id = 3, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 40, .y_advance = 0, .advance_width = 40, .lsb = 0, .kern_adjustment = 0 },
    };

    try Gpos.applyMarkToMark(&subtable, &glyphs);

    try std.testing.expectEqual(@as(i32, -55), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(i32, 130), glyphs[1].y_offset);
    try std.testing.expectEqual(@as(i32, 0), glyphs[1].x_advance);
}

test "gpos mark to ligature attachment" {
    var subtable = [_]u8{0} ** 58;
    writeU16(&subtable, 0, 1);
    writeU16(&subtable, 2, 12);
    writeU16(&subtable, 4, 18);
    writeU16(&subtable, 6, 1);
    writeU16(&subtable, 8, 24);
    writeU16(&subtable, 10, 36);

    writeU16(&subtable, 12, 1);
    writeU16(&subtable, 14, 1);
    writeU16(&subtable, 16, 3);

    writeU16(&subtable, 18, 1);
    writeU16(&subtable, 20, 1);
    writeU16(&subtable, 22, 1);

    writeU16(&subtable, 24, 1);
    writeU16(&subtable, 26, 0);
    writeU16(&subtable, 28, 6);
    writeU16(&subtable, 30, 1);
    writeI16(&subtable, 32, 10);
    writeI16(&subtable, 34, 50);

    writeU16(&subtable, 36, 1);
    writeU16(&subtable, 38, 4);
    writeU16(&subtable, 40, 1);
    writeU16(&subtable, 42, 4);
    writeU16(&subtable, 44, 1);
    writeI16(&subtable, 46, 70);
    writeI16(&subtable, 48, 120);

    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 500, .y_advance = 0, .advance_width = 500, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x301, .glyph_id = 3, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
    };

    try Gpos.applyMarkToLigature(&subtable, &glyphs);

    try std.testing.expectEqual(@as(i32, -440), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(i32, 70), glyphs[1].y_offset);
    try std.testing.expectEqual(@as(i32, 0), glyphs[1].x_advance);
}

test "coverage format 1 lookup" {
    var data = [_]u8{0} ** 10;
    writeU16(&data, 0, 1);
    writeU16(&data, 2, 3);
    writeU16(&data, 4, 10);
    writeU16(&data, 6, 20);
    writeU16(&data, 8, 30);

    try std.testing.expectEqual(@as(?u16, 0), try Coverage.getIndex(&data, 10));
    try std.testing.expectEqual(@as(?u16, 1), try Coverage.getIndex(&data, 20));
    try std.testing.expectEqual(@as(?u16, 2), try Coverage.getIndex(&data, 30));
    try std.testing.expectEqual(@as(?u16, null), try Coverage.getIndex(&data, 15));
}

test "coverage format 2 lookup" {
    var data = [_]u8{0} ** 16;
    writeU16(&data, 0, 2);
    writeU16(&data, 2, 2);
    writeU16(&data, 4, 10);
    writeU16(&data, 6, 12);
    writeU16(&data, 8, 0);
    writeU16(&data, 10, 20);
    writeU16(&data, 12, 25);
    writeU16(&data, 14, 3);

    try std.testing.expectEqual(@as(?u16, 0), try Coverage.getIndex(&data, 10));
    try std.testing.expectEqual(@as(?u16, 1), try Coverage.getIndex(&data, 11));
    try std.testing.expectEqual(@as(?u16, 3), try Coverage.getIndex(&data, 20));
    try std.testing.expectEqual(@as(?u16, 8), try Coverage.getIndex(&data, 25));
    try std.testing.expectEqual(@as(?u16, null), try Coverage.getIndex(&data, 15));
}

test "class def format 2 lookup" {
    var data = [_]u8{0} ** 16;
    writeU16(&data, 0, 2);
    writeU16(&data, 2, 2);
    writeU16(&data, 4, 10);
    writeU16(&data, 6, 12);
    writeU16(&data, 8, 1);
    writeU16(&data, 10, 20);
    writeU16(&data, 12, 25);
    writeU16(&data, 14, 2);

    try std.testing.expectEqual(@as(u16, 1), try ClassDef.getClass(&data, 10));
    try std.testing.expectEqual(@as(u16, 1), try ClassDef.getClass(&data, 11));
    try std.testing.expectEqual(@as(u16, 2), try ClassDef.getClass(&data, 20));
    try std.testing.expectEqual(@as(u16, 0), try ClassDef.getClass(&data, 15));
}

test "sliceFrom rejects out of range offsets" {
    const data = [_]u8{ 1, 2, 3 };
    try std.testing.expectError(font_parser.ParserError.InvalidTable, sliceFrom(&data, 4));
    try std.testing.expectEqualSlices(u8, data[3..], try sliceFrom(&data, 3));
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
    try std.testing.expect(!hasGposAdjustment(&unchanged));

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
    try std.testing.expect(hasGposAdjustment(&adjusted));
}

test "OpenType layout lookup collection filters by feature tag" {
    var data = [_]u8{0} ** 90;
    writeU16(&data, OtLayout.script_list_offset, 10);
    writeU16(&data, OtLayout.feature_list_offset, 34);
    writeU16(&data, OtLayout.lookup_list_offset, 80);

    writeU16(&data, 10, 1);
    data[12..16].* = OtLayout.default_script_tag;
    writeU16(&data, 16, 8);

    writeU16(&data, 18, 4);
    writeU16(&data, 20, 0);
    writeU16(&data, 22, 0);
    writeU16(&data, 24, OtLayout.required_feature_none);
    writeU16(&data, 26, 2);
    writeU16(&data, 28, 0);
    writeU16(&data, 30, 1);

    writeU16(&data, 34, 2);
    data[36..40].* = "liga".*;
    writeU16(&data, 40, 14);
    data[42..46].* = "kern".*;
    writeU16(&data, 46, 24);

    writeU16(&data, 48, 0);
    writeU16(&data, 50, 1);
    writeU16(&data, 52, 7);
    writeU16(&data, 58, 0);
    writeU16(&data, 60, 1);
    writeU16(&data, 62, 11);

    var selected = [_][4]u8{"kern".*};
    var lookup_indices = try OtLayout.collectLookupIndices(std.testing.allocator, &data, .{ .feature_tags = &selected });
    defer lookup_indices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lookup_indices.items.len);
    try std.testing.expectEqual(@as(u16, 11), lookup_indices.items[0]);
}

test "OpenType layout lookup collection can choose non-default language" {
    var data = [_]u8{0} ** 96;
    writeU16(&data, OtLayout.script_list_offset, 10);
    writeU16(&data, OtLayout.feature_list_offset, 48);
    writeU16(&data, OtLayout.lookup_list_offset, 90);

    writeU16(&data, 10, 1);
    data[12..16].* = OtLayout.latin_script_tag;
    writeU16(&data, 16, 8);

    writeU16(&data, 18, 0);
    writeU16(&data, 20, 1);
    data[22..26].* = "TRK ".*;
    writeU16(&data, 26, 18);

    writeU16(&data, 36, 0);
    writeU16(&data, 38, OtLayout.required_feature_none);
    writeU16(&data, 40, 1);
    writeU16(&data, 42, 1);

    writeU16(&data, 48, 2);
    data[50..54].* = "liga".*;
    writeU16(&data, 54, 14);
    data[56..60].* = "kern".*;
    writeU16(&data, 60, 20);

    writeU16(&data, 62, 0);
    writeU16(&data, 64, 1);
    writeU16(&data, 66, 3);
    writeU16(&data, 68, 0);
    writeU16(&data, 70, 1);
    writeU16(&data, 72, 5);

    var lookup_indices = try OtLayout.collectLookupIndices(std.testing.allocator, &data, .{
        .script_tag = "latn".*,
        .language_tag = "TRK ".*,
    });
    defer lookup_indices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lookup_indices.items.len);
    try std.testing.expectEqual(@as(u16, 5), lookup_indices.items[0]);
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
    writeU16(&subtable, 0, 2);
    writeU16(&subtable, 2, 8);
    writeU16(&subtable, 4, 1);
    writeU16(&subtable, 6, 10);
    writeU16(&subtable, 8, 1);
    writeU16(&subtable, 10, 1);
    writeU16(&subtable, 12, 1);

    try Gsub.applySingleSubstitution(&subtable, &glyphs);
    try std.testing.expectEqual(@as(u16, 10), glyphs.items[0].glyph_id);
}

test "legacy kern format 0 lookup returns pair adjustment" {
    var subtable = [_]u8{0} ** 26;
    writeU16(&subtable, 2, 26);
    writeU16(&subtable, 4, 0x0001);
    writeU16(&subtable, 6, 2);
    writeU16(&subtable, 8, 12);
    writeU16(&subtable, 10, 1);
    writeU16(&subtable, 12, 0);

    writeU16(&subtable, 14, 10);
    writeU16(&subtable, 16, 20);
    writeI16(&subtable, 18, -40);
    writeU16(&subtable, 20, 10);
    writeU16(&subtable, 22, 30);
    writeI16(&subtable, 24, -80);

    try std.testing.expectEqual(@as(i16, -40), try lookupKernFormat0(&subtable, 10, 20));
    try std.testing.expectEqual(@as(i16, -80), try lookupKernFormat0(&subtable, 10, 30));
    try std.testing.expectEqual(@as(i16, 0), try lookupKernFormat0(&subtable, 20, 10));
}

fn writeU16(data: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, data[offset..][0..2], value, .big);
}

fn writeI16(data: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, data[offset..][0..2], value, .big);
}
