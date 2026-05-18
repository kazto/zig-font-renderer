const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");
const ot_layout = @import("ot_layout.zig");
const types = @import("shaper_types.zig");

const readU16 = binary_reader.readU16;
const ShapedGlyph = types.ShapedGlyph;

const alt_format_offset = 0;
const alt_coverage_offset = 2;
const alt_set_count_offset = 4;
const alt_set_offsets_offset = 6;
const alt_set_glyph_count_offset = 0;
const alt_set_alternate_glyphs_offset = 2;

pub fn apply(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
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

        glyph.glyph_id = try readU16(alt_set_data, alt_set_alternate_glyphs_offset);
    }
}
