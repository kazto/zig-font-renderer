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

pub const Gpos = struct {
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

    pub fn apply(allocator: std.mem.Allocator, face: font_parser.Face, glyphs: []ShapedGlyph, options: ShapeOptions) LayoutError!void {
        const data = face.getTable(ot_layout.TableTags.gpos) orelse return;
        if (data.len < ot_layout.OtLayout.header_min_size) return font_parser.ParserError.InvalidTable;

        const lookup_list_off = try readU16(data, ot_layout.OtLayout.lookup_list_offset);
        const lookup_list_data = try ot_layout.sliceFrom(data, lookup_list_off);

        var lookup_indices = try ot_layout.OtLayout.collectLookupIndices(allocator, data, options);
        defer lookup_indices.deinit(allocator);
        for (lookup_indices.items) |lookup_index| {
            try applyLookup(allocator, face, lookup_list_data, lookup_index, glyphs);
        }
    }

    pub fn applyLookup(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, index: u16, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        _ = allocator;
        _ = face;
        const lookup_off = try ot_layout.OtLayout.getLookupOffset(lookup_list, index);
        const lookup_data = try ot_layout.sliceFrom(lookup_list, lookup_off);
        const lookup_type = try readU16(lookup_data, ot_layout.OtLayout.lookup_type_offset);
        const subtable_count = try readU16(lookup_data, ot_layout.OtLayout.lookup_subtable_count_offset);

        for (0..subtable_count) |i| {
            const subtable_off = try readU16(lookup_data, ot_layout.OtLayout.lookup_subtable_offsets_offset + i * 2);
            const subtable_data = try ot_layout.sliceFrom(lookup_data, subtable_off);

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

    pub fn applySingleAdjustment(subtable: []const u8, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        const format = try readU16(subtable, single_format_offset);
        const coverage_off = try readU16(subtable, single_coverage_offset);
        const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);

        if (format == 1) {
            const value_format = try readU16(subtable, single_f1_value_format_offset);
            const value_record = try ot_layout.sliceFrom(subtable, single_f1_value_record_offset);
            for (glyphs) |*glyph| {
                if (try ot_layout.Coverage.getIndex(coverage_data, glyph.glyph_id)) |_| {
                    try ValueFormat.readRecord(value_record, value_format, glyph);
                }
            }
        } else if (format == 2) {
            const value_format = try readU16(subtable, single_f2_value_format_offset);
            const count = try readU16(subtable, single_f2_count_offset);
            const record_size = ValueFormat.getRecordSize(value_format);
            for (glyphs) |*glyph| {
                if (try ot_layout.Coverage.getIndex(coverage_data, glyph.glyph_id)) |index| {
                    if (index >= count) return font_parser.ParserError.InvalidTable;
                    const record_offset = single_f2_value_records_offset + @as(usize, index) * record_size;
                    try ValueFormat.readRecord(try ot_layout.sliceFrom(subtable, record_offset), value_format, glyph);
                }
            }
        }
    }

    pub fn applyPairAdjustment(subtable: []const u8, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        const format = try readU16(subtable, pair_format_offset);
        const coverage_off = try readU16(subtable, pair_coverage_offset);
        const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);
        const value_format1 = try readU16(subtable, pair_value_format1_offset);
        const value_format2 = try readU16(subtable, pair_value_format2_offset);

        var i: usize = 0;
        while (i + 1 < glyphs.len) : (i += 1) {
            const index = try ot_layout.Coverage.getIndex(coverage_data, glyphs[i].glyph_id) orelse continue;

            if (format == 1) {
                const pair_set_count = try readU16(subtable, pair_f1_set_count_offset);
                if (index >= pair_set_count) return font_parser.ParserError.InvalidTable;
                const pair_set_off = try readU16(subtable, pair_f1_set_offsets_offset + @as(usize, index) * 2);
                const pair_set_data = try ot_layout.sliceFrom(subtable, pair_set_off);
                const pair_value_count = try readU16(pair_set_data, pair_set_count_offset);
                const record_size = pair_set_records_offset + ValueFormat.getRecordSize(value_format1) + ValueFormat.getRecordSize(value_format2);

                for (0..pair_value_count) |j| {
                    const record_off = pair_set_records_offset + j * record_size;
                    const second_gid = try readU16(pair_set_data, record_off + pair_record_gid2_offset);
                    if (second_gid == glyphs[i + 1].glyph_id) {
                        try ValueFormat.readRecord(try ot_layout.sliceFrom(pair_set_data, record_off + pair_record_values_offset), value_format1, &glyphs[i]);
                        try ValueFormat.readRecord(try ot_layout.sliceFrom(pair_set_data, record_off + pair_record_values_offset + ValueFormat.getRecordSize(value_format1)), value_format2, &glyphs[i + 1]);
                        break;
                    }
                }
            } else if (format == 2) {
                const class_def1_off = try readU16(subtable, pair_f2_class_def1_offset);
                const class_def2_off = try readU16(subtable, pair_f2_class_def2_offset);
                const class1_count = try readU16(subtable, pair_f2_class1_count_offset);
                const class2_count = try readU16(subtable, pair_f2_class2_count_offset);

                const class1 = try ot_layout.ClassDef.getClass(try ot_layout.sliceFrom(subtable, class_def1_off), glyphs[i].glyph_id);
                const class2 = try ot_layout.ClassDef.getClass(try ot_layout.sliceFrom(subtable, class_def2_off), glyphs[i + 1].glyph_id);

                if (class1 < class1_count and class2 < class2_count) {
                    const record_size1 = ValueFormat.getRecordSize(value_format1);
                    const record_size2 = ValueFormat.getRecordSize(value_format2);
                    const record_size = record_size1 + record_size2;
                    const record_off = pair_f2_records_offset + (@as(usize, class1) * @as(usize, class2_count) + @as(usize, class2)) * record_size;
                    try ValueFormat.readRecord(try ot_layout.sliceFrom(subtable, record_off), value_format1, &glyphs[i]);
                    try ValueFormat.readRecord(try ot_layout.sliceFrom(subtable, record_off + record_size1), value_format2, &glyphs[i + 1]);
                }
            }
        }
    }

    pub fn applyMarkToBase(subtable: []const u8, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        if (subtable.len < mark_base_base_array_offset + 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(subtable, mark_base_format_offset);
        if (format != 1) return;

        const mark_coverage_off = try readU16(subtable, mark_base_mark_coverage_offset);
        const base_coverage_off = try readU16(subtable, mark_base_base_coverage_offset);
        const class_count = try readU16(subtable, mark_base_class_count_offset);
        const mark_array_off = try readU16(subtable, mark_base_mark_array_offset);
        const base_array_off = try readU16(subtable, mark_base_base_array_offset);

        const mark_coverage = try ot_layout.sliceFrom(subtable, mark_coverage_off);
        const base_coverage = try ot_layout.sliceFrom(subtable, base_coverage_off);
        const mark_array = try ot_layout.sliceFrom(subtable, mark_array_off);
        const base_array = try ot_layout.sliceFrom(subtable, base_array_off);

        for (0..glyphs.len) |i| {
            const mark_index = try ot_layout.Coverage.getIndex(mark_coverage, glyphs[i].glyph_id) orelse continue;

            var base_idx: ?usize = null;
            if (i > 0) {
                var j = i - 1;
                while (true) {
                    if (try ot_layout.Coverage.getIndex(mark_coverage, glyphs[j].glyph_id) == null) {
                        base_idx = j;
                        break;
                    }
                    if (j == 0) break;
                    j -= 1;
                }
            }

            const b_idx = base_idx orelse continue;
            const base_index = try ot_layout.Coverage.getIndex(base_coverage, glyphs[b_idx].glyph_id) orelse continue;

            const mark_count = try readU16(mark_array, mark_array_count_offset);
            if (mark_index >= mark_count) return font_parser.ParserError.InvalidTable;
            const mark_record_off = mark_array_count_offset + 2 + @as(usize, mark_index) * mark_record_size;
            const mark_class = try readU16(mark_array, mark_record_off + mark_record_class_offset);
            const mark_anchor_off = try readU16(mark_array, mark_record_off + mark_record_anchor_offset);
            if (mark_class >= class_count) return font_parser.ParserError.InvalidTable;

            const mark_anchor_data = try ot_layout.sliceFrom(mark_array, mark_anchor_off);
            const mark_anchor = try readAnchor(mark_anchor_data);

            const base_count = try readU16(base_array, base_array_count_offset);
            if (base_index >= base_count) return font_parser.ParserError.InvalidTable;
            const base_record_size = @as(usize, class_count) * base_record_anchor_size;
            const base_record_off = base_array_count_offset + 2 + @as(usize, base_index) * base_record_size;
            const base_anchor_off = try readU16(base_array, base_record_off + @as(usize, mark_class) * base_record_anchor_size);
            if (base_anchor_off == 0) continue;

            const base_anchor_data = try ot_layout.sliceFrom(base_array, base_anchor_off);
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

    pub fn applyMarkToMark(subtable: []const u8, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        if (subtable.len < mark_mark_mark2_array_offset + 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(subtable, mark_mark_format_offset);
        if (format != 1) return;

        const mark1_coverage_off = try readU16(subtable, mark_mark_mark1_coverage_offset);
        const mark2_coverage_off = try readU16(subtable, mark_mark_mark2_coverage_offset);
        const class_count = try readU16(subtable, mark_mark_class_count_offset);
        const mark1_array_off = try readU16(subtable, mark_mark_mark1_array_offset);
        const mark2_array_off = try readU16(subtable, mark_mark_mark2_array_offset);

        const mark1_coverage = try ot_layout.sliceFrom(subtable, mark1_coverage_off);
        const mark2_coverage = try ot_layout.sliceFrom(subtable, mark2_coverage_off);
        const mark1_array = try ot_layout.sliceFrom(subtable, mark1_array_off);
        const mark2_array = try ot_layout.sliceFrom(subtable, mark2_array_off);

        for (0..glyphs.len) |i| {
            const mark2_index = try ot_layout.Coverage.getIndex(mark2_coverage, glyphs[i].glyph_id) orelse continue;

            var base_idx: ?usize = null;
            if (i > 0) {
                var j = i - 1;
                while (true) {
                    if (try ot_layout.Coverage.getIndex(mark1_coverage, glyphs[j].glyph_id)) |_| {
                        base_idx = j;
                        break;
                    }
                    if (j == 0) break;
                    j -= 1;
                }
            }

            const m1_idx = base_idx orelse continue;
            const mark1_index = try ot_layout.Coverage.getIndex(mark1_coverage, glyphs[m1_idx].glyph_id) orelse continue;

            const mark2_count = try readU16(mark2_array, mark_array_count_offset);
            if (mark2_index >= mark2_count) return font_parser.ParserError.InvalidTable;
            const mark2_record_off = mark_array_count_offset + 2 + @as(usize, mark2_index) * mark_record_size;
            const mark2_class = try readU16(mark2_array, mark2_record_off + mark_record_class_offset);
            const mark2_anchor_off = try readU16(mark2_array, mark2_record_off + mark_record_anchor_offset);
            if (mark2_class >= class_count) return font_parser.ParserError.InvalidTable;

            const mark2_anchor_data = try ot_layout.sliceFrom(mark2_array, mark2_anchor_off);
            const mark2_anchor = try readAnchor(mark2_anchor_data);

            const mark1_count = try readU16(mark1_array, base_array_count_offset);
            if (mark1_index >= mark1_count) return font_parser.ParserError.InvalidTable;
            const mark1_record_size = @as(usize, class_count) * base_record_anchor_size;
            const mark1_record_off = base_array_count_offset + 2 + @as(usize, mark1_index) * mark1_record_size;
            const mark1_anchor_off = try readU16(mark1_array, mark1_record_off + @as(usize, mark2_class) * base_record_anchor_size);
            if (mark1_anchor_off == 0) continue;

            const mark1_anchor_data = try ot_layout.sliceFrom(mark1_array, mark1_anchor_off);
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

    pub fn applyMarkToLigature(subtable: []const u8, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        if (subtable.len < mark_lig_lig_array_offset + 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(subtable, mark_lig_format_offset);
        if (format != 1) return;

        const mark_coverage_off = try readU16(subtable, mark_lig_mark_coverage_offset);
        const lig_coverage_off = try readU16(subtable, mark_lig_lig_coverage_offset);
        const class_count = try readU16(subtable, mark_lig_class_count_offset);
        const mark_array_off = try readU16(subtable, mark_lig_mark_array_offset);
        const lig_array_off = try readU16(subtable, mark_lig_lig_array_offset);

        const mark_coverage = try ot_layout.sliceFrom(subtable, mark_coverage_off);
        const lig_coverage = try ot_layout.sliceFrom(subtable, lig_coverage_off);
        const mark_array = try ot_layout.sliceFrom(subtable, mark_array_off);
        const lig_array = try ot_layout.sliceFrom(subtable, lig_array_off);

        for (0..glyphs.len) |i| {
            const mark_index = try ot_layout.Coverage.getIndex(mark_coverage, glyphs[i].glyph_id) orelse continue;

            var lig_idx: ?usize = null;
            var component_idx: u16 = 0;
            if (i > 0) {
                var j = i - 1;
                while (true) {
                    if (try ot_layout.Coverage.getIndex(lig_coverage, glyphs[j].glyph_id)) |_| {
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
            const lig_index = try ot_layout.Coverage.getIndex(lig_coverage, glyphs[l_idx].glyph_id) orelse continue;

            const mark_count = try readU16(mark_array, mark_array_count_offset);
            if (mark_index >= mark_count) return font_parser.ParserError.InvalidTable;
            const mark_record_off = mark_array_count_offset + 2 + @as(usize, mark_index) * mark_record_size;
            const mark_class = try readU16(mark_array, mark_record_off + mark_record_class_offset);
            const mark_anchor_off = try readU16(mark_array, mark_record_off + mark_record_anchor_offset);
            if (mark_class >= class_count) return font_parser.ParserError.InvalidTable;

            const mark_anchor_data = try ot_layout.sliceFrom(mark_array, mark_anchor_off);
            const mark_anchor = try readAnchor(mark_anchor_data);

            const lig_count = try readU16(lig_array, 0);
            if (lig_index >= lig_count) return font_parser.ParserError.InvalidTable;
            const lig_attach_off = try readU16(lig_array, 2 + @as(usize, lig_index) * 2);
            const lig_attach_data = try ot_layout.sliceFrom(lig_array, lig_attach_off);
            const comp_count = try readU16(lig_attach_data, 0);
            if (comp_count == 0) return font_parser.ParserError.InvalidTable;

            // Limit component_idx to available components
            const actual_comp_idx = if (component_idx < comp_count) component_idx else comp_count - 1;

            const comp_record_size = @as(usize, class_count) * 2;
            const comp_record_off = 2 + @as(usize, actual_comp_idx) * comp_record_size;
            const anchor_off = try readU16(lig_attach_data, comp_record_off + @as(usize, mark_class) * 2);
            if (anchor_off == 0) continue;

            const anchor_data = try ot_layout.sliceFrom(lig_attach_data, anchor_off);
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

    pub fn readAnchor(data: []const u8) font_parser.ParserError!struct { x: i16, y: i16 } {
        if (data.len < 6) return font_parser.ParserError.InvalidTable;
        const format = try readU16(data, anchor_format_offset);
        if (format < 1 or format > 3) return font_parser.ParserError.InvalidTable;
        return .{
            .x = try readI16(data, anchor_x_offset),
            .y = try readI16(data, anchor_y_offset),
        };
    }
};

test "gpos mark to base attachment" {
    var subtable = [_]u8{0} ** 52;
    test_utils.writeU16(&subtable, 0, 1); // format
    test_utils.writeU16(&subtable, 2, 12); // mark_coverage_off
    test_utils.writeU16(&subtable, 4, 18); // base_coverage_off
    test_utils.writeU16(&subtable, 6, 1); // class_count
    test_utils.writeU16(&subtable, 8, 24); // mark_array_off
    test_utils.writeU16(&subtable, 10, 40); // base_array_off

    // MarkCoverage (GID 2)
    test_utils.writeU16(&subtable, 12, 1);
    test_utils.writeU16(&subtable, 14, 1);
    test_utils.writeU16(&subtable, 16, 2);

    // BaseCoverage (GID 1)
    test_utils.writeU16(&subtable, 18, 1);
    test_utils.writeU16(&subtable, 20, 1);
    test_utils.writeU16(&subtable, 22, 1);

    // MarkArray (starts at 24)
    test_utils.writeU16(&subtable, 24, 1); // count
    test_utils.writeU16(&subtable, 26, 0); // class
    test_utils.writeU16(&subtable, 28, 6); // anchor_off (relative to 24, so at 30)
    // MarkAnchor (relative to 24, so at 30)
    test_utils.writeU16(&subtable, 30, 1); // anchor format
    test_utils.writeI16(&subtable, 32, 10); // x
    test_utils.writeI16(&subtable, 34, 50); // y

    // BaseArray (starts at 40)
    test_utils.writeU16(&subtable, 40, 1); // count
    test_utils.writeU16(&subtable, 42, 4); // anchor_off (relative to 40, so at 44)
    // BaseAnchor (relative to 40, so at 44)
    test_utils.writeU16(&subtable, 44, 1); // anchor format
    test_utils.writeI16(&subtable, 46, 30); // x
    test_utils.writeI16(&subtable, 48, 100); // y

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
    test_utils.writeU16(&subtable, 0, 1);
    test_utils.writeU16(&subtable, 2, 12);
    test_utils.writeU16(&subtable, 4, 18);
    test_utils.writeU16(&subtable, 6, 1);
    test_utils.writeU16(&subtable, 8, 24);
    test_utils.writeU16(&subtable, 10, 36);

    test_utils.writeU16(&subtable, 12, 1);
    test_utils.writeU16(&subtable, 14, 1);
    test_utils.writeU16(&subtable, 16, 2);

    test_utils.writeU16(&subtable, 18, 1);
    test_utils.writeU16(&subtable, 20, 1);
    test_utils.writeU16(&subtable, 22, 3);

    test_utils.writeU16(&subtable, 24, 1);
    test_utils.writeU16(&subtable, 26, 4);
    test_utils.writeU16(&subtable, 28, 1);
    test_utils.writeI16(&subtable, 30, 30);
    test_utils.writeI16(&subtable, 32, 100);

    test_utils.writeU16(&subtable, 36, 1);
    test_utils.writeU16(&subtable, 38, 0);
    test_utils.writeU16(&subtable, 40, 6);
    test_utils.writeU16(&subtable, 42, 1);
    test_utils.writeI16(&subtable, 44, 5);
    test_utils.writeI16(&subtable, 46, 20);

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
    test_utils.writeU16(&subtable, 0, 1);
    test_utils.writeU16(&subtable, 2, 12);
    test_utils.writeU16(&subtable, 4, 18);
    test_utils.writeU16(&subtable, 6, 1);
    test_utils.writeU16(&subtable, 8, 24);
    test_utils.writeU16(&subtable, 10, 36);

    test_utils.writeU16(&subtable, 12, 1);
    test_utils.writeU16(&subtable, 14, 1);
    test_utils.writeU16(&subtable, 16, 3);

    test_utils.writeU16(&subtable, 18, 1);
    test_utils.writeU16(&subtable, 20, 1);
    test_utils.writeU16(&subtable, 22, 1);

    test_utils.writeU16(&subtable, 24, 1);
    test_utils.writeU16(&subtable, 26, 0);
    test_utils.writeU16(&subtable, 28, 6);
    test_utils.writeU16(&subtable, 30, 1);
    test_utils.writeI16(&subtable, 32, 10);
    test_utils.writeI16(&subtable, 34, 50);

    test_utils.writeU16(&subtable, 36, 1);
    test_utils.writeU16(&subtable, 38, 4);
    test_utils.writeU16(&subtable, 40, 1);
    test_utils.writeU16(&subtable, 42, 4);
    test_utils.writeU16(&subtable, 44, 1);
    test_utils.writeI16(&subtable, 46, 70);
    test_utils.writeI16(&subtable, 48, 120);

    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 500, .y_advance = 0, .advance_width = 500, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x301, .glyph_id = 3, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
    };

    try Gpos.applyMarkToLigature(&subtable, &glyphs);

    try std.testing.expectEqual(@as(i32, -440), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(i32, 70), glyphs[1].y_offset);
    try std.testing.expectEqual(@as(i32, 0), glyphs[1].x_advance);
}
