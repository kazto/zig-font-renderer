const std = @import("std");
const font_parser = @import("font_parser.zig");
const shaper = @import("shaper.zig");

pub const SvgError = font_parser.ParserError || shaper.ShapeError || std.mem.Allocator.Error || error{
    UnsupportedCompositeGlyph,
    MissingText,
};

const max_composite_depth = 8;
const default_font_size_px = 64.0;
const default_margin_px = 8.0;

const TableTags = struct {
    const glyf = "glyf".*;
    const head = "head".*;
    const loca = "loca".*;
};

const Head = struct {
    const min_size_for_loca_format = 52;
    const index_to_loc_format_offset = 50;
    const short_loca_format = 0;
    const long_loca_format = 1;
};

const Loca = struct {
    const short_entry_size = 2;
    const short_entry_scale = 2;
    const long_entry_size = 4;
};

const Glyf = struct {
    const header_size = 10;
    const number_of_contours_offset = 0;
    const end_points_offset = 10;
    const contour_endpoint_size = 2;
    const instruction_length_size = 2;
    const empty_contour_count = 0;
    const composite_contour_marker_max = -1;
};

const SimpleGlyphFlag = struct {
    const on_curve = 0x01;
    const x_short_vector = 0x02;
    const y_short_vector = 0x04;
    const repeat = 0x08;
    const x_is_same_or_positive_short = 0x10;
    const y_is_same_or_positive_short = 0x20;
};

const CompositeGlyphFlag = struct {
    const arg_1_and_2_are_words = 0x0001;
    const args_are_xy_values = 0x0002;
    const has_scale = 0x0008;
    const more_components = 0x0020;
    const has_xy_scale = 0x0040;
    const has_2x2 = 0x0080;
};

const CompositeGlyph = struct {
    const components_offset = 10;
    const component_header_size = 4;
    const flags_offset = 0;
    const glyph_id_offset = 2;
    const word_args_size = 4;
    const byte_args_size = 2;
    const scale_size = 2;
    const xy_scale_size = 4;
    const matrix_2x2_size = 8;
    const f2dot14_one = 0x4000;
};

pub const RenderOptions = struct {
    font_size_px: f64 = default_font_size_px,
    margin_px: f64 = default_margin_px,
};

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
        return self.renderTextWithOptions(allocator, face, text, .{});
    }

    pub fn renderTextWithOptions(
        self: SvgRenderer,
        allocator: std.mem.Allocator,
        face: font_parser.Face,
        text: []const u8,
        options: RenderOptions,
    ) SvgError![]u8 {
        _ = self;

        const engine = shaper.ShapeEngine.init();
        var shaped = try engine.shapeText(allocator, face, text);
        defer shaped.deinit(allocator);

        const raw_width = if (shaped.total_advance > 0) shaped.total_advance else @as(i32, face.units_per_em);
        const scale = options.font_size_px / @as(f64, @floatFromInt(face.units_per_em));
        const width_px = @as(f64, @floatFromInt(raw_width)) * scale + options.margin_px * 2.0;
        const height_px = options.font_size_px * 1.25 + options.margin_px * 2.0;

        var output = std.ArrayList(u8).empty;
        errdefer output.deinit(allocator);
        const writer = output.writer(allocator);

        try writer.print(
            \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.2}" height="{d:.2}" viewBox="0 0 {d:.2} {d:.2}">
            \\  <g fill="black" transform="translate({d:.2} {d:.2}) scale({d:.6} {d:.6})">
            \\
        , .{
            width_px,
            height_px,
            width_px,
            height_px,
            options.margin_px,
            options.margin_px + options.font_size_px,
            scale,
            -scale,
        });

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

    const glyf = try face.requireTable(TableTags.glyf);
    if (range.end > glyf.len or range.start + Glyf.header_size > range.end) return font_parser.ParserError.InvalidTable;

    const glyph = glyf[range.start..range.end];
    const number_of_contours = try readI16(glyph, Glyf.number_of_contours_offset);
    if (number_of_contours == Glyf.empty_contour_count) return;
    if (number_of_contours <= Glyf.composite_contour_marker_max) {
        return appendCompositeGlyphPaths(allocator, writer, face, glyph, x_offset, y_offset, depth + 1);
    }

    const contour_count = @as(usize, @intCast(number_of_contours));
    if (Glyf.end_points_offset + contour_count * Glyf.contour_endpoint_size + Glyf.instruction_length_size > glyph.len) return font_parser.ParserError.InvalidTable;

    const end_points = try allocator.alloc(u16, contour_count);
    defer allocator.free(end_points);
    for (end_points, 0..) |*end_point, index| {
        end_point.* = try readU16(glyph, Glyf.end_points_offset + index * Glyf.contour_endpoint_size);
    }

    const point_count = @as(usize, end_points[end_points.len - 1]) + 1;
    const instruction_len_offset = Glyf.end_points_offset + contour_count * Glyf.contour_endpoint_size;
    const instruction_len = try readU16(glyph, instruction_len_offset);
    var offset = instruction_len_offset + Glyf.instruction_length_size + @as(usize, instruction_len);
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

        if ((flag & SimpleGlyphFlag.repeat) != 0) {
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
        const delta = try readCoordinateDelta(glyph, &offset, flag, SimpleGlyphFlag.x_short_vector, SimpleGlyphFlag.x_is_same_or_positive_short);
        x = @as(i16, @intCast(@as(i32, x) + delta));
        point.x = x;
        point.on_curve = (flag & SimpleGlyphFlag.on_curve) != 0;
    }

    var y: i16 = 0;
    for (points, flags) |*point, flag| {
        const delta = try readCoordinateDelta(glyph, &offset, flag, SimpleGlyphFlag.y_short_vector, SimpleGlyphFlag.y_is_same_or_positive_short);
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
    var offset: usize = CompositeGlyph.components_offset;
    var more_components = true;
    while (more_components) {
        if (offset + CompositeGlyph.component_header_size > glyph.len) return font_parser.ParserError.InvalidTable;
        const flags = try readU16(glyph, offset + CompositeGlyph.flags_offset);
        const component_glyph_id = try readU16(glyph, offset + CompositeGlyph.glyph_id_offset);
        offset += CompositeGlyph.component_header_size;

        if ((flags & CompositeGlyphFlag.args_are_xy_values) == 0) return SvgError.UnsupportedCompositeGlyph;

        var component_x: i32 = 0;
        var component_y: i32 = 0;
        if ((flags & CompositeGlyphFlag.arg_1_and_2_are_words) != 0) {
            component_x = try readI16(glyph, offset);
            component_y = try readI16(glyph, offset + 2);
            offset += CompositeGlyph.word_args_size;
        } else {
            if (offset + CompositeGlyph.byte_args_size > glyph.len) return font_parser.ParserError.InvalidTable;
            component_x = @as(i32, @as(i8, @bitCast(glyph[offset])));
            component_y = @as(i32, @as(i8, @bitCast(glyph[offset + 1])));
            offset += CompositeGlyph.byte_args_size;
        }

        if ((flags & CompositeGlyphFlag.has_scale) != 0) {
            if (offset + CompositeGlyph.scale_size > glyph.len) return font_parser.ParserError.InvalidTable;
            const scale = try readI16(glyph, offset);
            offset += CompositeGlyph.scale_size;
            if (scale != CompositeGlyph.f2dot14_one) return SvgError.UnsupportedCompositeGlyph;
        } else if ((flags & CompositeGlyphFlag.has_xy_scale) != 0) {
            if (offset + CompositeGlyph.xy_scale_size > glyph.len) return font_parser.ParserError.InvalidTable;
            const x_scale = try readI16(glyph, offset);
            const y_scale = try readI16(glyph, offset + 2);
            offset += CompositeGlyph.xy_scale_size;
            if (x_scale != CompositeGlyph.f2dot14_one or y_scale != CompositeGlyph.f2dot14_one) return SvgError.UnsupportedCompositeGlyph;
        } else if ((flags & CompositeGlyphFlag.has_2x2) != 0) {
            if (offset + CompositeGlyph.matrix_2x2_size > glyph.len) return font_parser.ParserError.InvalidTable;
            const xx = try readI16(glyph, offset);
            const yx = try readI16(glyph, offset + 2);
            const xy = try readI16(glyph, offset + 4);
            const yy = try readI16(glyph, offset + 6);
            offset += CompositeGlyph.matrix_2x2_size;
            if (xx != CompositeGlyph.f2dot14_one or yx != 0 or xy != 0 or yy != CompositeGlyph.f2dot14_one) return SvgError.UnsupportedCompositeGlyph;
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

        more_components = (flags & CompositeGlyphFlag.more_components) != 0;
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

    const head = try face.requireTable(TableTags.head);
    const loca = try face.requireTable(TableTags.loca);
    const glyf = try face.requireTable(TableTags.glyf);
    if (head.len < Head.min_size_for_loca_format) return font_parser.ParserError.InvalidTable;

    const index_to_loc_format = try readI16(head, Head.index_to_loc_format_offset);
    const index = @as(usize, glyph_id);
    const start: usize = switch (index_to_loc_format) {
        Head.short_loca_format => @as(usize, try readU16(loca, index * Loca.short_entry_size)) * Loca.short_entry_scale,
        Head.long_loca_format => @as(usize, try readU32(loca, index * Loca.long_entry_size)),
        else => return font_parser.ParserError.InvalidTable,
    };
    const end: usize = switch (index_to_loc_format) {
        Head.short_loca_format => @as(usize, try readU16(loca, (index + 1) * Loca.short_entry_size)) * Loca.short_entry_scale,
        Head.long_loca_format => @as(usize, try readU32(loca, (index + 1) * Loca.long_entry_size)),
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
