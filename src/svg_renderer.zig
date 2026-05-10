const std = @import("std");
const font_parser = @import("font_parser.zig");
const shaper = @import("shaper.zig");

pub const SvgError = font_parser.ParserError || shaper.ShapeError || std.mem.Allocator.Error || error{
    InvalidSvgColor,
    UnsupportedCffOperator,
    UnsupportedCffOutlines,
    UnsupportedCompositeGlyph,
    MissingText,
};

const max_composite_depth = 8;
const default_font_size_px = 64.0;
const default_margin_px = 8.0;

const TableTags = struct {
    const cff = "CFF ".*;
    const cff2 = "CFF2".*;
    const glyf = "glyf".*;
    const head = "head".*;
    const loca = "loca".*;
};

const Cff = struct {
    const header_min_size = 4;
    const header_size_offset = 2;
    const index_count_size = 2;
    const index_off_size_offset = 2;
    const top_dict_charstrings_operator = 17;
    const top_dict_private_operator = 18;
    const private_subrs_operator = 19;
    const operand_stack_max = 48;
    const max_subr_depth = 16;
};

const Type2 = struct {
    const hstem = 1;
    const vstem = 3;
    const vmoveto = 4;
    const rlineto = 5;
    const hlineto = 6;
    const vlineto = 7;
    const rrcurveto = 8;
    const callsubr = 10;
    const return_op = 11;
    const escape = 12;
    const endchar = 14;
    const hstemhm = 18;
    const hintmask = 19;
    const cntrmask = 20;
    const rmoveto = 21;
    const hmoveto = 22;
    const vstemhm = 23;
    const rcurveline = 24;
    const rlinecurve = 25;
    const vvcurveto = 26;
    const hhcurveto = 27;
    const callgsubr = 29;
    const vhcurveto = 30;
    const hvcurveto = 31;
};

const CffIndex = struct {
    data: []const u8,
    count: u16,
    off_size: u8,
    offsets_offset: usize,
    object_data_offset: usize,
    end_offset: usize,
};

const CffContext = struct {
    cff: []const u8,
    charstrings: CffIndex,
    global_subrs: CffIndex,
    local_subrs: ?CffIndex,
};

const TopDictInfo = struct {
    charstrings_offset: ?usize = null,
    private_size: ?usize = null,
    private_offset: ?usize = null,
};

const Type2State = struct {
    stack: [Cff.operand_stack_max]i32 = undefined,
    stack_len: usize = 0,
    x: i32 = 0,
    y: i32 = 0,
    has_current_point: bool = false,
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
    const f2dot14_one = 0x4000;
};

pub const RenderOptions = struct {
    font_size_px: f64 = default_font_size_px,
    margin_px: f64 = default_margin_px,
    fill: []const u8 = "black",
    background: ?[]const u8 = null,
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

const Transform = struct {
    xx: f64 = 1.0,
    yx: f64 = 0.0,
    xy: f64 = 0.0,
    yy: f64 = 1.0,
    dx: f64 = 0.0,
    dy: f64 = 0.0,

    fn translate(x: i32, y: i32) Transform {
        return .{ .dx = @floatFromInt(x), .dy = @floatFromInt(y) };
    }

    fn compose(self: Transform, inner: Transform) Transform {
        return .{
            .xx = self.xx * inner.xx + self.xy * inner.yx,
            .xy = self.xx * inner.xy + self.xy * inner.yy,
            .yx = self.yx * inner.xx + self.yy * inner.yx,
            .yy = self.yx * inner.xy + self.yy * inner.yy,
            .dx = self.xx * inner.dx + self.xy * inner.dy + self.dx,
            .dy = self.yx * inner.dx + self.yy * inner.dy + self.dy,
        };
    }

    fn apply(self: Transform, x: i32, y: i32) TransformedPoint {
        const fx: f64 = @floatFromInt(x);
        const fy: f64 = @floatFromInt(y);
        return .{
            .x = self.xx * fx + self.xy * fy + self.dx,
            .y = self.yx * fx + self.yy * fy + self.dy,
        };
    }
};

const TransformedPoint = struct {
    x: f64,
    y: f64,
};

const Bounds = struct {
    min_x: i32,
    min_y: i32,
    max_x: i32,
    max_y: i32,

    fn width(self: Bounds) i32 {
        return @max(1, self.max_x - self.min_x);
    }

    fn height(self: Bounds) i32 {
        return @max(1, self.max_y - self.min_y);
    }

    fn include(self: *Bounds, other: Bounds) void {
        self.min_x = @min(self.min_x, other.min_x);
        self.min_y = @min(self.min_y, other.min_y);
        self.max_x = @max(self.max_x, other.max_x);
        self.max_y = @max(self.max_y, other.max_y);
    }
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

        const bounds = try textBounds(face, shaped);
        const scale = options.font_size_px / @as(f64, @floatFromInt(face.units_per_em));
        const width_px = @as(f64, @floatFromInt(bounds.width())) * scale + options.margin_px * 2.0;
        const height_px = @as(f64, @floatFromInt(bounds.height())) * scale + options.margin_px * 2.0;
        const translate_x = options.margin_px - @as(f64, @floatFromInt(bounds.min_x)) * scale;
        const translate_y = options.margin_px + @as(f64, @floatFromInt(bounds.max_y)) * scale;
        try validateSvgColor(options.fill);
        if (options.background) |background| try validateSvgColor(background);

        var output = std.ArrayList(u8).empty;
        errdefer output.deinit(allocator);
        const writer = output.writer(allocator);

        try writer.print(
            \\<svg xmlns="http://www.w3.org/2000/svg" width="{d:.2}" height="{d:.2}" viewBox="0 0 {d:.2} {d:.2}">
            \\
        , .{
            width_px,
            height_px,
            width_px,
            height_px,
        });

        if (options.background) |background| {
            try writer.print("  <rect width=\"100%\" height=\"100%\" fill=\"{s}\"/>\n", .{background});
        }

        try writer.print(
            \\  <g fill="{s}" transform="translate({d:.2} {d:.2}) scale({d:.6} {d:.6})">
            \\
        , .{
            options.fill,
            translate_x,
            translate_y,
            scale,
            -scale,
        });

        for (shaped.glyphs) |glyph| {
            try appendGlyphPath(allocator, writer, face, glyph.glyph_id, Transform.translate(glyph.x_offset, 0), 0);
        }

        try writer.print(
            \\  </g>
            \\</svg>
            \\
        , .{});

        return try output.toOwnedSlice(allocator);
    }
};

fn validateSvgColor(value: []const u8) SvgError!void {
    if (value.len == 0) return SvgError.InvalidSvgColor;
    for (value) |char| {
        const valid = std.ascii.isAlphanumeric(char) or char == '#' or char == '-' or char == '_' or char == '(' or char == ')' or char == ',' or char == '.' or char == '%' or char == ' ';
        if (!valid) return SvgError.InvalidSvgColor;
    }
}

fn textBounds(face: font_parser.Face, shaped: shaper.ShapedText) SvgError!Bounds {
    var maybe_bounds: ?Bounds = null;

    for (shaped.glyphs) |glyph| {
        const bounds = (try glyphBounds(face, glyph.glyph_id)) orelse continue;
        const positioned: Bounds = .{
            .min_x = bounds.min_x + glyph.x_offset,
            .min_y = bounds.min_y + glyph.y_offset,
            .max_x = bounds.max_x + glyph.x_offset,
            .max_y = bounds.max_y + glyph.y_offset,
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
    bounds.max_x = @max(bounds.max_x, shaped.total_advance);
    return bounds;
}

fn glyphBounds(face: font_parser.Face, glyph_id: u16) SvgError!?Bounds {
    if (face.getTable(TableTags.glyf) == null and face.getTable(TableTags.cff) != null) {
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

fn appendGlyphPath(
    allocator: std.mem.Allocator,
    writer: std.ArrayList(u8).Writer,
    face: font_parser.Face,
    glyph_id: u16,
    transform: Transform,
    depth: u8,
) SvgError!void {
    if (depth > max_composite_depth) return SvgError.UnsupportedCompositeGlyph;

    if (face.getTable(TableTags.glyf) == null) {
        if (face.getTable(TableTags.cff)) |cff| {
            return appendCffGlyphPath(writer, cff, glyph_id, transform);
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
        return appendCompositeGlyphPaths(allocator, writer, face, glyph, transform, depth + 1);
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
        try appendContourPath(writer, points[contour_start .. contour_end + 1], transform);
        contour_start = contour_end + 1;
    }
    try writer.print("\"/>\n", .{});
}

fn appendCompositeGlyphPaths(
    allocator: std.mem.Allocator,
    writer: std.ArrayList(u8).Writer,
    face: font_parser.Face,
    glyph: []const u8,
    transform: Transform,
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

        var component_transform = Transform.translate(component_x, component_y);
        if ((flags & CompositeGlyphFlag.has_scale) != 0) {
            if (offset + CompositeGlyph.scale_size > glyph.len) return font_parser.ParserError.InvalidTable;
            const scale = try readF2Dot14(glyph, offset);
            offset += CompositeGlyph.scale_size;
            component_transform.xx = scale;
            component_transform.yy = scale;
        } else if ((flags & CompositeGlyphFlag.has_xy_scale) != 0) {
            if (offset + CompositeGlyph.xy_scale_size > glyph.len) return font_parser.ParserError.InvalidTable;
            const x_scale = try readF2Dot14(glyph, offset);
            const y_scale = try readF2Dot14(glyph, offset + 2);
            offset += CompositeGlyph.xy_scale_size;
            component_transform.xx = x_scale;
            component_transform.yy = y_scale;
        } else if ((flags & CompositeGlyphFlag.has_2x2) != 0) {
            if (offset + CompositeGlyph.matrix_2x2_size > glyph.len) return font_parser.ParserError.InvalidTable;
            const xx = try readF2Dot14(glyph, offset);
            const yx = try readF2Dot14(glyph, offset + 2);
            const xy = try readF2Dot14(glyph, offset + 4);
            const yy = try readF2Dot14(glyph, offset + 6);
            offset += CompositeGlyph.matrix_2x2_size;
            component_transform.xx = xx;
            component_transform.yx = yx;
            component_transform.xy = xy;
            component_transform.yy = yy;
        }

        try appendGlyphPath(
            allocator,
            writer,
            face,
            component_glyph_id,
            transform.compose(component_transform),
            depth,
        );

        more_components = (flags & CompositeGlyphFlag.more_components) != 0;
    }

    if (offset > glyph.len) return font_parser.ParserError.InvalidTable;
}

fn appendContourPath(writer: std.ArrayList(u8).Writer, contour: []const Point, transform: Transform) !void {
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

fn appendCffGlyphPath(writer: std.ArrayList(u8).Writer, cff: []const u8, glyph_id: u16, transform: Transform) SvgError!void {
    const context = try parseCffContext(cff);
    const charstring = try getCffCharString(context, glyph_id);
    if (charstring.len == 0) return;

    try writer.print("    <path d=\"", .{});
    try appendType2CharStringPath(writer, charstring, transform, context);
    try writer.print("\"/>\n", .{});
}

fn getCffCharString(context: CffContext, glyph_id: u16) SvgError![]const u8 {
    return getCffIndexObject(context.charstrings, glyph_id);
}

fn parseCffContext(cff: []const u8) SvgError!CffContext {
    if (cff.len < Cff.header_min_size) return font_parser.ParserError.InvalidTable;
    const header_size = cff[Cff.header_size_offset];
    if (header_size > cff.len) return font_parser.ParserError.InvalidTable;

    var offset: usize = header_size;
    const name_index = try readCffIndex(cff[offset..]);
    offset += name_index.end_offset;
    const top_dict_index = try readCffIndex(cff[offset..]);
    offset += top_dict_index.end_offset;
    const string_index = try readCffIndex(cff[offset..]);
    offset += string_index.end_offset;
    const global_subr_index = try readCffIndex(cff[offset..]);

    const top_dict = try getCffIndexObject(top_dict_index, 0);
    const top_dict_info = try readCffTopDictInfo(top_dict);
    const charstrings_offset = top_dict_info.charstrings_offset orelse return font_parser.ParserError.MissingMandatoryTable;
    if (charstrings_offset >= cff.len) return font_parser.ParserError.InvalidTable;
    const charstrings = try readCffIndex(cff[charstrings_offset..]);

    var local_subrs: ?CffIndex = null;
    if (top_dict_info.private_size) |private_size| {
        const private_offset = top_dict_info.private_offset orelse return font_parser.ParserError.InvalidTable;
        if (private_offset + private_size > cff.len) return font_parser.ParserError.InvalidTable;
        const private_dict = cff[private_offset .. private_offset + private_size];
        if (try readCffPrivateSubrsOffset(private_dict)) |subrs_offset| {
            const absolute_subrs_offset = private_offset + subrs_offset;
            if (absolute_subrs_offset >= cff.len) return font_parser.ParserError.InvalidTable;
            local_subrs = try readCffIndex(cff[absolute_subrs_offset..]);
        }
    }

    return .{
        .cff = cff,
        .charstrings = charstrings,
        .global_subrs = global_subr_index,
        .local_subrs = local_subrs,
    };
}

fn readCffTopDictInfo(dict: []const u8) SvgError!TopDictInfo {
    var result = TopDictInfo{};
    var stack: [Cff.operand_stack_max]i32 = undefined;
    var stack_len: usize = 0;
    var offset: usize = 0;
    while (offset < dict.len) {
        const byte = dict[offset];
        if (isCffDictOperator(byte)) {
            offset += 1;
            if (byte == 12) {
                if (offset >= dict.len) return font_parser.ParserError.InvalidTable;
                offset += 1;
                stack_len = 0;
                continue;
            }
            if (byte == Cff.top_dict_charstrings_operator) {
                if (stack_len == 0) return font_parser.ParserError.InvalidTable;
                const value = stack[stack_len - 1];
                if (value < 0) return font_parser.ParserError.InvalidTable;
                result.charstrings_offset = @intCast(value);
            } else if (byte == Cff.top_dict_private_operator) {
                if (stack_len < 2) return font_parser.ParserError.InvalidTable;
                const private_size = stack[stack_len - 2];
                const private_offset = stack[stack_len - 1];
                if (private_size < 0 or private_offset < 0) return font_parser.ParserError.InvalidTable;
                result.private_size = @intCast(private_size);
                result.private_offset = @intCast(private_offset);
            }
            stack_len = 0;
            continue;
        }

        const operand = try readCffDictOperand(dict, &offset);
        if (stack_len >= stack.len) return font_parser.ParserError.InvalidTable;
        stack[stack_len] = operand;
        stack_len += 1;
    }
    return result;
}

fn readCffPrivateSubrsOffset(dict: []const u8) SvgError!?usize {
    var stack: [Cff.operand_stack_max]i32 = undefined;
    var stack_len: usize = 0;
    var offset: usize = 0;
    while (offset < dict.len) {
        const byte = dict[offset];
        if (isCffDictOperator(byte)) {
            offset += 1;
            if (byte == 12) {
                if (offset >= dict.len) return font_parser.ParserError.InvalidTable;
                offset += 1;
                stack_len = 0;
                continue;
            }
            if (byte == Cff.private_subrs_operator) {
                if (stack_len == 0) return font_parser.ParserError.InvalidTable;
                const value = stack[stack_len - 1];
                if (value < 0) return font_parser.ParserError.InvalidTable;
                return @intCast(value);
            }
            stack_len = 0;
            continue;
        }

        const operand = try readCffDictOperand(dict, &offset);
        if (stack_len >= stack.len) return font_parser.ParserError.InvalidTable;
        stack[stack_len] = operand;
        stack_len += 1;
    }
    return null;
}

fn appendType2CharStringPath(writer: std.ArrayList(u8).Writer, charstring: []const u8, transform: Transform, context: CffContext) SvgError!void {
    var state = Type2State{};
    try executeType2CharString(writer, charstring, transform, context, &state, 0);
}

fn executeType2CharString(writer: std.ArrayList(u8).Writer, charstring: []const u8, transform: Transform, context: CffContext, state: *Type2State, depth: u8) SvgError!void {
    if (depth > Cff.max_subr_depth) return SvgError.UnsupportedCffOperator;
    var offset: usize = 0;

    while (offset < charstring.len) {
        const byte = charstring[offset];
        if (isType2Number(byte)) {
            const number = try readType2Number(charstring, &offset);
            if (state.stack_len >= state.stack.len) return font_parser.ParserError.InvalidTable;
            state.stack[state.stack_len] = number;
            state.stack_len += 1;
            continue;
        }

        offset += 1;
        switch (byte) {
            Type2.hstem, Type2.vstem, Type2.hstemhm, Type2.vstemhm => state.stack_len = 0,
            Type2.rmoveto => {
                if (state.stack_len < 2) return font_parser.ParserError.InvalidTable;
                state.x += state.stack[state.stack_len - 2];
                state.y += state.stack[state.stack_len - 1];
                const point = transform.apply(state.x, state.y);
                try writer.print("M {d:.2} {d:.2} ", .{ point.x, point.y });
                state.has_current_point = true;
                state.stack_len = 0;
            },
            Type2.hmoveto => {
                if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
                state.x += state.stack[state.stack_len - 1];
                const point = transform.apply(state.x, state.y);
                try writer.print("M {d:.2} {d:.2} ", .{ point.x, point.y });
                state.has_current_point = true;
                state.stack_len = 0;
            },
            Type2.vmoveto => {
                if (state.stack_len < 1) return font_parser.ParserError.InvalidTable;
                state.y += state.stack[state.stack_len - 1];
                const point = transform.apply(state.x, state.y);
                try writer.print("M {d:.2} {d:.2} ", .{ point.x, point.y });
                state.has_current_point = true;
                state.stack_len = 0;
            },
            Type2.rlineto => {
                if (!state.has_current_point or state.stack_len < 2 or (state.stack_len % 2) != 0) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                while (index < state.stack_len) : (index += 2) {
                    state.x += state.stack[index];
                    state.y += state.stack[index + 1];
                    const point = transform.apply(state.x, state.y);
                    try writer.print("L {d:.2} {d:.2} ", .{ point.x, point.y });
                }
                state.stack_len = 0;
            },
            Type2.hlineto, Type2.vlineto => {
                if (!state.has_current_point or state.stack_len == 0) return font_parser.ParserError.InvalidTable;
                var horizontal = byte == Type2.hlineto;
                for (state.stack[0..state.stack_len]) |value| {
                    if (horizontal) state.x += value else state.y += value;
                    const point = transform.apply(state.x, state.y);
                    try writer.print("L {d:.2} {d:.2} ", .{ point.x, point.y });
                    horizontal = !horizontal;
                }
                state.stack_len = 0;
            },
            Type2.rrcurveto => {
                if (!state.has_current_point or state.stack_len < 6 or (state.stack_len % 6) != 0) return font_parser.ParserError.InvalidTable;
                var index: usize = 0;
                while (index < state.stack_len) : (index += 6) {
                    const c1x = state.x + state.stack[index];
                    const c1y = state.y + state.stack[index + 1];
                    const c2x = c1x + state.stack[index + 2];
                    const c2y = c1y + state.stack[index + 3];
                    state.x = c2x + state.stack[index + 4];
                    state.y = c2y + state.stack[index + 5];
                    const c1 = transform.apply(c1x, c1y);
                    const c2 = transform.apply(c2x, c2y);
                    const end = transform.apply(state.x, state.y);
                    try writer.print("C {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} ", .{ c1.x, c1.y, c2.x, c2.y, end.x, end.y });
                }
                state.stack_len = 0;
            },
            Type2.callsubr => try executeCffSubroutine(writer, transform, context, context.local_subrs, state, depth + 1),
            Type2.callgsubr => try executeCffSubroutine(writer, transform, context, context.global_subrs, state, depth + 1),
            Type2.return_op => return,
            Type2.endchar => {
                try writer.print("Z ", .{});
                return;
            },
            Type2.escape, Type2.hintmask, Type2.cntrmask, Type2.rcurveline, Type2.rlinecurve, Type2.vvcurveto, Type2.hhcurveto, Type2.vhcurveto, Type2.hvcurveto => return SvgError.UnsupportedCffOperator,
            else => return SvgError.UnsupportedCffOperator,
        }
    }
}

fn executeCffSubroutine(writer: std.ArrayList(u8).Writer, transform: Transform, context: CffContext, maybe_subrs: ?CffIndex, state: *Type2State, depth: u8) SvgError!void {
    const subrs = maybe_subrs orelse return SvgError.UnsupportedCffOperator;
    if (state.stack_len == 0) return font_parser.ParserError.InvalidTable;
    const raw_index = state.stack[state.stack_len - 1];
    state.stack_len -= 1;
    const biased_index = raw_index + cffSubrBias(subrs.count);
    if (biased_index < 0 or biased_index > std.math.maxInt(u16)) return font_parser.ParserError.InvalidTable;
    const subr = try getCffIndexObject(subrs, @intCast(biased_index));
    try executeType2CharString(writer, subr, transform, context, state, depth);
}

fn cffSubrBias(count: u16) i32 {
    if (count < 1240) return 107;
    if (count < 33900) return 1131;
    return 32768;
}

fn glyphRange(face: font_parser.Face, glyph_id: u16) SvgError!GlyphRange {
    if (glyph_id >= face.num_glyphs) return font_parser.ParserError.InvalidGlyphId;
    if (face.getTable(TableTags.glyf) == null and face.getTable(TableTags.cff2) != null) {
        return SvgError.UnsupportedCffOutlines;
    }

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

fn readF2Dot14(data: []const u8, offset: usize) font_parser.ParserError!f64 {
    const raw = try readI16(data, offset);
    return @as(f64, @floatFromInt(raw)) / @as(f64, @floatFromInt(CompositeGlyph.f2dot14_one));
}

fn readCffIndex(data: []const u8) font_parser.ParserError!CffIndex {
    if (data.len < Cff.index_count_size) return font_parser.ParserError.InvalidTable;
    const count = try readU16(data, 0);
    if (count == 0) {
        return .{
            .data = data,
            .count = 0,
            .off_size = 0,
            .offsets_offset = Cff.index_count_size,
            .object_data_offset = Cff.index_count_size,
            .end_offset = Cff.index_count_size,
        };
    }

    if (data.len < Cff.index_count_size + 1) return font_parser.ParserError.InvalidTable;
    const off_size = data[Cff.index_off_size_offset];
    if (off_size == 0 or off_size > 4) return font_parser.ParserError.InvalidTable;
    const offsets_offset = Cff.index_count_size + 1;
    const object_data_offset = offsets_offset + (@as(usize, count) + 1) * @as(usize, off_size);
    if (object_data_offset > data.len) return font_parser.ParserError.InvalidTable;

    const last_offset = try readCffOffset(data, offsets_offset + @as(usize, count) * @as(usize, off_size), off_size);
    if (last_offset == 0) return font_parser.ParserError.InvalidTable;
    const end_offset = object_data_offset + @as(usize, last_offset) - 1;
    if (end_offset > data.len) return font_parser.ParserError.InvalidTable;

    return .{
        .data = data,
        .count = count,
        .off_size = off_size,
        .offsets_offset = offsets_offset,
        .object_data_offset = object_data_offset,
        .end_offset = end_offset,
    };
}

fn getCffIndexObject(index: CffIndex, object_index: u16) font_parser.ParserError![]const u8 {
    if (object_index >= index.count) return font_parser.ParserError.InvalidGlyphId;
    const offset_size = @as(usize, index.off_size);
    const start_offset = try readCffOffset(index.data, index.offsets_offset + @as(usize, object_index) * offset_size, index.off_size);
    const end_offset = try readCffOffset(index.data, index.offsets_offset + (@as(usize, object_index) + 1) * offset_size, index.off_size);
    if (start_offset == 0 or end_offset < start_offset) return font_parser.ParserError.InvalidTable;
    const start = index.object_data_offset + @as(usize, start_offset) - 1;
    const end = index.object_data_offset + @as(usize, end_offset) - 1;
    if (end > index.data.len or start > end) return font_parser.ParserError.InvalidTable;
    return index.data[start..end];
}

fn readCffOffset(data: []const u8, offset: usize, off_size: u8) font_parser.ParserError!u32 {
    if (off_size == 0 or off_size > 4 or offset + off_size > data.len) return font_parser.ParserError.InvalidTable;
    var value: u32 = 0;
    for (data[offset .. offset + off_size]) |byte| {
        value = (value << 8) | byte;
    }
    return value;
}

fn isCffDictOperator(byte: u8) bool {
    return byte <= 21;
}

fn readCffDictOperand(data: []const u8, offset: *usize) font_parser.ParserError!i32 {
    if (offset.* >= data.len) return font_parser.ParserError.InvalidTable;
    const byte = data[offset.*];
    offset.* += 1;
    return switch (byte) {
        32...246 => @as(i32, byte) - 139,
        247...250 => blk: {
            if (offset.* >= data.len) return font_parser.ParserError.InvalidTable;
            const b1 = data[offset.*];
            offset.* += 1;
            break :blk (@as(i32, byte) - 247) * 256 + @as(i32, b1) + 108;
        },
        251...254 => blk: {
            if (offset.* >= data.len) return font_parser.ParserError.InvalidTable;
            const b1 = data[offset.*];
            offset.* += 1;
            break :blk -((@as(i32, byte) - 251) * 256) - @as(i32, b1) - 108;
        },
        28 => blk: {
            const value = try readI16(data, offset.*);
            offset.* += 2;
            break :blk value;
        },
        29 => blk: {
            const value = try readI32(data, offset.*);
            offset.* += 4;
            break :blk value;
        },
        30 => blk: {
            try skipCffReal(data, offset);
            break :blk 0;
        },
        else => font_parser.ParserError.InvalidTable,
    };
}

fn skipCffReal(data: []const u8, offset: *usize) font_parser.ParserError!void {
    while (offset.* < data.len) {
        const byte = data[offset.*];
        offset.* += 1;
        if ((byte & 0x0f) == 0x0f or (byte >> 4) == 0x0f) return;
    }
    return font_parser.ParserError.InvalidTable;
}

fn isType2Number(byte: u8) bool {
    return byte == 28 or byte >= 32;
}

fn readType2Number(data: []const u8, offset: *usize) font_parser.ParserError!i32 {
    return readCffDictOperand(data, offset);
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

fn readI32(data: []const u8, offset: usize) font_parser.ParserError!i32 {
    if (offset + 4 > data.len) return font_parser.ParserError.InvalidTable;
    return std.mem.readInt(i32, data[offset..][0..4], .big);
}

test "midpoint uses integer midpoint" {
    try std.testing.expectEqual(@as(i32, 15), midpoint(10, 20));
    try std.testing.expectEqual(@as(i32, -5), midpoint(-10, 0));
}

test "transform compose applies nested composite placement" {
    const parent = Transform.translate(10, 20);
    const child = Transform{ .xx = 0.5, .yy = 0.5, .dx = 4, .dy = 6 };
    const point = parent.compose(child).apply(100, 200);
    try std.testing.expectEqual(@as(f64, 64.0), point.x);
    try std.testing.expectEqual(@as(f64, 126.0), point.y);
}

test "read F2Dot14 scale values" {
    const one = [_]u8{ 0x40, 0x00 };
    const half = [_]u8{ 0x20, 0x00 };
    try std.testing.expectEqual(@as(f64, 1.0), try readF2Dot14(&one, 0));
    try std.testing.expectEqual(@as(f64, 0.5), try readF2Dot14(&half, 0));
}

test "CFF2 outlines return explicit unsupported error" {
    const data = [_]u8{};
    const tables = [_]font_parser.TableMetadata{.{
        .tag = TableTags.cff2,
        .offset = 0,
        .length = 0,
    }};
    const face = font_parser.Face{
        .data = &data,
        .units_per_em = 1000,
        .num_glyphs = 1,
        .tables = &tables,
        .number_of_h_metrics = 1,
        .cmap = null,
    };

    try std.testing.expectError(SvgError.UnsupportedCffOutlines, glyphRange(face, 0));
}

test "CFF INDEX reads object slices" {
    const data = [_]u8{
        0,   2,   1,
        1,   3,   4,
        'A', 'B', 'C',
    };
    const index = try readCffIndex(&data);
    try std.testing.expectEqual(@as(u16, 2), index.count);
    try std.testing.expectEqualSlices(u8, "AB", try getCffIndexObject(index, 0));
    try std.testing.expectEqualSlices(u8, "C", try getCffIndexObject(index, 1));
}

test "CFF subroutine bias follows Type 2 thresholds" {
    try std.testing.expectEqual(@as(i32, 107), cffSubrBias(0));
    try std.testing.expectEqual(@as(i32, 107), cffSubrBias(1239));
    try std.testing.expectEqual(@as(i32, 1131), cffSubrBias(1240));
    try std.testing.expectEqual(@as(i32, 32768), cffSubrBias(33900));
}

test "Type2 charstring emits moveto and lines" {
    var output = std.ArrayList(u8).empty;
    defer output.deinit(std.testing.allocator);
    const writer = output.writer(std.testing.allocator);
    const empty_index = try readCffIndex(&[_]u8{ 0, 0 });
    const context = CffContext{
        .cff = &[_]u8{},
        .charstrings = empty_index,
        .global_subrs = empty_index,
        .local_subrs = null,
    };
    const charstring = [_]u8{
        139,           139,           Type2.rmoveto,
        189,           139,           139,
        189,           89,            139,
        Type2.rlineto, Type2.endchar,
    };

    try appendType2CharStringPath(writer, &charstring, Transform{}, context);
    try std.testing.expectEqualStrings("M 0.00 0.00 L 50.00 0.00 L 50.00 50.00 L 0.00 50.00 Z ", output.items);
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
        appendCompositeGlyphPaths(allocator, writer, face, &glyph, Transform{}, 0),
    );
}

test "svg color validation rejects attribute-breaking characters" {
    try std.testing.expectError(SvgError.InvalidSvgColor, validateSvgColor("\"red\""));
    try validateSvgColor("#1d4ed8");
    try validateSvgColor("rgb(10, 20, 30)");
}
