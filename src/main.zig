const std = @import("std");
const zfr = @import("zig_font_renderer");

const max_font_bytes = 256 * 1024 * 1024;

const CliError = error{
    MissingFontPath,
    MissingOptionValue,
    TooManyArguments,
    UnknownOption,
};

const CliOptions = struct {
    font_path: []const u8,
    text: ?[]const u8,
    help: bool = false,
};

pub fn main() !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [256]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const options = parseArgs(args) catch |err| {
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

    const font_data = std.fs.cwd().readFileAlloc(allocator, options.font_path, max_font_bytes) catch |err| {
        try stderr.print("error: failed to read font file '{s}': {s}\n", .{ options.font_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };
    defer allocator.free(font_data);

    var face = zfr.Face.init(allocator, font_data) catch |err| {
        try stderr.print("error: failed to parse font file '{s}': {s}\n", .{ options.font_path, @errorName(err) });
        try stderr.flush();
        std.process.exit(1);
    };
    defer face.deinit(allocator);

    try printFaceInfo(stdout, options.font_path, face);
    if (options.text) |text| {
        try printTextGlyphs(stdout, face, text);
    }
    try stdout.flush();
}

fn parseArgs(args: []const []const u8) CliError!CliOptions {
    var font_path: ?[]const u8 = null;
    var text: ?[]const u8 = null;
    var positional_count: u8 = 0;

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return .{ .font_path = "", .text = null, .help = true };
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
    };
}

fn cliErrorMessage(err: CliError) []const u8 {
    return switch (err) {
        CliError.MissingFontPath => "missing font path",
        CliError.MissingOptionValue => "missing value after option",
        CliError.TooManyArguments => "too many positional arguments",
        CliError.UnknownOption => "unknown option",
    };
}

fn printUsage(writer: *std.Io.Writer) !void {
    try writer.print(
        \\Usage:
        \\  zig_font_renderer --font <font-file> [--text <utf8-text>]
        \\  zig_font_renderer <font-file> [utf8-text]
        \\
        \\Prints data currently available from the Unit 1 font parser:
        \\  - font scalar metadata
        \\  - SFNT table records
        \\  - glyph IDs and horizontal metrics for UTF-8 text
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

fn printTextGlyphs(writer: *std.Io.Writer, face: zfr.Face, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const engine = zfr.ShapeEngine.init();
    var shaped = engine.shapeText(arena.allocator(), face, text) catch |err| {
        try writer.print("\nText glyphs: shaping failed ({s})\n", .{@errorName(err)});
        return;
    };
    defer shaped.deinit(arena.allocator());

    try writer.print("\nText glyphs:\n", .{});
    for (shaped.glyphs, 0..) |glyph, index| {
        try writer.print(
            "  [{d}] cluster={d} U+{X:0>4} glyph_id={d} x_offset={d} x_advance={d} lsb={d}\n",
            .{ index, glyph.cluster, glyph.codepoint, glyph.glyph_id, glyph.x_offset, glyph.x_advance, glyph.lsb },
        );
    }
    try writer.print("  total_advance={d}\n", .{shaped.total_advance});
}

test "parse positional font and text arguments" {
    const args = [_][]const u8{ "zig_font_renderer", "font.ttf", "Hello" };
    const options = try parseArgs(&args);
    try std.testing.expectEqualStrings("font.ttf", options.font_path);
    try std.testing.expectEqualStrings("Hello", options.text.?);
}

test "parse named font and text arguments" {
    const args = [_][]const u8{ "zig_font_renderer", "--font", "font.otf", "--text", "A" };
    const options = try parseArgs(&args);
    try std.testing.expectEqualStrings("font.otf", options.font_path);
    try std.testing.expectEqualStrings("A", options.text.?);
}

test "parse rejects missing font path" {
    const args = [_][]const u8{"zig_font_renderer"};
    try std.testing.expectError(CliError.MissingFontPath, parseArgs(&args));
}
