const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");
const ot_layout = @import("ot_layout.zig");
const types = @import("shaper_types.zig");
const test_utils = @import("shaper_test_utils.zig");

const readU16 = binary_reader.readU16;
const readU32 = binary_reader.readU32;
const readI16 = binary_reader.readI16;
const LayoutError = types.LayoutError;
const ShapeOptions = types.ShapeOptions;
const ShapedGlyph = types.ShapedGlyph;

const GposLookupType = enum(u16) {
    single_adjustment = 1,
    pair_adjustment = 2,
    cursive_attachment = 3,
    mark_to_base_attachment = 4,
    mark_to_ligature_attachment = 5,
    mark_to_mark_attachment = 6,
    chained_contextual_positioning = 8,
    extension_positioning = 9,
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
    pub const max_recursion_depth = 16;

    const extension_positioning_format = 1;
    const extension_format_offset = 0;
    const extension_lookup_type_offset = 2;
    const extension_subtable_offset_offset = 4;
    const extension_header_size = 8;

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
    const mark_lig_lig_array_count_offset = 0;
    const mark_lig_lig_attach_offsets_offset = 2;
    const mark_lig_lig_attach_component_count_offset = 0;
    const mark_lig_lig_attach_component_records_offset = 2;

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
            try applyLookup(allocator, face, lookup_list_data, lookup_index, glyphs, 0, options);
        }
    }

    pub fn applyLookup(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, index: u16, glyphs: []ShapedGlyph, depth: usize, options: ShapeOptions) font_parser.ParserError!void {
        if (depth >= max_recursion_depth) return font_parser.ParserError.InvalidTable;
        const lookup_off = try ot_layout.OtLayout.getLookupOffset(lookup_list, index);
        const lookup_data = try ot_layout.sliceFrom(lookup_list, lookup_off);
        const lookup_type = try readU16(lookup_data, ot_layout.OtLayout.lookup_type_offset);
        const subtable_count = try readU16(lookup_data, ot_layout.OtLayout.lookup_subtable_count_offset);

        for (0..subtable_count) |i| {
            const subtable_off = try readU16(lookup_data, ot_layout.OtLayout.lookup_subtable_offsets_offset + i * 2);
            const subtable_data = try ot_layout.sliceFrom(lookup_data, subtable_off);
            try applyLookupSubtable(allocator, face, lookup_type, subtable_data, glyphs, depth, options);
        }
    }

    fn applyLookupSubtable(allocator: std.mem.Allocator, face: font_parser.Face, lookup_type: u16, subtable_data: []const u8, glyphs: []ShapedGlyph, depth: usize, options: ShapeOptions) font_parser.ParserError!void {
        if (depth >= max_recursion_depth) return font_parser.ParserError.InvalidTable;
        if (lookup_type == @intFromEnum(GposLookupType.extension_positioning)) {
            const extension = try extensionSubtable(subtable_data);
            try applyLookupSubtable(allocator, face, extension.lookup_type, extension.subtable, glyphs, depth + 1, options);
        } else if (lookup_type == @intFromEnum(GposLookupType.single_adjustment)) {
            try applySingleAdjustment(subtable_data, glyphs);
        } else if (lookup_type == @intFromEnum(GposLookupType.pair_adjustment)) {
            try applyPairAdjustment(subtable_data, glyphs);
        } else if (lookup_type == @intFromEnum(GposLookupType.cursive_attachment)) {
            try applyCursiveAttachment(subtable_data, glyphs, options);
        } else if (lookup_type == @intFromEnum(GposLookupType.mark_to_base_attachment)) {
            try applyMarkToBase(subtable_data, glyphs);
        } else if (lookup_type == @intFromEnum(GposLookupType.mark_to_ligature_attachment)) {
            try applyMarkToLigature(subtable_data, glyphs);
        } else if (lookup_type == @intFromEnum(GposLookupType.mark_to_mark_attachment)) {
            try applyMarkToMark(subtable_data, glyphs);
        } else if (lookup_type == @intFromEnum(GposLookupType.chained_contextual_positioning)) {
            try applyChainedContextualPositioning(allocator, face, subtable_data, glyphs, depth, options);
        }
    }

    const ExtensionSubtable = struct {
        lookup_type: u16,
        subtable: []const u8,
    };

    fn extensionSubtable(subtable_data: []const u8) font_parser.ParserError!ExtensionSubtable {
        if (subtable_data.len < extension_header_size) return font_parser.ParserError.InvalidTable;
        const format = try readU16(subtable_data, extension_format_offset);
        if (format != extension_positioning_format) return font_parser.ParserError.InvalidTable;
        const lookup_type = try readU16(subtable_data, extension_lookup_type_offset);
        if (lookup_type == @intFromEnum(GposLookupType.extension_positioning)) return font_parser.ParserError.InvalidTable;
        const extension_offset = try readU32(subtable_data, extension_subtable_offset_offset);
        if (extension_offset > std.math.maxInt(usize)) return font_parser.ParserError.InvalidTable;
        return .{
            .lookup_type = lookup_type,
            .subtable = try ot_layout.sliceFrom(subtable_data, @intCast(extension_offset)),
        };
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
            if (i > 0) {
                var j = i - 1;
                while (true) {
                    if (try ot_layout.Coverage.getIndex(lig_coverage, glyphs[j].glyph_id)) |_| {
                        lig_idx = j;
                        break;
                    }
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

            const lig_count = try readU16(lig_array, mark_lig_lig_array_count_offset);
            if (lig_index >= lig_count) return font_parser.ParserError.InvalidTable;
            const lig_attach_off = try readU16(lig_array, mark_lig_lig_attach_offsets_offset + @as(usize, lig_index) * 2);
            const lig_attach_data = try ot_layout.sliceFrom(lig_array, lig_attach_off);
            const comp_count = try readU16(lig_attach_data, mark_lig_lig_attach_component_count_offset);
            if (comp_count == 0) return font_parser.ParserError.InvalidTable;

            const actual_comp_idx = inferLigatureComponentIndex(glyphs, l_idx, i, comp_count);

            const comp_record_size = @as(usize, class_count) * 2;
            const comp_record_off = mark_lig_lig_attach_component_records_offset + @as(usize, actual_comp_idx) * comp_record_size;
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

    fn inferLigatureComponentIndex(glyphs: []const ShapedGlyph, lig_idx: usize, mark_idx: usize, comp_count: u16) u16 {
        const lig_cluster = glyphs[lig_idx].cluster;
        const mark_cluster = glyphs[mark_idx].cluster;
        if (mark_cluster >= lig_cluster) {
            const cluster_delta = mark_cluster - lig_cluster;
            if (cluster_delta < @as(usize, comp_count)) return @intCast(cluster_delta);
            return comp_count - 1;
        }

        return 0;
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

    pub fn applyCursiveAttachment(subtable: []const u8, glyphs: []ShapedGlyph, options: ShapeOptions) font_parser.ParserError!void {
        if (subtable.len < 6) return font_parser.ParserError.InvalidTable;
        const format = try readU16(subtable, 0);
        if (format != 1) return font_parser.ParserError.InvalidTable;

        const coverage_off = try readU16(subtable, 2);
        const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);

        const count = try readU16(subtable, 4);
        const record_size: usize = 4;
        if (subtable.len < 6 + @as(usize, count) * record_size) return font_parser.ParserError.InvalidTable;

        const direction = options.direction;

        var i: usize = 1;
        while (i < glyphs.len) : (i += 1) {
            const prev_idx = try ot_layout.Coverage.getIndex(coverage_data, glyphs[i - 1].glyph_id) orelse continue;
            const curr_idx = try ot_layout.Coverage.getIndex(coverage_data, glyphs[i].glyph_id) orelse continue;

            if (prev_idx >= count or curr_idx >= count) return font_parser.ParserError.InvalidTable;

            const prev_record_off = 6 + @as(usize, prev_idx) * record_size;
            const curr_record_off = 6 + @as(usize, curr_idx) * record_size;

            const prev_exit_off = try readU16(subtable, prev_record_off + 2);
            const curr_entry_off = try readU16(subtable, curr_record_off);

            if (prev_exit_off == 0 or curr_entry_off == 0) continue;

            const prev_exit_data = try ot_layout.sliceFrom(subtable, prev_exit_off);
            const curr_entry_data = try ot_layout.sliceFrom(subtable, curr_entry_off);

            const exit_anchor = try readAnchor(prev_exit_data);
            const entry_anchor = try readAnchor(curr_entry_data);

            const exit_x = @as(i32, exit_anchor.x);
            const exit_y = @as(i32, exit_anchor.y);
            const entry_x = @as(i32, entry_anchor.x);
            const entry_y = @as(i32, entry_anchor.y);

            if (direction == .rtl) {
                const d = exit_x + glyphs[i - 1].x_offset;
                glyphs[i - 1].x_advance -= d;
                glyphs[i - 1].x_offset -= d;

                glyphs[i].x_advance = entry_x + glyphs[i].x_offset;
            } else {
                glyphs[i - 1].x_advance = exit_x + glyphs[i - 1].x_offset;

                const d = entry_x + glyphs[i].x_offset;
                glyphs[i].x_advance -= d;
                glyphs[i].x_offset -= d;
            }

            if (direction == .rtl) {
                glyphs[i - 1].y_offset = glyphs[i].y_offset + entry_y - exit_y;
            } else {
                glyphs[i].y_offset = glyphs[i - 1].y_offset + exit_y - entry_y;
            }
        }
    }

    const chained_f1_coverage_offset = 2;
    const chained_f1_rule_set_count_offset = 4;
    const chained_f1_rule_set_offsets_offset = 6;
    const chain_rule_set_count_offset = 0;
    const chain_rule_set_offsets_offset = 2;
    const chain_rule_backtrack_count_offset = 0;

    const chained_f2_coverage_offset = 2;
    const chained_f2_backtrack_class_def_offset = 4;
    const chained_f2_input_class_def_offset = 6;
    const chained_f2_lookahead_class_def_offset = 8;
    const chained_f2_class_set_count_offset = 10;
    const chained_f2_class_set_offsets_offset = 12;
    const chain_class_set_count_offset = 0;
    const chain_class_set_offsets_offset = 2;
    const chain_class_rule_backtrack_count_offset = 0;

    pub fn applyChainedContextualPositioning(
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        subtable: []const u8,
        glyphs: []ShapedGlyph,
        depth: usize,
        options: ShapeOptions,
    ) font_parser.ParserError!void {
        if (depth >= max_recursion_depth) return font_parser.ParserError.InvalidTable;
        if (subtable.len < 2) return font_parser.ParserError.InvalidTable;
        const format = try readU16(subtable, 0);
        if (format == 1) {
            try applyChainedFormat1(allocator, face, subtable, glyphs, depth, options);
        } else if (format == 2) {
            try applyChainedFormat2(allocator, face, subtable, glyphs, depth, options);
        } else if (format == 3) {
            try applyChainedFormat3(allocator, face, subtable, glyphs, depth, options);
        } else {
            return font_parser.ParserError.InvalidTable;
        }
    }

    fn applyChainedFormat1(
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        subtable: []const u8,
        glyphs: []ShapedGlyph,
        depth: usize,
        options: ShapeOptions,
    ) font_parser.ParserError!void {
        if (subtable.len < 6) return font_parser.ParserError.InvalidTable;
        const coverage_off = try readU16(subtable, chained_f1_coverage_offset);
        const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);
        const rule_set_count = try readU16(subtable, chained_f1_rule_set_count_offset);

        var i: usize = 0;
        while (i < glyphs.len) {
            const coverage_index = try ot_layout.Coverage.getIndex(coverage_data, glyphs[i].glyph_id) orelse {
                i += 1;
                continue;
            };
            if (coverage_index >= rule_set_count) return font_parser.ParserError.InvalidTable;

            const rule_set_off = try readU16(subtable, chained_f1_rule_set_offsets_offset + @as(usize, coverage_index) * 2);
            if (rule_set_off == 0) {
                i += 1;
                continue;
            }

            const rule_set = try ot_layout.sliceFrom(subtable, rule_set_off);
            if (rule_set.len < 2) return font_parser.ParserError.InvalidTable;
            const rule_count = try readU16(rule_set, chain_rule_set_count_offset);
            var matched_len: ?u16 = null;

            for (0..rule_count) |rule_idx| {
                const rule_off = try readU16(rule_set, chain_rule_set_offsets_offset + rule_idx * 2);
                const rule = try ot_layout.sliceFrom(rule_set, rule_off);
                if (rule.len < 2) return font_parser.ParserError.InvalidTable;
                const backtrack_count = try readU16(rule, chain_rule_backtrack_count_offset);
                var offset: usize = chain_rule_backtrack_count_offset + 2;

                if (i < backtrack_count) continue;
                var matches = true;
                if (rule.len < offset + @as(usize, backtrack_count) * 2) return font_parser.ParserError.InvalidTable;
                for (0..backtrack_count) |j| {
                    const expected_gid = try readU16(rule, offset + j * 2);
                    if (glyphs[i - 1 - j].glyph_id != expected_gid) {
                        matches = false;
                        break;
                    }
                }
                if (!matches) continue;
                offset += @as(usize, backtrack_count) * 2;

                if (rule.len < offset + 2) return font_parser.ParserError.InvalidTable;
                const input_count = try readU16(rule, offset);
                offset += 2;
                if (input_count == 0 or i + input_count > glyphs.len) continue;
                if (rule.len < offset + @as(usize, input_count - 1) * 2) return font_parser.ParserError.InvalidTable;
                for (1..input_count) |input_idx| {
                    const expected_gid = try readU16(rule, offset + (input_idx - 1) * 2);
                    if (glyphs[i + input_idx].glyph_id != expected_gid) {
                        matches = false;
                        break;
                    }
                }
                if (!matches) continue;
                offset += @as(usize, input_count - 1) * 2;

                if (rule.len < offset + 2) return font_parser.ParserError.InvalidTable;
                const lookahead_count = try readU16(rule, offset);
                offset += 2;
                if (i + input_count + lookahead_count > glyphs.len) continue;
                if (rule.len < offset + @as(usize, lookahead_count) * 2) return font_parser.ParserError.InvalidTable;
                for (0..lookahead_count) |lookahead_idx| {
                    const expected_gid = try readU16(rule, offset + lookahead_idx * 2);
                    if (glyphs[i + input_count + lookahead_idx].glyph_id != expected_gid) {
                        matches = false;
                        break;
                    }
                }
                if (!matches) continue;
                offset += @as(usize, lookahead_count) * 2;

                if (rule.len < offset + 2) return font_parser.ParserError.InvalidTable;
                const pos_count = try readU16(rule, offset);
                offset += 2;
                if (rule.len < offset + @as(usize, pos_count) * 4) return font_parser.ParserError.InvalidTable;
                const pos_records = rule[offset .. offset + @as(usize, pos_count) * 4];

                try applyPositioningRecords(allocator, face, pos_records, pos_count, glyphs, i, depth, options);
                matched_len = input_count;
                break;
            }

            if (matched_len) |len| {
                i += len;
            } else {
                i += 1;
            }
        }
    }

    fn applyChainedFormat2(
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        subtable: []const u8,
        glyphs: []ShapedGlyph,
        depth: usize,
        options: ShapeOptions,
    ) font_parser.ParserError!void {
        if (subtable.len < 12) return font_parser.ParserError.InvalidTable;
        const coverage_off = try readU16(subtable, chained_f2_coverage_offset);
        const backtrack_class_def_off = try readU16(subtable, chained_f2_backtrack_class_def_offset);
        const input_class_def_off = try readU16(subtable, chained_f2_input_class_def_offset);
        const lookahead_class_def_off = try readU16(subtable, chained_f2_lookahead_class_def_offset);
        const class_set_count = try readU16(subtable, chained_f2_class_set_count_offset);
        const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);
        const backtrack_class_def = try ot_layout.sliceFrom(subtable, backtrack_class_def_off);
        const input_class_def = try ot_layout.sliceFrom(subtable, input_class_def_off);
        const lookahead_class_def = try ot_layout.sliceFrom(subtable, lookahead_class_def_off);

        var i: usize = 0;
        while (i < glyphs.len) {
            if (try ot_layout.Coverage.getIndex(coverage_data, glyphs[i].glyph_id) == null) {
                i += 1;
                continue;
            }

            const first_class = try ot_layout.ClassDef.getClass(input_class_def, glyphs[i].glyph_id);
            if (first_class >= class_set_count) return font_parser.ParserError.InvalidTable;

            const class_set_off = try readU16(subtable, chained_f2_class_set_offsets_offset + @as(usize, first_class) * 2);
            if (class_set_off == 0) {
                i += 1;
                continue;
            }

            const class_set = try ot_layout.sliceFrom(subtable, class_set_off);
            if (class_set.len < 2) return font_parser.ParserError.InvalidTable;
            const class_rule_count = try readU16(class_set, chain_class_set_count_offset);
            var matched_len: ?u16 = null;

            for (0..class_rule_count) |rule_idx| {
                const class_rule_off = try readU16(class_set, chain_class_set_offsets_offset + rule_idx * 2);
                const class_rule = try ot_layout.sliceFrom(class_set, class_rule_off);
                if (class_rule.len < 2) return font_parser.ParserError.InvalidTable;
                const backtrack_count = try readU16(class_rule, chain_class_rule_backtrack_count_offset);
                var offset: usize = chain_class_rule_backtrack_count_offset + 2;

                if (i < backtrack_count) continue;
                var matches = true;
                if (class_rule.len < offset + @as(usize, backtrack_count) * 2) return font_parser.ParserError.InvalidTable;
                for (0..backtrack_count) |j| {
                    const expected_class = try readU16(class_rule, offset + j * 2);
                    const actual_class = try ot_layout.ClassDef.getClass(backtrack_class_def, glyphs[i - 1 - j].glyph_id);
                    if (actual_class != expected_class) {
                        matches = false;
                        break;
                    }
                }
                if (!matches) continue;
                offset += @as(usize, backtrack_count) * 2;

                if (class_rule.len < offset + 2) return font_parser.ParserError.InvalidTable;
                const input_count = try readU16(class_rule, offset);
                offset += 2;
                if (input_count == 0 or i + input_count > glyphs.len) continue;
                if (class_rule.len < offset + @as(usize, input_count - 1) * 2) return font_parser.ParserError.InvalidTable;
                for (1..input_count) |input_idx| {
                    const expected_class = try readU16(class_rule, offset + (input_idx - 1) * 2);
                    const actual_class = try ot_layout.ClassDef.getClass(input_class_def, glyphs[i + input_idx].glyph_id);
                    if (actual_class != expected_class) {
                        matches = false;
                        break;
                    }
                }
                if (!matches) continue;
                offset += @as(usize, input_count - 1) * 2;

                if (class_rule.len < offset + 2) return font_parser.ParserError.InvalidTable;
                const lookahead_count = try readU16(class_rule, offset);
                offset += 2;
                if (i + input_count + lookahead_count > glyphs.len) continue;
                if (class_rule.len < offset + @as(usize, lookahead_count) * 2) return font_parser.ParserError.InvalidTable;
                for (0..lookahead_count) |lookahead_idx| {
                    const expected_class = try readU16(class_rule, offset + lookahead_idx * 2);
                    const actual_class = try ot_layout.ClassDef.getClass(lookahead_class_def, glyphs[i + input_count + lookahead_idx].glyph_id);
                    if (actual_class != expected_class) {
                        matches = false;
                        break;
                    }
                }
                if (!matches) continue;
                offset += @as(usize, lookahead_count) * 2;

                if (class_rule.len < offset + 2) return font_parser.ParserError.InvalidTable;
                const pos_count = try readU16(class_rule, offset);
                offset += 2;
                if (class_rule.len < offset + @as(usize, pos_count) * 4) return font_parser.ParserError.InvalidTable;
                const pos_records = class_rule[offset .. offset + @as(usize, pos_count) * 4];

                try applyPositioningRecords(allocator, face, pos_records, pos_count, glyphs, i, depth, options);
                matched_len = input_count;
                break;
            }

            if (matched_len) |len| {
                i += len;
            } else {
                i += 1;
            }
        }
    }

    fn applyChainedFormat3(
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        subtable: []const u8,
        glyphs: []ShapedGlyph,
        depth: usize,
        options: ShapeOptions,
    ) font_parser.ParserError!void {
        if (subtable.len < 10) return font_parser.ParserError.InvalidTable;
        var offset: usize = 2;

        const backtrack_count = try readU16(subtable, offset);
        offset += 2;
        if (subtable.len < offset + @as(usize, backtrack_count) * 2) return font_parser.ParserError.InvalidTable;
        const backtrack_coverages = subtable[offset .. offset + @as(usize, backtrack_count) * 2];
        offset += @as(usize, backtrack_count) * 2;

        if (subtable.len < offset + 2) return font_parser.ParserError.InvalidTable;
        const input_count = try readU16(subtable, offset);
        offset += 2;
        if (subtable.len < offset + @as(usize, input_count) * 2) return font_parser.ParserError.InvalidTable;
        const input_coverages = subtable[offset .. offset + @as(usize, input_count) * 2];
        offset += @as(usize, input_count) * 2;

        if (subtable.len < offset + 2) return font_parser.ParserError.InvalidTable;
        const lookahead_count = try readU16(subtable, offset);
        offset += 2;
        if (subtable.len < offset + @as(usize, lookahead_count) * 2) return font_parser.ParserError.InvalidTable;
        const lookahead_coverages = subtable[offset .. offset + @as(usize, lookahead_count) * 2];
        offset += @as(usize, lookahead_count) * 2;

        if (subtable.len < offset + 2) return font_parser.ParserError.InvalidTable;
        const pos_count = try readU16(subtable, offset);
        offset += 2;
        if (subtable.len < offset + @as(usize, pos_count) * 4) return font_parser.ParserError.InvalidTable;
        const pos_records = subtable[offset .. offset + @as(usize, pos_count) * 4];

        var i: usize = 0;
        while (i < glyphs.len) {
            if (try matchChainedFormat3(subtable, backtrack_coverages, input_coverages, lookahead_coverages, glyphs, i)) {
                try applyPositioningRecords(allocator, face, pos_records, pos_count, glyphs, i, depth, options);
                i += input_count;
            } else {
                i += 1;
            }
        }
    }

    fn matchChainedFormat3(
        subtable: []const u8,
        backtrack: []const u8,
        input: []const u8,
        lookahead: []const u8,
        glyphs: []const ShapedGlyph,
        pos: usize,
    ) font_parser.ParserError!bool {
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

    fn applyPositioningRecords(
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        pos_records: []const u8,
        pos_count: u16,
        glyphs: []ShapedGlyph,
        start: usize,
        depth: usize,
        options: ShapeOptions,
    ) font_parser.ParserError!void {
        if (depth >= max_recursion_depth) return font_parser.ParserError.InvalidTable;

        const data = face.getTable(ot_layout.TableTags.gpos) orelse return;
        if (data.len < ot_layout.OtLayout.header_min_size) return font_parser.ParserError.InvalidTable;
        const lookup_list_off = try readU16(data, ot_layout.OtLayout.lookup_list_offset);
        const lookup_list_data = try ot_layout.sliceFrom(data, lookup_list_off);

        for (0..pos_count) |i| {
            const sequence_index = try readU16(pos_records, i * 4);
            const lookup_list_index = try readU16(pos_records, i * 4 + 2);

            const target_idx = start + sequence_index;
            if (target_idx >= glyphs.len) continue;

            try applyLookup(allocator, face, lookup_list_data, lookup_list_index, glyphs[target_idx..], depth + 1, options);
        }
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

test "gpos extension positioning delegates to nested single adjustment" {
    var lookup_list = [_]u8{0} ** 34;
    test_utils.writeU16(&lookup_list, 0, 1);
    test_utils.writeU16(&lookup_list, 2, 4);

    test_utils.writeU16(&lookup_list, 4, @intFromEnum(GposLookupType.extension_positioning));
    test_utils.writeU16(&lookup_list, 6, 0);
    test_utils.writeU16(&lookup_list, 8, 1);
    test_utils.writeU16(&lookup_list, 10, 8);

    test_utils.writeU16(&lookup_list, 12, 1);
    test_utils.writeU16(&lookup_list, 14, @intFromEnum(GposLookupType.single_adjustment));
    test_utils.writeU32(&lookup_list, 16, 8);

    test_utils.writeU16(&lookup_list, 20, 1);
    test_utils.writeU16(&lookup_list, 22, 8);
    test_utils.writeU16(&lookup_list, 24, ValueFormat.x_advance);
    test_utils.writeI16(&lookup_list, 26, 25);
    test_utils.writeU16(&lookup_list, 28, 1);
    test_utils.writeU16(&lookup_list, 30, 1);
    test_utils.writeU16(&lookup_list, 32, 2);

    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 2, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };

    const face: font_parser.Face = undefined;
    try Gpos.applyLookup(std.testing.allocator, face, &lookup_list, 0, &glyphs, 0, .{});

    try std.testing.expectEqual(@as(i32, 125), glyphs[0].x_advance);
}

test "gpos extension positioning rejects nested extension positioning" {
    var lookup_list = [_]u8{0} ** 20;
    test_utils.writeU16(&lookup_list, 0, 1);
    test_utils.writeU16(&lookup_list, 2, 4);

    test_utils.writeU16(&lookup_list, 4, @intFromEnum(GposLookupType.extension_positioning));
    test_utils.writeU16(&lookup_list, 6, 0);
    test_utils.writeU16(&lookup_list, 8, 1);
    test_utils.writeU16(&lookup_list, 10, 8);

    test_utils.writeU16(&lookup_list, 12, 1);
    test_utils.writeU16(&lookup_list, 14, @intFromEnum(GposLookupType.extension_positioning));
    test_utils.writeU32(&lookup_list, 16, 8);

    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 2, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };

    const face: font_parser.Face = undefined;
    try std.testing.expectError(font_parser.ParserError.InvalidTable, Gpos.applyLookup(std.testing.allocator, face, &lookup_list, 0, &glyphs, 0, .{}));
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

test "gpos mark to ligature uses cluster to select component" {
    var subtable = [_]u8{0} ** 64;
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
    test_utils.writeU16(&subtable, 40, 2);
    test_utils.writeU16(&subtable, 42, 6);
    test_utils.writeU16(&subtable, 44, 12);
    test_utils.writeU16(&subtable, 46, 1);
    test_utils.writeI16(&subtable, 48, 70);
    test_utils.writeI16(&subtable, 50, 120);
    test_utils.writeU16(&subtable, 52, 1);
    test_utils.writeI16(&subtable, 54, 170);
    test_utils.writeI16(&subtable, 56, 140);

    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 500, .y_advance = 0, .advance_width = 500, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 0x301, .glyph_id = 3, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 50, .y_advance = 0, .advance_width = 50, .lsb = 0, .kern_adjustment = 0 },
    };

    try Gpos.applyMarkToLigature(&subtable, &glyphs);

    try std.testing.expectEqual(@as(i32, -340), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(i32, 90), glyphs[1].y_offset);
    try std.testing.expectEqual(@as(i32, 0), glyphs[1].x_advance);
}

test "gpos cursive attachment LTR" {
    var subtable = [_]u8{0} ** 34;
    test_utils.writeU16(&subtable, 0, 1); // posFormat
    test_utils.writeU16(&subtable, 2, 14); // coverageOffset
    test_utils.writeU16(&subtable, 4, 2); // entryExitCount
    // glyph 2 exit anchor at 22
    test_utils.writeU16(&subtable, 6, 0); // entryAnchorOffset
    test_utils.writeU16(&subtable, 8, 22); // exitAnchorOffset
    // glyph 3 entry anchor at 28
    test_utils.writeU16(&subtable, 10, 28); // entryAnchorOffset
    test_utils.writeU16(&subtable, 12, 0); // exitAnchorOffset

    // Coverage (offset 14)
    test_utils.writeU16(&subtable, 14, 1); // format
    test_utils.writeU16(&subtable, 16, 2); // glyphCount
    test_utils.writeU16(&subtable, 18, 2); // glyphs[0] = 2
    test_utils.writeU16(&subtable, 20, 3); // glyphs[1] = 3

    // exit anchor for glyph 2 (offset 22)
    test_utils.writeU16(&subtable, 22, 1); // format
    test_utils.writeI16(&subtable, 24, 80); // x
    test_utils.writeI16(&subtable, 26, 40); // y

    // entry anchor for glyph 3 (offset 28)
    test_utils.writeU16(&subtable, 28, 1); // format
    test_utils.writeI16(&subtable, 30, 10); // x
    test_utils.writeI16(&subtable, 32, 30); // y

    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 2, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'B', .glyph_id = 3, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };

    try Gpos.applyCursiveAttachment(&subtable, &glyphs, .{ .direction = .ltr });

    try std.testing.expectEqual(@as(i32, 80), glyphs[0].x_advance);
    try std.testing.expectEqual(@as(i32, 90), glyphs[1].x_advance);
    try std.testing.expectEqual(@as(i32, -10), glyphs[1].x_offset);
    try std.testing.expectEqual(@as(i32, 10), glyphs[1].y_offset);
}

test "gpos cursive attachment RTL" {
    var subtable = [_]u8{0} ** 34;
    test_utils.writeU16(&subtable, 0, 1);
    test_utils.writeU16(&subtable, 2, 14);
    test_utils.writeU16(&subtable, 4, 2);
    test_utils.writeU16(&subtable, 6, 0);
    test_utils.writeU16(&subtable, 8, 22);
    test_utils.writeU16(&subtable, 10, 28);
    test_utils.writeU16(&subtable, 12, 0);

    test_utils.writeU16(&subtable, 14, 1);
    test_utils.writeU16(&subtable, 16, 2);
    test_utils.writeU16(&subtable, 18, 2);
    test_utils.writeU16(&subtable, 20, 3);

    test_utils.writeU16(&subtable, 22, 1);
    test_utils.writeI16(&subtable, 24, 80);
    test_utils.writeI16(&subtable, 26, 40);

    test_utils.writeU16(&subtable, 28, 1);
    test_utils.writeI16(&subtable, 30, 10);
    test_utils.writeI16(&subtable, 32, 30);

    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 2, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'B', .glyph_id = 3, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };

    try Gpos.applyCursiveAttachment(&subtable, &glyphs, .{ .direction = .rtl });

    try std.testing.expectEqual(@as(i32, 20), glyphs[0].x_advance);
    try std.testing.expectEqual(@as(i32, -80), glyphs[0].x_offset);
    try std.testing.expectEqual(@as(i32, 10), glyphs[1].x_advance);
    try std.testing.expectEqual(@as(i32, -10), glyphs[0].y_offset);
}

test "gpos chained contextual positioning Format 3" {
    var gpos_data = [_]u8{0} ** 100;
    test_utils.writeU16(&gpos_data, 0, 1);
    test_utils.writeU16(&gpos_data, 2, 0);
    test_utils.writeU16(&gpos_data, 4, 10);
    test_utils.writeU16(&gpos_data, 6, 10);
    test_utils.writeU16(&gpos_data, 8, 10);

    test_utils.writeU16(&gpos_data, 10, 2);
    test_utils.writeU16(&gpos_data, 12, 6);
    test_utils.writeU16(&gpos_data, 14, 40);

    test_utils.writeU16(&gpos_data, 16, @intFromEnum(GposLookupType.chained_contextual_positioning));
    test_utils.writeU16(&gpos_data, 18, 0);
    test_utils.writeU16(&gpos_data, 20, 1);
    test_utils.writeU16(&gpos_data, 22, 8);

    test_utils.writeU16(&gpos_data, 24, 3);
    test_utils.writeU16(&gpos_data, 26, 1);
    test_utils.writeU16(&gpos_data, 28, 52);
    test_utils.writeU16(&gpos_data, 30, 1);
    test_utils.writeU16(&gpos_data, 32, 58);
    test_utils.writeU16(&gpos_data, 34, 1);
    test_utils.writeU16(&gpos_data, 36, 64);
    test_utils.writeU16(&gpos_data, 38, 1);
    test_utils.writeU16(&gpos_data, 40, 0);
    test_utils.writeU16(&gpos_data, 42, 1);

    test_utils.writeU16(&gpos_data, 50, @intFromEnum(GposLookupType.single_adjustment));
    test_utils.writeU16(&gpos_data, 52, 0);
    test_utils.writeU16(&gpos_data, 54, 1);
    test_utils.writeU16(&gpos_data, 56, 8);

    test_utils.writeU16(&gpos_data, 58, 1);
    test_utils.writeU16(&gpos_data, 60, 12);
    test_utils.writeU16(&gpos_data, 62, 0x0004);
    test_utils.writeI16(&gpos_data, 64, 150);

    test_utils.writeU16(&gpos_data, 70, 1);
    test_utils.writeU16(&gpos_data, 72, 1);
    test_utils.writeU16(&gpos_data, 74, 20);

    test_utils.writeU16(&gpos_data, 76, 1);
    test_utils.writeU16(&gpos_data, 78, 1);
    test_utils.writeU16(&gpos_data, 80, 10);

    test_utils.writeU16(&gpos_data, 82, 1);
    test_utils.writeU16(&gpos_data, 84, 1);
    test_utils.writeU16(&gpos_data, 86, 20);

    test_utils.writeU16(&gpos_data, 88, 1);
    test_utils.writeU16(&gpos_data, 90, 1);
    test_utils.writeU16(&gpos_data, 92, 30);

    var tables = [_]font_parser.TableMetadata{
        .{
            .tag = ot_layout.TableTags.gpos,
            .offset = 0,
            .length = @intCast(gpos_data.len),
        },
    };
    const face = font_parser.Face{
        .data = &gpos_data,
        .units_per_em = 1000,
        .num_glyphs = 100,
        .tables = &tables,
        .number_of_h_metrics = 0,
        .number_of_v_metrics = null,
        .vorg_default_vert_origin_y = null,
        .vorg = null,
        .cmap = null,
    };

    var glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'X', .glyph_id = 10, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'Y', .glyph_id = 20, .cluster = 1, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
        .{ .codepoint = 'Z', .glyph_id = 30, .cluster = 2, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };

    const lookup_list_data = gpos_data[10..];
    try Gpos.applyLookup(std.testing.allocator, face, lookup_list_data, 0, &glyphs, 0, .{});

    try std.testing.expectEqual(@as(i32, 250), glyphs[1].x_advance);
}

