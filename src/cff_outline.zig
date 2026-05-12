const std = @import("std");
const cff_context = @import("cff_context.zig");
const cff_index = @import("cff_index.zig");
const type2_charstring = @import("type2_charstring.zig");
const types = @import("cff_types.zig");

pub const CffError = types.CffError;
pub const Transform = types.Transform;

pub fn appendGlyphPath(writer: std.ArrayList(u8).Writer, cff: []const u8, glyph_id: u16, transform: Transform) CffError!void {
    const context = try cff_context.parseCffContext(cff);
    const charstring = try cff_index.getCffIndexObject(context.charstrings, glyph_id);
    if (charstring.len == 0) return;
    const local_subrs = try cff_context.getCffGlyphLocalSubrs(context, glyph_id);

    try writer.print("    <path d=\"", .{});
    try type2_charstring.appendType2CharStringPathWithSubrs(writer, charstring, transform, context, local_subrs);
    try writer.print("\"/>\n", .{});
}
