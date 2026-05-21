const std = @import("std");
const zfr = @import("zig_font_renderer");

const max_font_file_size = 256 * 1024 * 1024;
const parser_iterations = 200;
const lookup_iterations = 20_000;
const shaping_iterations = 1_000;
const svg_iterations = 100;

const PerfFont = struct {
    label: []const u8,
    path: []const u8,
    text: []const u8,
};

const perf_fonts = [_]PerfFont{
    .{
        .label = "latin",
        .path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        .text = "AV fi Hello 123",
    },
    .{
        .label = "arabic",
        .path = "/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf",
        .text = "سلام123",
    },
    .{
        .label = "devanagari",
        .path = "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf",
        .text = "र्कि",
    },
    .{
        .label = "cff",
        .path = "/usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf",
        .text = "AV fi",
    },
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var executed: usize = 0;
    for (perf_fonts) |font| {
        if (!pathExists(font.path)) {
            try stdout.print("perf smoke skip {s}: missing {s}\n", .{ font.label, font.path });
            continue;
        }
        executed += 1;
        try runFontSmoke(allocator, stdout, font);
    }

    if (executed == 0) {
        try stdout.print("perf smoke skipped: no representative system fonts found\n", .{});
    }
    try stdout.flush();
}

fn runFontSmoke(allocator: std.mem.Allocator, stdout: *std.Io.Writer, font: PerfFont) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const data = try std.Io.Dir.cwd().readFileAlloc(io, font.path, allocator, .limited(max_font_file_size));
    defer allocator.free(data);

    var lap_start = std.Io.Timestamp.now(io, .awake);

    var parser_iteration: usize = 0;
    while (parser_iteration < parser_iterations) : (parser_iteration += 1) {
        var face = try zfr.Face.init(allocator, data);
        face.deinit(allocator);
    }
    const parser_ns = lap(&lap_start, io);

    var face = try zfr.Face.init(allocator, data);
    defer face.deinit(allocator);

    const lookup_codepoints = [_]u32{ 'A', 'V', 'f', 'i', 0x0633, 0x0644, 0x0930, 0x094D, 0x0915 };
    var checksum: u64 = 0;
    var lookup_iteration: usize = 0;
    while (lookup_iteration < lookup_iterations) : (lookup_iteration += 1) {
        const codepoint = lookup_codepoints[lookup_iteration % lookup_codepoints.len];
        const glyph_id = try face.getGlyphId(codepoint);
        const metric = try face.getHMetric(glyph_id);
        checksum +%= glyph_id;
        checksum +%= metric.advance_width;
    }
    const lookup_ns = lap(&lap_start, io);

    var engine = zfr.ShapeEngine.init();
    var shape_iteration: usize = 0;
    while (shape_iteration < shaping_iterations) : (shape_iteration += 1) {
        var shaped = try engine.shapeText(allocator, face, font.text);
        checksum +%= @intCast(shaped.total_advance);
        shaped.deinit(allocator);
    }
    const shaping_ns = lap(&lap_start, io);

    var renderer = zfr.SvgRenderer.init();
    var svg_iteration: usize = 0;
    while (svg_iteration < svg_iterations) : (svg_iteration += 1) {
        const svg = try renderer.renderText(allocator, face, font.text);
        checksum +%= svg.len;
        allocator.free(svg);
    }
    const svg_ns = lap(&lap_start, io);

    try stdout.print(
        "perf smoke {s}: init {d:.3}ms/iter, lookup {d:.3}us/iter, shape {d:.3}us/iter, svg {d:.3}us/iter, checksum {d}\n",
        .{
            font.label,
            perIterMs(parser_ns, parser_iterations),
            perIterUs(lookup_ns, lookup_iterations),
            perIterUs(shaping_ns, shaping_iterations),
            perIterUs(svg_ns, svg_iterations),
            checksum,
        },
    );
}

fn pathExists(path: []const u8) bool {
    const io = std.Io.Threaded.global_single_threaded.io();
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn lap(start: *std.Io.Timestamp, io: std.Io) u64 {
    const now = std.Io.Timestamp.now(io, .awake);
    const duration = start.durationTo(now);
    start.* = now;
    return @intCast(duration.toNanoseconds());
}

fn perIterMs(ns: u64, iterations: usize) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(iterations)) / std.time.ns_per_ms;
}

fn perIterUs(ns: u64, iterations: usize) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(iterations)) / std.time.ns_per_us;
}
