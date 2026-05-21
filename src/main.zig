const std = @import("std");
const zfr = @import("zig_font_renderer");

const CliError = error{
    ConflictingVariationOptions,
    InvalidFaceIndex,
    InvalidFontSize,
    InvalidMargin,
    InvalidVariationCoord,
    InvalidVariationInstanceIndex,
    MissingFontPath,
    MissingOptionValue,
    TooManyArguments,
    UnknownOption,
};

const default_font_size_px = 64.0;
const default_margin_px = 8.0;
const max_cli_variation_coords = 8;
const variation_tag_len = 4;

const CliOptions = struct {
    font_path: []const u8,
    text: ?[]const u8,
    output_path: ?[]const u8,
    font_size_px: f64 = default_font_size_px,
    margin_px: f64 = default_margin_px,
    fill: []const u8 = "black",
    background: ?[]const u8 = null,
    direction: zfr.ShapeDirection = .auto,
    face_index: u32 = 0,
    variation_coords: [max_cli_variation_coords]zfr.VariationCoord = undefined,
    variation_coord_count: usize = 0,
    variation_instance_index: ?u16 = null,
    quiet: bool = false,
    help: bool = false,
};

const LoadedFace = struct {
    data: []u8,
    face: zfr.Face,

    fn deinit(self: *LoadedFace, allocator: std.mem.Allocator) void {
        self.face.deinit(allocator);
        allocator.free(self.data);
        self.* = undefined;
    }
};

const stdout_buffer_size = 4096;
const stderr_buffer_size = 256;
const max_font_file_size = 256 * 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var stdout_buffer: [stdout_buffer_size]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [stderr_buffer_size]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    var args_iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iterator.deinit();

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    while (args_iterator.next()) |arg| {
        try args.append(allocator, arg);
    }

    const options = parseArgs(args.items) catch |err| {
        try stderr.print("error: {s}\n\n", .{cliErrorMessage(err)});
        try printUsage(stderr);
        try stderr.flush();
        std.process.exit(2);
    };

    if (options.help) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }

    if (options.text) |text| {
        if (options.output_path) |output_path| {
            try writeSvg(allocator, stderr, options.font_path, text, output_path, .{
                .font_size_px = options.font_size_px,
                .margin_px = options.margin_px,
                .fill = options.fill,
                .background = options.background,
                .shape = .{ .direction = options.direction },
                .face_index = options.face_index,
                .variation_coords = options.variation_coords[0..options.variation_coord_count],
                .variation_instance_index = options.variation_instance_index,
            });
        } else {
            var loaded = try loadFaceOrExit(allocator, stderr, options.font_path, options.face_index);
            defer loaded.deinit(allocator);
            if (!options.quiet) {
                try printFaceInfo(stdout, options.font_path, loaded.face);
            }
            try printTextGlyphs(stdout, loaded.face, text, options.direction);
        }
    } else {
        var loaded = try loadFaceOrExit(allocator, stderr, options.font_path, options.face_index);
        defer loaded.deinit(allocator);
        if (!options.quiet) {
            try printFaceInfo(stdout, options.font_path, loaded.face);
        }
    }
    try stdout.flush();
}

fn loadFaceOrExit(allocator: std.mem.Allocator, stderr: *std.Io.Writer, font_path: []const u8, face_index: u32) !LoadedFace {
    const io = std.Io.Threaded.global_single_threaded.io();
    const font_data = std.Io.Dir.cwd().readFileAlloc(io, font_path, allocator, .limited(max_font_file_size)) catch |err| {
        try stderr.print("error: failed to read font file '{s}': {s}\n", .{ font_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };
    errdefer allocator.free(font_data);

    const face = zfr.Face.initFaceIndex(allocator, font_data, face_index) catch |err| {
        allocator.free(font_data);
        try stderr.print("error: failed to parse font file '{s}': {s}\n", .{ font_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };

    return .{ .data = font_data, .face = face };
}

fn parseArgs(args: []const []const u8) CliError!CliOptions {
    var font_path: ?[]const u8 = null;
    var text: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var font_size_px: f64 = default_font_size_px;
    var margin_px: f64 = default_margin_px;
    var fill: []const u8 = "black";
    var background: ?[]const u8 = null;
    var direction: zfr.ShapeDirection = .auto;
    var face_index: u32 = 0;
    var variation_coords: [max_cli_variation_coords]zfr.VariationCoord = undefined;
    var variation_coord_count: usize = 0;
    var variation_instance_index: ?u16 = null;
    var quiet = false;
    var positional_count: u8 = 0;

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return .{ .font_path = "", .text = null, .output_path = null, .help = true };
        }

        if (std.mem.eql(u8, arg, "--quiet")) {
            quiet = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--font")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            font_path = args[index];
            continue;
        }

        if (std.mem.eql(u8, arg, "--text")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            text = args[index];
            continue;
        }

        if (std.mem.eql(u8, arg, "--output")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            output_path = args[index];
            continue;
        }

        if (std.mem.eql(u8, arg, "--font-size")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            font_size_px = std.fmt.parseFloat(f64, args[index]) catch return CliError.InvalidFontSize;
            if (font_size_px <= 0 or !std.math.isFinite(font_size_px)) return CliError.InvalidFontSize;
            continue;
        }

        if (std.mem.eql(u8, arg, "--face-index")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            face_index = std.fmt.parseInt(u32, args[index], 10) catch return CliError.InvalidFaceIndex;
            continue;
        }

        if (std.mem.eql(u8, arg, "--variation")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            if (variation_instance_index != null) return CliError.ConflictingVariationOptions;
            if (variation_coord_count >= max_cli_variation_coords) return CliError.InvalidVariationCoord;
            variation_coords[variation_coord_count] = try parseVariationCoord(args[index]);
            variation_coord_count += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "--variation-instance")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            if (variation_coord_count > 0) return CliError.ConflictingVariationOptions;
            variation_instance_index = std.fmt.parseInt(u16, args[index], 10) catch return CliError.InvalidVariationInstanceIndex;
            continue;
        }

        if (std.mem.eql(u8, arg, "--margin")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            margin_px = std.fmt.parseFloat(f64, args[index]) catch return CliError.InvalidMargin;
            if (margin_px < 0 or !std.math.isFinite(margin_px)) return CliError.InvalidMargin;
            continue;
        }

        if (std.mem.eql(u8, arg, "--fill")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            fill = args[index];
            continue;
        }

        if (std.mem.eql(u8, arg, "--background")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            background = args[index];
            continue;
        }

        if (std.mem.eql(u8, arg, "--direction")) {
            index += 1;
            if (index >= args.len) return CliError.MissingOptionValue;
            direction = parseDirection(args[index]) catch return CliError.UnknownOption;
            continue;
        }

        if (std.mem.startsWith(u8, arg, "-")) return CliError.UnknownOption;

        switch (positional_count) {
            0 => font_path = arg,
            1 => text = arg,
            else => return CliError.TooManyArguments,
        }
        positional_count += 1;
    }

    return .{
        .font_path = font_path orelse return CliError.MissingFontPath,
        .text = text,
        .output_path = output_path,
        .font_size_px = font_size_px,
        .margin_px = margin_px,
        .fill = fill,
        .background = background,
        .direction = direction,
        .face_index = face_index,
        .variation_coords = variation_coords,
        .variation_coord_count = variation_coord_count,
        .variation_instance_index = variation_instance_index,
        .quiet = quiet,
    };
}

fn cliErrorMessage(err: CliError) []const u8 {
    return switch (err) {
        CliError.ConflictingVariationOptions => "cannot combine --variation and --variation-instance",
        CliError.InvalidFaceIndex => "invalid face index",
        CliError.InvalidFontSize => "invalid font size",
        CliError.InvalidMargin => "invalid margin",
        CliError.InvalidVariationCoord => "invalid variation coordinate",
        CliError.InvalidVariationInstanceIndex => "invalid variation instance index",
        CliError.MissingFontPath => "missing font path",
        CliError.MissingOptionValue => "missing value after option",
        CliError.TooManyArguments => "too many positional arguments",
        CliError.UnknownOption => "unknown option",
    };
}

fn parseVariationCoord(value: []const u8) CliError!zfr.VariationCoord {
    const separator = std.mem.indexOfScalar(u8, value, '=') orelse return CliError.InvalidVariationCoord;
    if (separator != variation_tag_len or separator + 1 >= value.len) return CliError.InvalidVariationCoord;
    const coord = std.fmt.parseFloat(f64, value[separator + 1 ..]) catch return CliError.InvalidVariationCoord;
    if (!std.math.isFinite(coord)) return CliError.InvalidVariationCoord;
    return .{
        .tag = value[0..variation_tag_len].*,
        .value = coord,
    };
}

fn parseDirection(value: []const u8) !zfr.ShapeDirection {
    if (std.mem.eql(u8, value, "auto")) return .auto;
    if (std.mem.eql(u8, value, "ltr")) return .ltr;
    if (std.mem.eql(u8, value, "rtl")) return .rtl;
    if (std.mem.eql(u8, value, "ttb") or std.mem.eql(u8, value, "vertical")) return .ttb;
    return error.UnknownOption;
}

fn printUsage(writer: *std.Io.Writer) !void {
    try writer.print(
        \\Usage:
        \\  zig_font_renderer --font <font-file> [--face-index <n>] [--text <utf8-text>] [--output <svg-file>] [--font-size <px>] [--margin <px>] [--fill <color>] [--background <color>] [--direction <auto|ltr|rtl|ttb>] [--variation <axis=value>]... [--variation-instance <n>] [--quiet]
        \\  zig_font_renderer <font-file> [utf8-text]
        \\
        \\Prints data currently available from the Unit 1 font parser:
        \\  - font scalar metadata
        \\  - SFNT table records
        \\  - glyph IDs and horizontal metrics for UTF-8 text
        \\  - SVG output for simple TrueType glyph outlines when --output is set
        \\
    , .{});
}

fn printFaceInfo(writer: *std.Io.Writer, font_path: []const u8, face: zfr.Face) !void {
    try writer.print("Font: {s}\n", .{font_path});
    try writer.print("units_per_em: {d}\n", .{face.units_per_em});
    try writer.print("num_glyphs: {d}\n", .{face.num_glyphs});
    try writer.print("number_of_h_metrics: {d}\n", .{face.number_of_h_metrics});
    try writer.print("\nTables ({d}):\n", .{face.tables.len});

    for (face.tables) |table| {
        try writer.print("  {s} offset={d} length={d}\n", .{ &table.tag, table.offset, table.length });
    }
}

fn printTextGlyphs(writer: *std.Io.Writer, face: zfr.Face, text: []const u8, direction: zfr.ShapeDirection) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const engine = zfr.ShapeEngine.init();
    var shaped = engine.shapeTextWithOptions(arena.allocator(), face, text, .{ .direction = direction }) catch |err| {
        try writer.print("\nText glyphs: shaping failed ({s})\n", .{@errorName(err)});
        return;
    };
    defer shaped.deinit(arena.allocator());

    try writer.print("\nText glyphs:\n", .{});
    for (shaped.glyphs, 0..) |glyph, index| {
        try writer.print(
            "  [{d}] cluster={d} U+{X:0>4} glyph_id={d} x_offset={d} y_offset={d} x_advance={d} y_advance={d} kern={d} lsb={d}\n",
            .{ index, glyph.cluster, glyph.codepoint, glyph.glyph_id, glyph.x_offset, glyph.y_offset, glyph.x_advance, glyph.y_advance, glyph.kern_adjustment, glyph.lsb },
        );
    }
    try writer.print("  total_advance={d}\n", .{shaped.total_advance});
}

fn writeSvg(
    allocator: std.mem.Allocator,
    stderr: *std.Io.Writer,
    font_path: []const u8,
    text: []const u8,
    output_path: []const u8,
    options: struct {
        font_size_px: f64,
        margin_px: f64,
        fill: []const u8,
        background: ?[]const u8,
        shape: zfr.ShapeOptions,
        face_index: u32,
        variation_coords: []const zfr.VariationCoord,
        variation_instance_index: ?u16,
    },
) !void {
    const svg = zfr.renderToSvg(allocator, font_path, text, .{
        .render = .{
            .font_size_px = options.font_size_px,
            .margin_px = options.margin_px,
            .fill = options.fill,
            .background = options.background,
            .shape = options.shape,
            .variation_coords = options.variation_coords,
            .variation_instance_index = options.variation_instance_index,
        },
        .face_index = options.face_index,
    }) catch |err| {
        try stderr.print("error: failed to render SVG: {s}\n", .{@errorName(err)});
        try stderr.flush();
        std.process.exit(1);
    };
    defer allocator.free(svg);

    const io = std.Io.Threaded.global_single_threaded.io();
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = svg }) catch |err| {
        try stderr.print("error: failed to write SVG '{s}': {s}\n", .{ output_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };
}

test "parse positional font and text arguments" {
    const args = [_][]const u8{ "zig_font_renderer", "font.ttf", "Hello" };
    const options = try parseArgs(&args);
    try std.testing.expectEqualStrings("font.ttf", options.font_path);
    try std.testing.expectEqualStrings("Hello", options.text.?);
    try std.testing.expect(options.output_path == null);
}

test "parse named font and text arguments" {
    const args = [_][]const u8{
        "zig_font_renderer",
        "--font",
        "font.otf",
        "--text",
        "A",
        "--output",
        "out.svg",
        "--font-size",
        "96",
        "--face-index",
        "2",
        "--variation",
        "wght=700",
        "--variation",
        "wdth=75",
        "--margin",
        "12",
        "--fill",
        "#222",
        "--background",
        "white",
        "--quiet",
    };
    const options = try parseArgs(&args);
    try std.testing.expectEqualStrings("font.otf", options.font_path);
    try std.testing.expectEqualStrings("A", options.text.?);
    try std.testing.expectEqualStrings("out.svg", options.output_path.?);
    try std.testing.expectEqual(@as(f64, 96.0), options.font_size_px);
    try std.testing.expectEqual(@as(u32, 2), options.face_index);
    try std.testing.expectEqual(@as(usize, 2), options.variation_coord_count);
    try std.testing.expectEqualStrings("wght", &options.variation_coords[0].tag);
    try std.testing.expectEqual(@as(f64, 700.0), options.variation_coords[0].value);
    try std.testing.expectEqualStrings("wdth", &options.variation_coords[1].tag);
    try std.testing.expectEqual(@as(f64, 75.0), options.variation_coords[1].value);
    try std.testing.expectEqual(@as(f64, 12.0), options.margin_px);
    try std.testing.expectEqualStrings("#222", options.fill);
    try std.testing.expectEqualStrings("white", options.background.?);
    try std.testing.expect(options.quiet);
}

test "parse rejects missing font path" {
    const args = [_][]const u8{"zig_font_renderer"};
    try std.testing.expectError(CliError.MissingFontPath, parseArgs(&args));
}

test "parse rejects invalid font size" {
    const args = [_][]const u8{ "zig_font_renderer", "--font", "font.ttf", "--font-size", "0" };
    try std.testing.expectError(CliError.InvalidFontSize, parseArgs(&args));
}

test "parse rejects invalid face index" {
    const args = [_][]const u8{ "zig_font_renderer", "--font", "font.ttc", "--face-index", "-1" };
    try std.testing.expectError(CliError.InvalidFaceIndex, parseArgs(&args));
}

test "parse accepts variation instance index" {
    const args = [_][]const u8{ "zig_font_renderer", "--font", "font.ttf", "--variation-instance", "1" };
    const options = try parseArgs(&args);
    try std.testing.expectEqual(@as(?u16, 1), options.variation_instance_index);
}

test "parse rejects invalid variation coordinate" {
    const args = [_][]const u8{ "zig_font_renderer", "--font", "font.ttf", "--variation", "weight=700" };
    try std.testing.expectError(CliError.InvalidVariationCoord, parseArgs(&args));
}

test "parse rejects conflicting variation options" {
    const args = [_][]const u8{ "zig_font_renderer", "--font", "font.ttf", "--variation", "wght=700", "--variation-instance", "1" };
    try std.testing.expectError(CliError.ConflictingVariationOptions, parseArgs(&args));
}

test "parse rejects invalid margin" {
    const args = [_][]const u8{ "zig_font_renderer", "--font", "font.ttf", "--margin", "-1" };
    try std.testing.expectError(CliError.InvalidMargin, parseArgs(&args));
}

test "parse accepts vertical direction" {
    const args = [_][]const u8{
        "zig_font_renderer",
        "--font",
        "font.otf",
        "--direction",
        "ttb",
    };
    const options = try parseArgs(&args);
    try std.testing.expectEqual(zfr.ShapeDirection.ttb, options.direction);
}
