const std = @import("std");
const font_parser = @import("font_parser.zig");

const TableTags = struct {
    const kern = "kern".*;
    const gsub = "GSUB".*;
    const gpos = "GPOS".*;
};

const OtLayout = struct {
    const header_min_size = 10;
    const script_list_offset = 4;
    const feature_list_offset = 6;
    const lookup_list_offset = 8;

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
    ligature_substitution = 4,
};

const Gsub = struct {
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

    fn apply(allocator: std.mem.Allocator, face: font_parser.Face, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        const data = face.getTable(TableTags.gsub) orelse return;
        if (data.len < OtLayout.header_min_size) return font_parser.ParserError.InvalidTable;

        const script_list_off = try readU16(data, OtLayout.script_list_offset);
        const feature_list_off = try readU16(data, OtLayout.feature_list_offset);
        const lookup_list_off = try readU16(data, OtLayout.lookup_list_offset);
        const script_list_data = try sliceFrom(data, script_list_off);
        const feature_list_data = try sliceFrom(data, feature_list_off);
        const lookup_list_data = try sliceFrom(data, lookup_list_off);

        var script_off_val = try OtLayout.findScriptOffset(script_list_data, "DFLT".*);
        if (script_off_val == null) {
            script_off_val = try OtLayout.findScriptOffset(script_list_data, "latn".*);
        }
        const actual_script_off = script_off_val orelse return;
        const script_data = try sliceFrom(script_list_data, actual_script_off);
        const default_lang_sys_off = try readU16(script_data, 0);
        if (default_lang_sys_off == 0) return;

        const lang_sys_data = try sliceFrom(script_data, default_lang_sys_off);
        const feature_count = try readU16(lang_sys_data, OtLayout.lang_sys_feature_count_offset);

        for (0..feature_count) |i| {
            const feature_index = try readU16(lang_sys_data, OtLayout.lang_sys_feature_indices_offset + i * 2);
            const feature_offset = OtLayout.feature_list_count_offset + 2 + @as(usize, feature_index) * OtLayout.feature_record_size;
            const feature_data_off = try readU16(feature_list_data, feature_offset + OtLayout.feature_offset_offset);
            const feature_data = try sliceFrom(feature_list_data, feature_data_off);
            const lookup_count = try readU16(feature_data, OtLayout.feature_data_lookup_count_offset);

            for (0..lookup_count) |j| {
                const lookup_index = try readU16(feature_data, OtLayout.feature_data_lookup_indices_offset + j * 2);
                try applyLookup(allocator, face, lookup_list_data, lookup_index, glyphs);
            }
        }
    }

    fn applyLookup(allocator: std.mem.Allocator, face: font_parser.Face, lookup_list: []const u8, index: u16, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
        _ = allocator;
        _ = face;
        const lookup_off = try OtLayout.getLookupOffset(lookup_list, index);
        const lookup_data = try sliceFrom(lookup_list, lookup_off);
        const lookup_type = try readU16(lookup_data, OtLayout.lookup_type_offset);
        const subtable_count = try readU16(lookup_data, OtLayout.lookup_subtable_count_offset);

        for (0..subtable_count) |i| {
            const subtable_off = try readU16(lookup_data, OtLayout.lookup_subtable_offsets_offset + i * 2);
            const subtable_data = try sliceFrom(lookup_data, subtable_off);

            if (lookup_type == @intFromEnum(GsubLookupType.single_substitution)) {
                try applySingleSubstitution(subtable_data, glyphs);
            } else if (lookup_type == @intFromEnum(GsubLookupType.ligature_substitution)) {
                try applyLigatureSubstitution(subtable_data, glyphs);
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
};

const GposLookupType = enum(u16) {
    single_adjustment = 1,
    pair_adjustment = 2,
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

    fn apply(allocator: std.mem.Allocator, face: font_parser.Face, glyphs: []ShapedGlyph) font_parser.ParserError!void {
        const data = face.getTable(TableTags.gpos) orelse return;
        if (data.len < OtLayout.header_min_size) return font_parser.ParserError.InvalidTable;

        const script_list_off = try readU16(data, OtLayout.script_list_offset);
        const feature_list_off = try readU16(data, OtLayout.feature_list_offset);
        const lookup_list_off = try readU16(data, OtLayout.lookup_list_offset);
        const script_list_data = try sliceFrom(data, script_list_off);
        const feature_list_data = try sliceFrom(data, feature_list_off);
        const lookup_list_data = try sliceFrom(data, lookup_list_off);

        var script_off_val = try OtLayout.findScriptOffset(script_list_data, "DFLT".*);
        if (script_off_val == null) {
            script_off_val = try OtLayout.findScriptOffset(script_list_data, "latn".*);
        }
        const actual_script_off = script_off_val orelse return;
        const script_data = try sliceFrom(script_list_data, actual_script_off);
        const default_lang_sys_off = try readU16(script_data, 0);
        if (default_lang_sys_off == 0) return;

        const lang_sys_data = try sliceFrom(script_data, default_lang_sys_off);
        const feature_count = try readU16(lang_sys_data, OtLayout.lang_sys_feature_count_offset);

        for (0..feature_count) |i| {
            const feature_index = try readU16(lang_sys_data, OtLayout.lang_sys_feature_indices_offset + i * 2);
            const feature_offset = OtLayout.feature_list_count_offset + 2 + @as(usize, feature_index) * OtLayout.feature_record_size;
            const feature_data_off = try readU16(feature_list_data, feature_offset + OtLayout.feature_offset_offset);
            const feature_data = try sliceFrom(feature_list_data, feature_data_off);
            const lookup_count = try readU16(feature_data, OtLayout.feature_data_lookup_count_offset);

            for (0..lookup_count) |j| {
                const lookup_index = try readU16(feature_data, OtLayout.feature_data_lookup_indices_offset + j * 2);
                try applyLookup(allocator, face, lookup_list_data, lookup_index, glyphs);
            }
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
        try Gsub.apply(allocator, face, &glyphs);

        // Update metrics for potentially new glyph IDs from GSUB
        for (glyphs.items) |*glyph| {
            const metric = try face.getHMetric(glyph.glyph_id);
            glyph.advance_width = metric.advance_width;
            glyph.x_advance = @as(i32, metric.advance_width);
            glyph.lsb = metric.lsb;
        }

        // 2. GPOS positioning
        try Gpos.apply(allocator, face, glyphs.items);
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

fn readU16(data: []const u8, offset: usize) font_parser.ParserError!u16 {
    if (offset + 2 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readI16(data: []const u8, offset: usize) font_parser.ParserError!i16 {
    if (offset + 2 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

fn sliceFrom(data: []const u8, offset: usize) font_parser.ParserError![]const u8 {
    if (offset > data.len) return font_parser.ParserError.InvalidTable;
    return data[offset..];
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
