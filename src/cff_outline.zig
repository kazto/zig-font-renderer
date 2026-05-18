const std = @import("std");
const font_parser = @import("font_parser.zig");
const cff_context = @import("cff_context.zig");
const cff_index = @import("cff_index.zig");
const type2_charstring = @import("type2_charstring.zig");
const types = @import("cff_types.zig");

pub const CffError = types.CffError;
pub const Transform = types.Transform;

pub fn appendGlyphPath(writer: std.ArrayList(u8).Writer, cff: []const u8, glyph_id: u16, transform: Transform) CffError!void {
    const context = try cff_context.parseCffContext(cff);
    try appendGlyphPathFromContext(writer, context, glyph_id, transform);
}

pub fn appendCff2GlyphPath(writer: std.ArrayList(u8).Writer, cff2: []const u8, glyph_id: u16, transform: Transform) CffError!void {
    const context = try cff_context.parseCff2Context(cff2);
    try appendGlyphPathFromContext(writer, context, glyph_id, transform);
}

pub fn appendCff2GlyphPathWithVariationCoords(allocator: std.mem.Allocator, writer: std.ArrayList(u8).Writer, cff2: []const u8, glyph_id: u16, transform: Transform, normalized_coords: []const f64) CffError!void {
    var context = try cff_context.parseCff2Context(cff2);
    var weights: ?[]f64 = null;
    defer if (weights) |items| allocator.free(items);

    if (normalized_coords.len > 0) {
        const variation_store_offset = context.cff2_variation_store_offset orelse return font_parser.ParserError.InvalidTable;
        if (variation_store_offset >= cff2.len) return font_parser.ParserError.InvalidTable;
        weights = try cff_context.readCff2VariationRegionWeights(allocator, cff2[variation_store_offset..], normalized_coords);
        context.cff2_blend_region_weights = weights.?;
    }

    try appendGlyphPathFromContext(writer, context, glyph_id, transform);
}

fn appendGlyphPathFromContext(writer: std.ArrayList(u8).Writer, context: cff_context.CffContext, glyph_id: u16, transform: Transform) CffError!void {
    const charstring = try cff_index.getCffIndexObject(context.charstrings, glyph_id);
    if (charstring.len == 0) return;
    const local_subrs = try cff_context.getCffGlyphLocalSubrs(context, glyph_id);

    try writer.print("    <path d=\"", .{});
    try type2_charstring.appendType2CharStringPathWithSubrs(writer, charstring, transform, context, local_subrs);
    try writer.print("\"/>\n", .{});
}
