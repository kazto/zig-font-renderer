const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");
const chained_contextual = @import("gsub_chained_contextual.zig");
const ot_layout = @import("ot_layout.zig");
const types = @import("shaper_types.zig");

const readU16 = binary_reader.readU16;
const LayoutError = types.LayoutError;
const ShapedGlyph = types.ShapedGlyph;

const context_format_offset = 0;
const context_f1_coverage_offset = 2;
const context_f1_rule_set_count_offset = 4;
const context_f1_rule_set_offsets_offset = 6;
const context_rule_set_count_offset = 0;
const context_rule_set_offsets_offset = 2;
const context_rule_glyph_count_offset = 0;
const context_rule_subst_count_offset = 2;
const context_rule_input_sequence_offset = 4;
const context_f2_coverage_offset = 2;
const context_f2_class_def_offset = 4;
const context_f2_class_set_count_offset = 6;
const context_f2_class_set_offsets_offset = 8;
const context_class_set_count_offset = 0;
const context_class_set_offsets_offset = 2;
const context_class_rule_glyph_count_offset = 0;
const context_class_rule_subst_count_offset = 2;
const context_class_rule_input_sequence_offset = 4;
const subst_record_size = 4;

pub const ApplySubstitutionRecordsFn = *const fn (
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    lookup_list: []const u8,
    subst_records: []const u8,
    subst_count: u16,
    glyphs: *std.ArrayList(ShapedGlyph),
    start: usize,
    depth: usize,
) LayoutError!void;

pub fn apply(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    lookup_list: []const u8,
    subtable: []const u8,
    glyphs: *std.ArrayList(ShapedGlyph),
    depth: usize,
    apply_substitution_records: ApplySubstitutionRecordsFn,
) LayoutError!void {
    const format = try readU16(subtable, context_format_offset);
    if (format == 1) {
        try applyFormat1(allocator, face, lookup_list, subtable, glyphs, depth, apply_substitution_records);
    } else if (format == 2) {
        try applyFormat2(allocator, face, lookup_list, subtable, glyphs, depth, apply_substitution_records);
    } else if (format == 3) {
        try applyFormat3(allocator, face, lookup_list, subtable, glyphs, depth, apply_substitution_records);
    }
}

pub fn applyFormat1(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    lookup_list: []const u8,
    subtable: []const u8,
    glyphs: *std.ArrayList(ShapedGlyph),
    depth: usize,
    apply_substitution_records: ApplySubstitutionRecordsFn,
) LayoutError!void {
    const coverage_off = try readU16(subtable, context_f1_coverage_offset);
    const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);
    const rule_set_count = try readU16(subtable, context_f1_rule_set_count_offset);

    var i: usize = 0;
    while (i < glyphs.items.len) {
        const coverage_index = try ot_layout.Coverage.getIndex(coverage_data, glyphs.items[i].glyph_id) orelse {
            i += 1;
            continue;
        };
        if (coverage_index >= rule_set_count) return font_parser.ParserError.InvalidTable;

        const rule_set_off = try readU16(subtable, context_f1_rule_set_offsets_offset + @as(usize, coverage_index) * 2);
        if (rule_set_off == 0) {
            i += 1;
            continue;
        }

        const rule_set = try ot_layout.sliceFrom(subtable, rule_set_off);
        const rule_count = try readU16(rule_set, context_rule_set_count_offset);
        var matched_len: ?u16 = null;

        for (0..rule_count) |rule_idx| {
            const rule_off = try readU16(rule_set, context_rule_set_offsets_offset + rule_idx * 2);
            const rule = try ot_layout.sliceFrom(rule_set, rule_off);
            const glyph_count = try readU16(rule, context_rule_glyph_count_offset);
            const subst_count = try readU16(rule, context_rule_subst_count_offset);
            if (glyph_count == 0 or i + glyph_count > glyphs.items.len) continue;

            var matches = true;
            for (1..glyph_count) |input_idx| {
                const expected_gid = try readU16(rule, context_rule_input_sequence_offset + (input_idx - 1) * 2);
                if (glyphs.items[i + input_idx].glyph_id != expected_gid) {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;

            const subst_records_offset = context_rule_input_sequence_offset + @as(usize, glyph_count - 1) * 2;
            const subst_records = try ot_layout.sliceRange(rule, subst_records_offset, @as(usize, subst_count) * subst_record_size);
            try apply_substitution_records(allocator, face, lookup_list, subst_records, subst_count, glyphs, i, depth);
            matched_len = glyph_count;
            break;
        }

        if (matched_len) |len| {
            i += len;
        } else {
            i += 1;
        }
    }
}

pub fn applyFormat2(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    lookup_list: []const u8,
    subtable: []const u8,
    glyphs: *std.ArrayList(ShapedGlyph),
    depth: usize,
    apply_substitution_records: ApplySubstitutionRecordsFn,
) LayoutError!void {
    const coverage_off = try readU16(subtable, context_f2_coverage_offset);
    const class_def_off = try readU16(subtable, context_f2_class_def_offset);
    const class_set_count = try readU16(subtable, context_f2_class_set_count_offset);
    const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);
    const class_def = try ot_layout.sliceFrom(subtable, class_def_off);

    var i: usize = 0;
    while (i < glyphs.items.len) {
        if (try ot_layout.Coverage.getIndex(coverage_data, glyphs.items[i].glyph_id) == null) {
            i += 1;
            continue;
        }

        const first_class = try ot_layout.ClassDef.getClass(class_def, glyphs.items[i].glyph_id);
        if (first_class >= class_set_count) return font_parser.ParserError.InvalidTable;

        const class_set_off = try readU16(subtable, context_f2_class_set_offsets_offset + @as(usize, first_class) * 2);
        if (class_set_off == 0) {
            i += 1;
            continue;
        }

        const class_set = try ot_layout.sliceFrom(subtable, class_set_off);
        const class_rule_count = try readU16(class_set, context_class_set_count_offset);
        var matched_len: ?u16 = null;

        for (0..class_rule_count) |rule_idx| {
            const class_rule_off = try readU16(class_set, context_class_set_offsets_offset + rule_idx * 2);
            const class_rule = try ot_layout.sliceFrom(class_set, class_rule_off);
            const glyph_count = try readU16(class_rule, context_class_rule_glyph_count_offset);
            const subst_count = try readU16(class_rule, context_class_rule_subst_count_offset);
            if (glyph_count == 0 or i + glyph_count > glyphs.items.len) continue;

            var matches = true;
            for (1..glyph_count) |input_idx| {
                const expected_class = try readU16(class_rule, context_class_rule_input_sequence_offset + (input_idx - 1) * 2);
                const actual_class = try ot_layout.ClassDef.getClass(class_def, glyphs.items[i + input_idx].glyph_id);
                if (actual_class != expected_class) {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;

            const subst_records_offset = context_class_rule_input_sequence_offset + @as(usize, glyph_count - 1) * 2;
            const subst_records = try ot_layout.sliceRange(class_rule, subst_records_offset, @as(usize, subst_count) * subst_record_size);
            try apply_substitution_records(allocator, face, lookup_list, subst_records, subst_count, glyphs, i, depth);
            matched_len = glyph_count;
            break;
        }

        if (matched_len) |len| {
            i += len;
        } else {
            i += 1;
        }
    }
}

pub fn applyFormat3(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    lookup_list: []const u8,
    subtable: []const u8,
    glyphs: *std.ArrayList(ShapedGlyph),
    depth: usize,
    apply_substitution_records: ApplySubstitutionRecordsFn,
) LayoutError!void {
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
        if (try chained_contextual.matchFormat3(subtable, &[_]u8{}, input_coverages, &[_]u8{}, glyphs.items, i)) {
            try apply_substitution_records(allocator, face, lookup_list, subst_records, subst_count, glyphs, i, depth);
            i += input_count;
        } else {
            i += 1;
        }
    }
}
