const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const cff_outline = @import("cff_outline.zig");
const font_parser = @import("font_parser.zig");
const shaper = @import("shaper.zig");
const svg_geometry = @import("svg_geometry.zig");

const readU16 = binary_reader.readU16;
const readI16 = binary_reader.readI16;
const readU32 = binary_reader.readU32;

pub const SvgGlyphError = font_parser.ParserError || cff_outline.CffError || error{
    UnsupportedCffOutlines,
    UnsupportedCompositeGlyph,
};

const max_composite_depth = 8;
const test_units_per_em = 1000;
const test_vertical_origin_y = 200;
const test_vertical_origin_result_y = 193.0;
const test_vorg_data_length = 14;
const test_vorg_glyph_id = 7;
const test_vorg_default_origin_y = 0;
const test_composite_fixture_length = 90;
const test_head_index_to_loc_offset = 50;
const test_loca_table_offset = 52;
const test_loca_table_length = 6;
const test_composite_glyf_offset = 58;
const test_composite_glyph_count = 2;
const test_composite_point_match_count = 2;
const test_simple_component_offset = 74;

const Point = svg_geometry.Point;
const GlyphRange = svg_geometry.GlyphRange;
pub const Transform = svg_geometry.Transform;
const TransformedPoint = svg_geometry.TransformedPoint;
const SimpleGlyphOutline = svg_geometry.SimpleGlyphOutline;
const Bounds = svg_geometry.Bounds;
const midpoint = svg_geometry.midpoint;
const readF2Dot14 = svg_geometry.readF2Dot14;

const TableTags = struct {
    const cff = "CFF ".*;
    const cff2 = "CFF2".*;
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
    const x_min_offset = 2;
    const y_min_offset = 4;
    const x_max_offset = 6;
    const y_max_offset = 8;
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
};

pub fn glyphTransform(face: font_parser.Face, glyph: shaper.ShapedGlyph, direction: shaper.ShapeDirection) SvgGlyphError!Transform {
    const vertical_origin_y: i32 = if (direction == .ttb)
        @as(i32, (try face.getVerticalOriginY(glyph.glyph_id)) orelse 0)
    else
        0;
    return Transform.translate(glyph.x_offset, glyph.y_offset - vertical_origin_y);
}

pub fn textBounds(face: font_parser.Face, shaped: shaper.ShapedText, direction: shaper.ShapeDirection) SvgGlyphError!Bounds {
    var maybe_bounds: ?Bounds = null;

    for (shaped.glyphs) |glyph| {
        const bounds = (try glyphBounds(face, glyph.glyph_id)) orelse continue;
        const transform = try glyphTransform(face, glyph, direction);
        const positioned: Bounds = .{
            .min_x = bounds.min_x + @as(i32, @intFromFloat(transform.dx)),
            .min_y = bounds.min_y + @as(i32, @intFromFloat(transform.dy)),
            .max_x = bounds.max_x + @as(i32, @intFromFloat(transform.dx)),
            .max_y = bounds.max_y + @as(i32, @intFromFloat(transform.dy)),
        };

        if (maybe_bounds) |*current| {
            current.include(positioned);
        } else {
            maybe_bounds = positioned;
        }
    }

    var bounds = maybe_bounds orelse Bounds{
        .min_x = 0,
        .min_y = 0,
        .max_x = @max(1, shaped.total_advance),
        .max_y = @as(i32, face.units_per_em),
    };
    switch (direction) {
        .ttb => bounds.max_y = @max(bounds.max_y, shaped.total_advance),
        else => bounds.max_x = @max(bounds.max_x, shaped.total_advance),
    }
    return bounds;
}

fn glyphBounds(face: font_parser.Face, glyph_id: u16) SvgGlyphError!?Bounds {
    if (face.getTable(TableTags.glyf) == null and (face.getTable(TableTags.cff) != null or face.getTable(TableTags.cff2) != null)) {
        const metric = try face.getHMetric(glyph_id);
        return .{
            .min_x = 0,
            .min_y = 0,
            .max_x = @max(1, @as(i32, metric.advance_width)),
            .max_y = @as(i32, face.units_per_em),
        };
    }

    const range = try glyphRange(face, glyph_id);
    if (range.start == range.end) return null;

    const glyf = try face.requireTable(TableTags.glyf);
    if (range.end > glyf.len or range.start + Glyf.header_size > range.end) return font_parser.ParserError.InvalidTable;

    const glyph = glyf[range.start..range.end];
    return .{
        .min_x = try readI16(glyph, Glyf.x_min_offset),
        .min_y = try readI16(glyph, Glyf.y_min_offset),
        .max_x = try readI16(glyph, Glyf.x_max_offset),
        .max_y = try readI16(glyph, Glyf.y_max_offset),
    };
}

pub fn appendGlyphPath(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    face: font_parser.Face,
    glyph_id: u16,
    transform: Transform,
    depth: u8,
    cff2_variation_coords: []const f64,
) SvgGlyphError!void {
    if (depth > max_composite_depth) return SvgGlyphError.UnsupportedCompositeGlyph;

    if (face.getTable(TableTags.glyf) == null) {
        if (face.getTable(TableTags.cff)) |cff| {
            return cff_outline.appendGlyphPath(writer, cff, glyph_id, .{
                .xx = transform.xx,
                .yx = transform.yx,
                .xy = transform.xy,
                .yy = transform.yy,
                .dx = transform.dx,
                .dy = transform.dy,
            });
        }
        if (face.getTable(TableTags.cff2)) |cff2| {
            return cff_outline.appendCff2GlyphPathWithVariationCoords(allocator, writer, cff2, glyph_id, .{
                .xx = transform.xx,
                .yx = transform.yx,
                .xy = transform.xy,
                .yy = transform.yy,
                .dx = transform.dx,
                .dy = transform.dy,
            }, cff2_variation_coords);
        }
    }

    const range = try glyphRange(face, glyph_id);
    if (range.start == range.end) return;

    const glyf = try face.requireTable(TableTags.glyf);
    if (range.end > glyf.len or range.start + Glyf.header_size > range.end) return font_parser.ParserError.InvalidTable;

    const glyph = glyf[range.start..range.end];
    const number_of_contours = try readI16(glyph, Glyf.number_of_contours_offset);
    if (number_of_contours == Glyf.empty_contour_count) return;
    if (number_of_contours <= Glyf.composite_contour_marker_max) {
        return appendCompositeGlyphPaths(allocator, writer, face, glyph, transform, depth + 1, cff2_variation_coords);
    }

    const outline = try readSimpleGlyphOutline(allocator, glyph, number_of_contours);
    defer outline.deinit(allocator);

    try writer.print("    <path d=\"", .{});
    var contour_start: usize = 0;
    for (outline.end_points) |end_point| {
        const contour_end = @as(usize, end_point);
        try appendContourPath(writer, outline.points[contour_start .. contour_end + 1], transform);
        contour_start = contour_end + 1;
    }
    try writer.print("\"/>\n", .{});
}

fn readSimpleGlyphOutline(
    allocator: std.mem.Allocator,
    glyph: []const u8,
    number_of_contours: i16,
) SvgGlyphError!SimpleGlyphOutline {
    const contour_count = @as(usize, @intCast(number_of_contours));
    if (Glyf.end_points_offset + contour_count * Glyf.contour_endpoint_size + Glyf.instruction_length_size > glyph.len) return font_parser.ParserError.InvalidTable;

    const end_points = try allocator.alloc(u16, contour_count);
    errdefer allocator.free(end_points);
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
    errdefer allocator.free(points);

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

    return .{ .end_points = end_points, .points = points };
}

fn appendCompositeGlyphPaths(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    face: font_parser.Face,
    glyph: []const u8,
    transform: Transform,
    depth: u8,
    cff2_variation_coords: []const f64,
) SvgGlyphError!void {
    var parent_points = std.ArrayList(TransformedPoint).empty;
    defer parent_points.deinit(allocator);

    var offset: usize = CompositeGlyph.components_offset;
    var more_components = true;
    while (more_components) {
        if (offset + CompositeGlyph.component_header_size > glyph.len) return font_parser.ParserError.InvalidTable;
        const flags = try readU16(glyph, offset + CompositeGlyph.flags_offset);
        const component_glyph_id = try readU16(glyph, offset + CompositeGlyph.glyph_id_offset);
        offset += CompositeGlyph.component_header_size;

        const args_are_xy_values = (flags & CompositeGlyphFlag.args_are_xy_values) != 0;

        var arg1: i32 = 0;
        var arg2: i32 = 0;
        if ((flags & CompositeGlyphFlag.arg_1_and_2_are_words) != 0) {
            if (args_are_xy_values) {
                arg1 = try readI16(glyph, offset);
                arg2 = try readI16(glyph, offset + 2);
            } else {
                arg1 = @intCast(try readU16(glyph, offset));
                arg2 = @intCast(try readU16(glyph, offset + 2));
            }
            offset += CompositeGlyph.word_args_size;
        } else {
            if (offset + CompositeGlyph.byte_args_size > glyph.len) return font_parser.ParserError.InvalidTable;
            if (args_are_xy_values) {
                arg1 = @as(i32, @as(i8, @bitCast(glyph[offset])));
                arg2 = @as(i32, @as(i8, @bitCast(glyph[offset + 1])));
            } else {
                arg1 = glyph[offset];
                arg2 = glyph[offset + 1];
            }
            offset += CompositeGlyph.byte_args_size;
        }

        var component_transform = try readCompositeTransform(glyph, flags, &offset);

        if (args_are_xy_values) {
            component_transform.dx = @floatFromInt(arg1);
            component_transform.dy = @floatFromInt(arg2);
        } else {
            const parent_point_index: usize = @intCast(arg1);
            const component_point_index: usize = @intCast(arg2);
            if (parent_point_index >= parent_points.items.len) return font_parser.ParserError.InvalidTable;

            var component_points = std.ArrayList(TransformedPoint).empty;
            defer component_points.deinit(allocator);
            try appendGlyphTransformedPoints(
                allocator,
                face,
                component_glyph_id,
                component_transform,
                &component_points,
                depth,
            );
            if (component_point_index >= component_points.items.len) return font_parser.ParserError.InvalidTable;

            const parent_point = parent_points.items[parent_point_index];
            const component_point = component_points.items[component_point_index];
            component_transform.dx = parent_point.x - component_point.x;
            component_transform.dy = parent_point.y - component_point.y;
        }

        try appendGlyphPath(
            allocator,
            writer,
            face,
            component_glyph_id,
            transform.compose(component_transform),
            depth,
            cff2_variation_coords,
        );

        try appendGlyphTransformedPoints(
            allocator,
            face,
            component_glyph_id,
            component_transform,
            &parent_points,
            depth,
        );

        more_components = (flags & CompositeGlyphFlag.more_components) != 0;
    }

    if (offset > glyph.len) return font_parser.ParserError.InvalidTable;
}

fn appendGlyphTransformedPoints(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    glyph_id: u16,
    transform: Transform,
    points: *std.ArrayList(TransformedPoint),
    depth: u8,
) SvgGlyphError!void {
    if (depth > max_composite_depth) return SvgGlyphError.UnsupportedCompositeGlyph;
    if (face.getTable(TableTags.glyf) == null) return SvgGlyphError.UnsupportedCompositeGlyph;

    const range = try glyphRange(face, glyph_id);
    if (range.start == range.end) return;

    const glyf = try face.requireTable(TableTags.glyf);
    if (range.end > glyf.len or range.start + Glyf.header_size > range.end) return font_parser.ParserError.InvalidTable;

    const glyph = glyf[range.start..range.end];
    const number_of_contours = try readI16(glyph, Glyf.number_of_contours_offset);
    if (number_of_contours == Glyf.empty_contour_count) return;
    if (number_of_contours <= Glyf.composite_contour_marker_max) {
        var composite_points = std.ArrayList(TransformedPoint).empty;
        defer composite_points.deinit(allocator);
        try appendCompositeGlyphTransformedPoints(allocator, face, glyph, &composite_points, depth + 1);
        for (composite_points.items) |point| {
            try points.append(allocator, transform.applyPoint(point));
        }
        return;
    }

    const outline = try readSimpleGlyphOutline(allocator, glyph, number_of_contours);
    defer outline.deinit(allocator);

    for (outline.points) |point| {
        try points.append(allocator, transform.apply(point.x, point.y));
    }
}

fn appendCompositeGlyphTransformedPoints(
    allocator: std.mem.Allocator,
    face: font_parser.Face,
    glyph: []const u8,
    points: *std.ArrayList(TransformedPoint),
    depth: u8,
) SvgGlyphError!void {
    var offset: usize = CompositeGlyph.components_offset;
    var more_components = true;
    while (more_components) {
        if (offset + CompositeGlyph.component_header_size > glyph.len) return font_parser.ParserError.InvalidTable;
        const flags = try readU16(glyph, offset + CompositeGlyph.flags_offset);
        const component_glyph_id = try readU16(glyph, offset + CompositeGlyph.glyph_id_offset);
        offset += CompositeGlyph.component_header_size;

        const args_are_xy_values = (flags & CompositeGlyphFlag.args_are_xy_values) != 0;
        var arg1: i32 = 0;
        var arg2: i32 = 0;
        if ((flags & CompositeGlyphFlag.arg_1_and_2_are_words) != 0) {
            if (args_are_xy_values) {
                arg1 = try readI16(glyph, offset);
                arg2 = try readI16(glyph, offset + 2);
            } else {
                arg1 = @intCast(try readU16(glyph, offset));
                arg2 = @intCast(try readU16(glyph, offset + 2));
            }
            offset += CompositeGlyph.word_args_size;
        } else {
            if (offset + CompositeGlyph.byte_args_size > glyph.len) return font_parser.ParserError.InvalidTable;
            if (args_are_xy_values) {
                arg1 = @as(i32, @as(i8, @bitCast(glyph[offset])));
                arg2 = @as(i32, @as(i8, @bitCast(glyph[offset + 1])));
            } else {
                arg1 = glyph[offset];
                arg2 = glyph[offset + 1];
            }
            offset += CompositeGlyph.byte_args_size;
        }

        var component_transform = try readCompositeTransform(glyph, flags, &offset);
        if (args_are_xy_values) {
            component_transform.dx = @floatFromInt(arg1);
            component_transform.dy = @floatFromInt(arg2);
        } else {
            const parent_point_index: usize = @intCast(arg1);
            const component_point_index: usize = @intCast(arg2);
            if (parent_point_index >= points.items.len) return font_parser.ParserError.InvalidTable;

            var component_points = std.ArrayList(TransformedPoint).empty;
            defer component_points.deinit(allocator);
            try appendGlyphTransformedPoints(allocator, face, component_glyph_id, component_transform, &component_points, depth);
            if (component_point_index >= component_points.items.len) return font_parser.ParserError.InvalidTable;

            const parent_point = points.items[parent_point_index];
            const component_point = component_points.items[component_point_index];
            component_transform.dx = parent_point.x - component_point.x;
            component_transform.dy = parent_point.y - component_point.y;
        }

        try appendGlyphTransformedPoints(allocator, face, component_glyph_id, component_transform, points, depth);
        more_components = (flags & CompositeGlyphFlag.more_components) != 0;
    }

    if (offset > glyph.len) return font_parser.ParserError.InvalidTable;
}

fn readCompositeTransform(glyph: []const u8, flags: u16, offset: *usize) font_parser.ParserError!Transform {
    var transform = Transform{};
    if ((flags & CompositeGlyphFlag.has_scale) != 0) {
        if (offset.* + CompositeGlyph.scale_size > glyph.len) return font_parser.ParserError.InvalidTable;
        const scale = try readF2Dot14(glyph, offset.*);
        offset.* += CompositeGlyph.scale_size;
        transform.xx = scale;
        transform.yy = scale;
    } else if ((flags & CompositeGlyphFlag.has_xy_scale) != 0) {
        if (offset.* + CompositeGlyph.xy_scale_size > glyph.len) return font_parser.ParserError.InvalidTable;
        const x_scale = try readF2Dot14(glyph, offset.*);
        const y_scale = try readF2Dot14(glyph, offset.* + 2);
        offset.* += CompositeGlyph.xy_scale_size;
        transform.xx = x_scale;
        transform.yy = y_scale;
    } else if ((flags & CompositeGlyphFlag.has_2x2) != 0) {
        if (offset.* + CompositeGlyph.matrix_2x2_size > glyph.len) return font_parser.ParserError.InvalidTable;
        const xx = try readF2Dot14(glyph, offset.*);
        const yx = try readF2Dot14(glyph, offset.* + 2);
        const xy = try readF2Dot14(glyph, offset.* + 4);
        const yy = try readF2Dot14(glyph, offset.* + 6);
        offset.* += CompositeGlyph.matrix_2x2_size;
        transform.xx = xx;
        transform.yx = yx;
        transform.xy = xy;
        transform.yy = yy;
    }

    return transform;
}

fn appendContourPath(writer: *std.Io.Writer, contour: []const Point, transform: Transform) !void {
    if (contour.len == 0) return;

    const first = contour[0];
    const first_transformed = transform.apply(first.x, first.y);
    try writer.print("M {d:.2} {d:.2} ", .{ first_transformed.x, first_transformed.y });

    var index: usize = 1;
    while (index < contour.len) : (index += 1) {
        const current = contour[index];
        if (current.on_curve) {
            const transformed = transform.apply(current.x, current.y);
            try writer.print("L {d:.2} {d:.2} ", .{ transformed.x, transformed.y });
        } else {
            const next = contour[(index + 1) % contour.len];
            if (next.on_curve) {
                const current_transformed = transform.apply(current.x, current.y);
                const next_transformed = transform.apply(next.x, next.y);
                try writer.print("Q {d:.2} {d:.2} {d:.2} {d:.2} ", .{ current_transformed.x, current_transformed.y, next_transformed.x, next_transformed.y });
                if (index + 1 < contour.len) index += 1;
            } else {
                const mid_x = midpoint(current.x, next.x);
                const mid_y = midpoint(current.y, next.y);
                const current_transformed = transform.apply(current.x, current.y);
                const mid_transformed = transform.apply(mid_x, mid_y);
                try writer.print("Q {d:.2} {d:.2} {d:.2} {d:.2} ", .{ current_transformed.x, current_transformed.y, mid_transformed.x, mid_transformed.y });
            }
        }
    }

    try writer.print("Z ", .{});
}

fn glyphRange(face: font_parser.Face, glyph_id: u16) SvgGlyphError!GlyphRange {
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

test "glyph transform includes vertical shaping offset" {
    const face = font_parser.Face{
        .data = &[_]u8{},
        .units_per_em = test_units_per_em,
        .num_glyphs = 1,
        .tables = &[_]font_parser.TableMetadata{},
        .number_of_h_metrics = 1,
        .number_of_v_metrics = null,
        .vorg_default_vert_origin_y = null,
        .vorg = null,
        .cmap = null,
    };
    const transform = try glyphTransform(face, .{
        .codepoint = 'A',
        .glyph_id = 1,
        .cluster = 0,
        .x_offset = 12,
        .y_offset = 34,
        .x_advance = 100,
        .y_advance = 0,
        .advance_width = 100,
        .lsb = 0,
        .kern_adjustment = 0,
    }, .ltr);
    const point = transform.apply(10, 20);
    try std.testing.expectEqual(@as(f64, 22.0), point.x);
    try std.testing.expectEqual(@as(f64, 54.0), point.y);
}

test "glyph transform applies vertical origin from VORG" {
    const data = [_]u8{
        0x00, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x07,
        0x00, 0x07,
    };
    const tables = [_]font_parser.TableMetadata{.{
        .tag = "VORG".*,
        .offset = 0,
        .length = test_vorg_data_length,
    }};
    const face = font_parser.Face{
        .data = &data,
        .units_per_em = test_units_per_em,
        .num_glyphs = 8,
        .tables = &tables,
        .number_of_h_metrics = 1,
        .number_of_v_metrics = null,
        .vorg_default_vert_origin_y = test_vorg_default_origin_y,
        .vorg = tables[0],
        .cmap = null,
    };
    const transform = try glyphTransform(face, .{
        .codepoint = 'A',
        .glyph_id = test_vorg_glyph_id,
        .cluster = 0,
        .x_offset = 0,
        .y_offset = test_vertical_origin_y,
        .x_advance = 100,
        .y_advance = 0,
        .advance_width = 100,
        .lsb = 0,
        .kern_adjustment = 0,
    }, .ttb);
    const point = transform.apply(0, 0);
    try std.testing.expectEqual(@as(f64, 0.0), point.x);
    try std.testing.expectEqual(@as(f64, test_vertical_origin_result_y), point.y);
}

test "CFF2 outline path emits through charstring renderer" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const writer = &output.writer;
    const data = [_]u8{
        2,   0,   5,   0,   2,
        150, 17,  0,   0,   0,
        0,   0,   0,   0,   1,
        1,   1,   7,   139, 139,
        21,  189, 139, 5,
    };
    const tables = [_]font_parser.TableMetadata{.{
        .tag = TableTags.cff2,
        .offset = 0,
        .length = data.len,
    }};
    const face = font_parser.Face{
        .data = &data,
        .units_per_em = test_units_per_em,
        .num_glyphs = 1,
        .tables = &tables,
        .number_of_h_metrics = 1,
        .number_of_v_metrics = null,
        .vorg_default_vert_origin_y = null,
        .vorg = null,
        .cmap = null,
    };

    try appendGlyphPath(std.testing.allocator, writer, face, 0, Transform{}, 0, &.{});
    try std.testing.expectEqualStrings("    <path d=\"M 0.00 0.00 L 50.00 0.00 Z \"/>\n", output.written());
}

test "composite glyph parser rejects point-matched first component" {
    const allocator = std.testing.allocator;
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    const face: font_parser.Face = undefined;
    const glyph = [_]u8{
        0xff, 0xff, 0, 0, 0, 0, 0, 0, 0, 0,
        0,    0,    0, 1, 0, 0, 0, 0,
    };

    try std.testing.expectError(
        font_parser.ParserError.InvalidTable,
        appendCompositeGlyphPaths(allocator, writer, face, &glyph, Transform{}, 0, &.{}),
    );
}

test "composite glyph parser aligns point-matched components" {
    const allocator = std.testing.allocator;
    var data = [_]u8{0} ** test_composite_fixture_length;
    data[test_head_index_to_loc_offset] = 0;
    data[test_head_index_to_loc_offset + 1] = 0;
    data[test_loca_table_offset] = 0;
    data[test_loca_table_offset + 1] = 0;
    data[test_loca_table_offset + 2] = 0;
    data[test_loca_table_offset + 3] = 8;
    data[test_loca_table_offset + 4] = 0;
    data[test_loca_table_offset + 5] = 16;

    const glyph0_offset = test_composite_glyf_offset;
    data[glyph0_offset + 1] = 1;
    data[glyph0_offset + 10] = 0;
    data[glyph0_offset + 11] = 0;
    data[glyph0_offset + 12] = 0;
    data[glyph0_offset + 13] = 0;
    data[glyph0_offset + 14] = SimpleGlyphFlag.on_curve | SimpleGlyphFlag.x_is_same_or_positive_short | SimpleGlyphFlag.y_is_same_or_positive_short;

    const glyph1_offset = test_simple_component_offset;
    data[glyph1_offset + 1] = 1;
    data[glyph1_offset + 10] = 0;
    data[glyph1_offset + 11] = 0;
    data[glyph1_offset + 12] = 0;
    data[glyph1_offset + 13] = 0;
    data[glyph1_offset + 14] = SimpleGlyphFlag.on_curve | SimpleGlyphFlag.x_short_vector | SimpleGlyphFlag.x_is_same_or_positive_short | SimpleGlyphFlag.y_is_same_or_positive_short;
    data[glyph1_offset + 15] = 10;

    const tables = [_]font_parser.TableMetadata{
        .{ .tag = TableTags.head, .offset = 0, .length = 52 },
        .{ .tag = TableTags.loca, .offset = test_loca_table_offset, .length = test_loca_table_length },
        .{ .tag = TableTags.glyf, .offset = test_composite_glyf_offset, .length = 32 },
    };
    const face = font_parser.Face{
        .data = &data,
        .units_per_em = test_units_per_em,
        .num_glyphs = test_composite_glyph_count,
        .tables = &tables,
        .number_of_h_metrics = 1,
        .number_of_v_metrics = null,
        .vorg_default_vert_origin_y = null,
        .vorg = null,
        .cmap = null,
    };

    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    const glyph = [_]u8{
        0xff, 0xff, 0, 0, 0,  0,  0, 0, 0, 0,
        0,    0x22, 0, 0, 20, 30, 0, 0, 0, 1,
        0,    0,
    };

    try appendCompositeGlyphPaths(allocator, writer, face, &glyph, Transform{}, 0, &.{});
    try std.testing.expectEqual(@as(usize, test_composite_point_match_count), std.mem.count(u8, output.written(), "M 20.00 30.00"));
}
