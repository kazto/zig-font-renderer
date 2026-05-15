const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");
const ot_layout = @import("ot_layout.zig");
const types = @import("shaper_types.zig");

const readU16 = binary_reader.readU16;
const LayoutError = types.LayoutError;
const ShapedGlyph = types.ShapedGlyph;

const subst_record_size = 4;

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
    const format = try readU16(subtable, 0);
    if (format == 1) {
        try applyFormat1(allocator, face, lookup_list, subtable, glyphs, depth, apply_substitution_records);
    } else if (format == 2) {
        try applyFormat2(allocator, face, lookup_list, subtable, glyphs, depth, apply_substitution_records);
    } else if (format == 3) {
        try applyFormat3(allocator, face, lookup_list, subtable, glyphs, depth, apply_substitution_records);
    }
}

fn applyFormat1(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    lookup_list: []const u8,
    subtable: []const u8,
    glyphs: *std.ArrayList(ShapedGlyph),
    depth: usize,
    apply_substitution_records: ApplySubstitutionRecordsFn,
) LayoutError!void {
    const coverage_off = try readU16(subtable, chained_f1_coverage_offset);
    const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);
    const rule_set_count = try readU16(subtable, chained_f1_rule_set_count_offset);

    var i: usize = 0;
    while (i < glyphs.items.len) {
        const coverage_index = try ot_layout.Coverage.getIndex(coverage_data, glyphs.items[i].glyph_id) orelse {
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
        const rule_count = try readU16(rule_set, chain_rule_set_count_offset);
        var matched_len: ?u16 = null;

        for (0..rule_count) |rule_idx| {
            const rule_off = try readU16(rule_set, chain_rule_set_offsets_offset + rule_idx * 2);
            const rule = try ot_layout.sliceFrom(rule_set, rule_off);
            const backtrack_count = try readU16(rule, chain_rule_backtrack_count_offset);
            var offset: usize = chain_rule_backtrack_count_offset + 2;

            if (i < backtrack_count) continue;
            var matches = true;
            for (0..backtrack_count) |j| {
                const expected_gid = try readU16(rule, offset + j * 2);
                if (glyphs.items[i - 1 - j].glyph_id != expected_gid) {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;
            offset += @as(usize, backtrack_count) * 2;

            const input_count = try readU16(rule, offset);
            offset += 2;
            if (input_count == 0 or i + input_count > glyphs.items.len) continue;
            for (1..input_count) |input_idx| {
                const expected_gid = try readU16(rule, offset + (input_idx - 1) * 2);
                if (glyphs.items[i + input_idx].glyph_id != expected_gid) {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;
            offset += @as(usize, input_count - 1) * 2;

            const lookahead_count = try readU16(rule, offset);
            offset += 2;
            if (i + input_count + lookahead_count > glyphs.items.len) continue;
            for (0..lookahead_count) |lookahead_idx| {
                const expected_gid = try readU16(rule, offset + lookahead_idx * 2);
                if (glyphs.items[i + input_count + lookahead_idx].glyph_id != expected_gid) {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;
            offset += @as(usize, lookahead_count) * 2;

            const subst_count = try readU16(rule, offset);
            offset += 2;
            const subst_records = try ot_layout.sliceRange(rule, offset, @as(usize, subst_count) * subst_record_size);
            try apply_substitution_records(allocator, face, lookup_list, subst_records, subst_count, glyphs, i, depth);
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

fn applyFormat2(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    lookup_list: []const u8,
    subtable: []const u8,
    glyphs: *std.ArrayList(ShapedGlyph),
    depth: usize,
    apply_substitution_records: ApplySubstitutionRecordsFn,
) LayoutError!void {
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
    while (i < glyphs.items.len) {
        if (try ot_layout.Coverage.getIndex(coverage_data, glyphs.items[i].glyph_id) == null) {
            i += 1;
            continue;
        }

        const first_class = try ot_layout.ClassDef.getClass(input_class_def, glyphs.items[i].glyph_id);
        if (first_class >= class_set_count) return font_parser.ParserError.InvalidTable;

        const class_set_off = try readU16(subtable, chained_f2_class_set_offsets_offset + @as(usize, first_class) * 2);
        if (class_set_off == 0) {
            i += 1;
            continue;
        }

        const class_set = try ot_layout.sliceFrom(subtable, class_set_off);
        const class_rule_count = try readU16(class_set, chain_class_set_count_offset);
        var matched_len: ?u16 = null;

        for (0..class_rule_count) |rule_idx| {
            const class_rule_off = try readU16(class_set, chain_class_set_offsets_offset + rule_idx * 2);
            const class_rule = try ot_layout.sliceFrom(class_set, class_rule_off);
            const backtrack_count = try readU16(class_rule, chain_class_rule_backtrack_count_offset);
            var offset: usize = chain_class_rule_backtrack_count_offset + 2;

            if (i < backtrack_count) continue;
            var matches = true;
            for (0..backtrack_count) |j| {
                const expected_class = try readU16(class_rule, offset + j * 2);
                const actual_class = try ot_layout.ClassDef.getClass(backtrack_class_def, glyphs.items[i - 1 - j].glyph_id);
                if (actual_class != expected_class) {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;
            offset += @as(usize, backtrack_count) * 2;

            const input_count = try readU16(class_rule, offset);
            offset += 2;
            if (input_count == 0 or i + input_count > glyphs.items.len) continue;
            for (1..input_count) |input_idx| {
                const expected_class = try readU16(class_rule, offset + (input_idx - 1) * 2);
                const actual_class = try ot_layout.ClassDef.getClass(input_class_def, glyphs.items[i + input_idx].glyph_id);
                if (actual_class != expected_class) {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;
            offset += @as(usize, input_count - 1) * 2;

            const lookahead_count = try readU16(class_rule, offset);
            offset += 2;
            if (i + input_count + lookahead_count > glyphs.items.len) continue;
            for (0..lookahead_count) |lookahead_idx| {
                const expected_class = try readU16(class_rule, offset + lookahead_idx * 2);
                const actual_class = try ot_layout.ClassDef.getClass(lookahead_class_def, glyphs.items[i + input_count + lookahead_idx].glyph_id);
                if (actual_class != expected_class) {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;
            offset += @as(usize, lookahead_count) * 2;

            const subst_count = try readU16(class_rule, offset);
            offset += 2;
            const subst_records = try ot_layout.sliceRange(class_rule, offset, @as(usize, subst_count) * subst_record_size);
            try apply_substitution_records(allocator, face, lookup_list, subst_records, subst_count, glyphs, i, depth);
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

fn applyFormat3(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    lookup_list: []const u8,
    subtable: []const u8,
    glyphs: *std.ArrayList(ShapedGlyph),
    depth: usize,
    apply_substitution_records: ApplySubstitutionRecordsFn,
) LayoutError!void {
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
        if (try matchFormat3(subtable, backtrack_coverages, input_coverages, lookahead_coverages, glyphs.items, i)) {
            try apply_substitution_records(allocator, face, lookup_list, subst_records, subst_count, glyphs, i, depth);
            i += input_count;
        } else {
            i += 1;
        }
    }
}

pub fn matchFormat3(subtable: []const u8, backtrack: []const u8, input: []const u8, lookahead: []const u8, glyphs: []const ShapedGlyph, pos: usize) font_parser.ParserError!bool {
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
