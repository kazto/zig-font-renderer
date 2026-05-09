const std = @import("std");
const font_parser = @import("font_parser.zig");
const svg_renderer = @import("svg_renderer.zig");

pub const RenderToSvgError = font_parser.ParserError || svg_renderer.SvgError || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError || error{
    FileTooBig,
};

const default_max_font_bytes = 256 * 1024 * 1024;

pub const RenderToSvgOptions = struct {
    render: svg_renderer.RenderOptions = .{},
    max_font_bytes: usize = default_max_font_bytes,
};

pub fn renderToSvg(
    allocator: std.mem.Allocator,
    font_path: []const u8,
    text: []const u8,
    options: RenderToSvgOptions,
) RenderToSvgError![]u8 {
    const font_data = try std.fs.cwd().readFileAlloc(allocator, font_path, options.max_font_bytes);
    defer allocator.free(font_data);

    var face = try font_parser.Face.init(allocator, font_data);
    defer face.deinit(allocator);

    const renderer = svg_renderer.SvgRenderer.init();
    return renderer.renderTextWithOptions(allocator, face, text, options.render);
}

test "renderToSvg reports missing file" {
    try std.testing.expectError(
        error.FileNotFound,
        renderToSvg(std.testing.allocator, "missing-font-file.ttf", "A", .{}),
    );
}
