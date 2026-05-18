const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");
const ot_layout = @import("ot_layout.zig");
const shaper_arabic = @import("shaper_arabic.zig");
const types = @import("shaper_types.zig");

const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;
const ShapedGlyph = types.ShapedGlyph;

const single_format_offset = 0;
const single_coverage_offset = 2;
const single_f1_delta_offset = 4;
const single_f2_count_offset = 4;
const single_f2_substitutes_offset = 6;

pub fn apply(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
    try applyForJoiningForm(subtable, glyphs, null, .none);
}

pub fn applyForJoiningForm(
    subtable: []const u8,
    glyphs: *std.ArrayList(ShapedGlyph),
    forms: ?[]const shaper_arabic.JoiningForm,
    target_form: shaper_arabic.JoiningForm,
) font_parser.ParserError!void {
    const format = try readU16(subtable, single_format_offset);
    const coverage_off = try readU16(subtable, single_coverage_offset);
    const coverage_data = try ot_layout.sliceFrom(subtable, coverage_off);

    for (glyphs.items, 0..) |*glyph, index| {
        if (forms) |joining_forms| {
            if (index >= joining_forms.len) return font_parser.ParserError.InvalidTable;
            if (joining_forms[index] != target_form) continue;
        }
        if (try ot_layout.Coverage.getIndex(coverage_data, glyph.glyph_id)) |coverage_index| {
            if (format == 1) {
                const delta = try readI16(subtable, single_f1_delta_offset);
                glyph.glyph_id = @intCast(@mod(@as(i32, glyph.glyph_id) + delta, 65536));
            } else if (format == 2) {
                const count = try readU16(subtable, single_f2_count_offset);
                if (coverage_index >= count) return font_parser.ParserError.InvalidTable;
                glyph.glyph_id = try readU16(subtable, single_f2_substitutes_offset + @as(usize, coverage_index) * 2);
            }
        }
    }
}
