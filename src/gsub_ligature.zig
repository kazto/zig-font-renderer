const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const font_parser = @import("font_parser.zig");
const ot_layout = @import("ot_layout.zig");
const types = @import("shaper_types.zig");

const readU16 = binary_reader.readU16;
const ShapedGlyph = types.ShapedGlyph;

const lig_coverage_offset = 2;
const lig_set_count_offset = 4;
const lig_set_offsets_offset = 6;
const lig_set_ligature_count_offset = 0;
const lig_set_lig_offsets_offset = 2;
const lig_glyph_offset = 0;
const lig_comp_count_offset = 2;
const lig_comp_ids_offset = 4;

pub fn apply(subtable: []const u8, glyphs: *std.ArrayList(ShapedGlyph)) font_parser.ParserError!void {
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
