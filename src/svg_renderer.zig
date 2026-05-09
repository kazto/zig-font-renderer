const std = @import("std");
const font_parser = @import("font_parser.zig");
const shaper = @import("shaper.zig");

pub const SvgError = font_parser.ParserError || shaper.ShapeError || std.mem.Allocator.Error || error{
    UnsupportedCompositeGlyph,
    MissingText,
};

const max_composite_depth = 8;

const Point = struct {
    x: i16,
    y: i16,
    on_curve: bool,
};

const GlyphRange = struct {
    start: usize,
    end: usize,
};

pub const SvgRenderer = struct {
    pub fn init() SvgRenderer {
        return .{};
    }

    pub fn renderText(
        self: SvgRenderer,
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        text: []const u8,
    ) SvgError![]u8 {
        _ = self;

        const engine = shaper.ShapeEngine.init();
        var shaped = try engine.shapeText(allocator, face, text);
        defer shaped.deinit(allocator);

        const width = if (shaped.total_advance > 0) shaped.total_advance else @as(i32, face.units_per_em);
        var output = std.ArrayList(u8).empty;
        errdefer output.deinit(allocator);
        const writer = output.writer(allocator);

        try writer.print(
            \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -{d} {d} {d}">
            \\  <g fill="black" transform="scale(1 -1)">
            \\
        , .{ face.units_per_em, width, face.units_per_em + face.units_per_em / 4 });

        for (shaped.glyphs) |glyph| {
            try appendGlyphPath(allocator, writer, face, glyph.glyph_id, glyph.x_offset, 0, 0);
        }

        try writer.print(
            \\  </g>
            \\</svg>
            \\
        , .{});

        return try output.toOwnedSlice(allocator);
    }
};

fn appendGlyphPath(
    allocator: std.mem.Allocator,
    writer: std.ArrayList(u8).Writer,
    face: font_parser.Face,
    glyph_id: u16,
    x_offset: i32,
    y_offset: i32,
    depth: u8,
) SvgError!void {
    if (depth > max_composite_depth) return SvgError.UnsupportedCompositeGlyph;

    const range = try glyphRange(face, glyph_id);
    if (range.start == range.end) return;

    const glyf = try face.requireTable("glyf".*);
    if (range.end > glyf.len or range.start + 10 > range.end) return font_parser.ParserError.InvalidTable;

    const glyph = glyf[range.start..range.end];
    const number_of_contours = try readI16(glyph, 0);
    if (number_of_contours == 0) return;
    if (number_of_contours < 0) {
        return appendCompositeGlyphPaths(allocator, writer, face, glyph, x_offset, y_offset, depth + 1);
    }

    const contour_count = @as(usize, @intCast(number_of_contours));
    if (10 + contour_count * 2 + 2 > glyph.len) return font_parser.ParserError.InvalidTable;

    const end_points = try allocator.alloc(u16, contour_count);
    defer allocator.free(end_points);
    for (end_points, 0..) |*end_point, index| {
        end_point.* = try readU16(glyph, 10 + index * 2);
    }

    const point_count = @as(usize, end_points[end_points.len - 1]) + 1;
    const instruction_len_offset = 10 + contour_count * 2;
    const instruction_len = try readU16(glyph, instruction_len_offset);
    var offset = instruction_len_offset + 2 + @as(usize, instruction_len);
    if (offset > glyph.len) return font_parser.ParserError.InvalidTable;

    const flags = try allocator.alloc(u8, point_count);
    defer allocator.free(flags);
    var flag_index: usize = 0;
    while (flag_index < point_count) {
        if (offset >= glyph.len) return font_parser.ParserError.InvalidTable;
        const flag = glyph[offset];
        offset += 1;
        flags[flag_index] = flag;
        flag_index += 1;

        if ((flag & 0x08) != 0) {
            if (offset >= glyph.len) return font_parser.ParserError.InvalidTable;
            const repeat_count = glyph[offset];
            offset += 1;
            var repeat_index: usize = 0;
            while (repeat_index < repeat_count) : (repeat_index += 1) {
                if (flag_index >= point_count) return font_parser.ParserError.InvalidTable;
                flags[flag_index] = flag;
                flag_index += 1;
            }
        }
    }

    const points = try allocator.alloc(Point, point_count);
    defer allocator.free(points);

    var x: i16 = 0;
    for (points, flags) |*point, flag| {
        const delta = try readCoordinateDelta(glyph, &offset, flag, 0x02, 0x10);
        x = @as(i16, @intCast(@as(i32, x) + delta));
        point.x = x;
        point.on_curve = (flag & 0x01) != 0;
    }

    var y: i16 = 0;
    for (points, flags) |*point, flag| {
        const delta = try readCoordinateDelta(glyph, &offset, flag, 0x04, 0x20);
        y = @as(i16, @intCast(@as(i32, y) + delta));
        point.y = y;
    }

    try writer.print("    <path d=\"", .{});
    var contour_start: usize = 0;
    for (end_points) |end_point| {
        const contour_end = @as(usize, end_point);
        try appendContourPath(writer, points[contour_start .. contour_end + 1], x_offset, y_offset);
        contour_start = contour_end + 1;
    }
    try writer.print("\"/>\n", .{});
}

fn appendCompositeGlyphPaths(
    allocator: std.mem.Allocator,
    writer: std.ArrayList(u8).Writer,
    face: font_parser.Face,
    glyph: []const u8,
    x_offset: i32,
    y_offset: i32,
    depth: u8,
) SvgError!void {
    var offset: usize = 10;
    var more_components = true;
    while (more_components) {
        if (offset + 4 > glyph.len) return font_parser.ParserError.InvalidTable;
        const flags = try readU16(glyph, offset);
        const component_glyph_id = try readU16(glyph, offset + 2);
        offset += 4;

        if ((flags & 0x0002) == 0) return SvgError.UnsupportedCompositeGlyph;

        var component_x: i32 = 0;
        var component_y: i32 = 0;
        if ((flags & 0x0001) != 0) {
            component_x = try readI16(glyph, offset);
            component_y = try readI16(glyph, offset + 2);
            offset += 4;
        } else {
            if (offset + 2 > glyph.len) return font_parser.ParserError.InvalidTable;
            component_x = @as(i32, @as(i8, @bitCast(glyph[offset])));
            component_y = @as(i32, @as(i8, @bitCast(glyph[offset + 1])));
            offset += 2;
        }

        if ((flags & 0x0008) != 0) {
            if (offset + 2 > glyph.len) return font_parser.ParserError.InvalidTable;
            const scale = try readI16(glyph, offset);
            offset += 2;
            if (scale != 0x4000) return SvgError.UnsupportedCompositeGlyph;
        } else if ((flags & 0x0040) != 0) {
            if (offset + 4 > glyph.len) return font_parser.ParserError.InvalidTable;
            const x_scale = try readI16(glyph, offset);
            const y_scale = try readI16(glyph, offset + 2);
            offset += 4;
            if (x_scale != 0x4000 or y_scale != 0x4000) return SvgError.UnsupportedCompositeGlyph;
        } else if ((flags & 0x0080) != 0) {
            if (offset + 8 > glyph.len) return font_parser.ParserError.InvalidTable;
            const xx = try readI16(glyph, offset);
            const yx = try readI16(glyph, offset + 2);
            const xy = try readI16(glyph, offset + 4);
            const yy = try readI16(glyph, offset + 6);
            offset += 8;
            if (xx != 0x4000 or yx != 0 or xy != 0 or yy != 0x4000) return SvgError.UnsupportedCompositeGlyph;
        }

        try appendGlyphPath(
            allocator,
            writer,
            face,
            component_glyph_id,
            x_offset + component_x,
            y_offset + component_y,
            depth,
        );

        more_components = (flags & 0x0020) != 0;
    }

    if (offset > glyph.len) return font_parser.ParserError.InvalidTable;
}

fn appendContourPath(writer: std.ArrayList(u8).Writer, contour: []const Point, x_offset: i32, y_offset: i32) !void {
    if (contour.len == 0) return;

    const first = contour[0];
    try writer.print("M {d} {d} ", .{ x_offset + first.x, y_offset + first.y });

    var index: usize = 1;
    while (index < contour.len) : (index += 1) {
        const current = contour[index];
        if (current.on_curve) {
            try writer.print("L {d} {d} ", .{ x_offset + current.x, y_offset + current.y });
        } else {
            const next = contour[(index + 1) % contour.len];
            if (next.on_curve) {
                try writer.print("Q {d} {d} {d} {d} ", .{ x_offset + current.x, y_offset + current.y, x_offset + next.x, y_offset + next.y });
                if (index + 1 < contour.len) index += 1;
            } else {
                const mid_x = midpoint(current.x, next.x);
                const mid_y = midpoint(current.y, next.y);
                try writer.print("Q {d} {d} {d} {d} ", .{ x_offset + current.x, y_offset + current.y, x_offset + mid_x, y_offset + mid_y });
            }
        }
    }

    try writer.print("Z ", .{});
}

fn glyphRange(face: font_parser.Face, glyph_id: u16) font_parser.ParserError!GlyphRange {
    if (glyph_id >= face.num_glyphs) return font_parser.ParserError.InvalidGlyphId;

    const head = try face.requireTable("head".*);
    const loca = try face.requireTable("loca".*);
    const glyf = try face.requireTable("glyf".*);
    if (head.len < 52) return font_parser.ParserError.InvalidTable;

    const index_to_loc_format = try readI16(head, 50);
    const index = @as(usize, glyph_id);
    const start: usize = switch (index_to_loc_format) {
        0 => @as(usize, try readU16(loca, index * 2)) * 2,
        1 => @as(usize, try readU32(loca, index * 4)),
        else => return font_parser.ParserError.InvalidTable,
    };
    const end: usize = switch (index_to_loc_format) {
        0 => @as(usize, try readU16(loca, (index + 1) * 2)) * 2,
        1 => @as(usize, try readU32(loca, (index + 1) * 4)),
        else => unreachable,
    };

    if (start > end or end > glyf.len) return font_parser.ParserError.InvalidTable;
    return .{ .start = start, .end = end };
}

fn readCoordinateDelta(data: []const u8, offset: *usize, flag: u8, short_mask: u8, same_mask: u8) font_parser.ParserError!i32 {
    if ((flag & short_mask) != 0) {
        if (offset.* >= data.len) return font_parser.ParserError.InvalidTable;
        const value = @as(i32, data[offset.*]);
        offset.* += 1;
        return if ((flag & same_mask) != 0) value else -value;
    }

    if ((flag & same_mask) != 0) return 0;
    const value = try readI16(data, offset.*);
    offset.* += 2;
    return value;
}

fn midpoint(a: i16, b: i16) i32 {
    return @divTrunc(@as(i32, a) + @as(i32, b), 2);
}

fn readU16(data: []const u8, offset: usize) font_parser.ParserError!u16 {
    if (offset + 2 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readI16(data: []const u8, offset: usize) font_parser.ParserError!i16 {
    if (offset + 2 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) font_parser.ParserError!u32 {
    if (offset + 4 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

test "midpoint uses integer midpoint" {
    try std.testing.expectEqual(@as(i32, 15), midpoint(10, 20));
    try std.testing.expectEqual(@as(i32, -5), midpoint(-10, 0));
}

test "composite glyph parser rejects point-matched components" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    const writer = output.writer(allocator);
    const face: font_parser.Face = undefined;
    const glyph = [_]u8{
        0xff, 0xff, 0, 0, 0, 0, 0, 0, 0, 0,
        0,    0,    0, 1, 0, 0, 0, 0,
    };

    try std.testing.expectError(
        SvgError.UnsupportedCompositeGlyph,
        appendCompositeGlyphPaths(allocator, writer, face, &glyph, 0, 0, 0),
    );
}
