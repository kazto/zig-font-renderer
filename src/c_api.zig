const std = @import("std");
const font_rendering_service = @import("font_rendering_service.zig");
const shaper = @import("shaper.zig");
const svg_renderer = @import("svg_renderer.zig");

const allocator = std.heap.page_allocator;

pub const zfr_ok: c_int = 0;
pub const zfr_error_invalid_argument: c_int = 1;
pub const zfr_error_out_of_memory: c_int = 2;
pub const zfr_error_io: c_int = 3;
pub const zfr_error_parse: c_int = 4;
pub const zfr_error_render: c_int = 5;

pub const zfr_direction_auto: c_int = 0;
pub const zfr_direction_ltr: c_int = 1;
pub const zfr_direction_rtl: c_int = 2;
pub const zfr_direction_ttb: c_int = 3;

pub const ZfrRenderOptions = extern struct {
    font_size_px: f64,
    margin_px: f64,
    face_index: u32,
    max_font_bytes: usize,
    fill: ?[*:0]const u8,
    background: ?[*:0]const u8,
    direction: c_int,
};

pub export fn zfr_default_render_options() ZfrRenderOptions {
    const defaults = svg_renderer.RenderOptions{};
    return .{
        .font_size_px = defaults.font_size_px,
        .margin_px = defaults.margin_px,
        .face_index = 0,
        .max_font_bytes = 256 * 1024 * 1024,
        .fill = "black",
        .background = null,
        .direction = zfr_direction_auto,
    };
}

pub export fn zfr_render_svg_file(
    font_path: ?[*:0]const u8,
    text: ?[*:0]const u8,
    options: ?*const ZfrRenderOptions,
    out_svg: ?*?[*:0]u8,
    out_len: ?*usize,
) c_int {
    const font_path_ptr = font_path orelse return zfr_error_invalid_argument;
    const text_ptr = text orelse return zfr_error_invalid_argument;
    const out_svg_ptr = out_svg orelse return zfr_error_invalid_argument;
    const out_len_ptr = out_len orelse return zfr_error_invalid_argument;

    out_svg_ptr.* = null;
    out_len_ptr.* = 0;

    const effective_options = if (options) |value| value.* else zfr_default_render_options();
    const render_options = toRenderOptions(effective_options) catch return zfr_error_invalid_argument;
    const service_options = font_rendering_service.RenderToSvgOptions{
        .render = render_options,
        .max_font_bytes = effective_options.max_font_bytes,
        .face_index = effective_options.face_index,
    };

    const svg = font_rendering_service.renderToSvg(
        allocator,
        std.mem.span(font_path_ptr),
        std.mem.span(text_ptr),
        service_options,
    ) catch |err| return statusFromError(err);
    defer allocator.free(svg);

    const terminated = allocator.dupeZ(u8, svg) catch return zfr_error_out_of_memory;
    out_svg_ptr.* = terminated.ptr;
    out_len_ptr.* = terminated.len;
    return zfr_ok;
}

pub export fn zfr_free_string(ptr: ?[*:0]u8, len: usize) void {
    const value = ptr orelse return;
    allocator.free(value[0..len :0]);
}

pub export fn zfr_status_message(status: c_int) [*:0]const u8 {
    return switch (status) {
        zfr_ok => "ok",
        zfr_error_invalid_argument => "invalid argument",
        zfr_error_out_of_memory => "out of memory",
        zfr_error_io => "I/O error",
        zfr_error_parse => "font parse error",
        zfr_error_render => "render error",
        else => "unknown status",
    };
}

fn toRenderOptions(options: ZfrRenderOptions) !svg_renderer.RenderOptions {
    if (options.font_size_px <= 0 or !std.math.isFinite(options.font_size_px)) return error.InvalidArgument;
    if (options.margin_px < 0 or !std.math.isFinite(options.margin_px)) return error.InvalidArgument;
    if (options.max_font_bytes == 0) return error.InvalidArgument;

    return .{
        .font_size_px = options.font_size_px,
        .margin_px = options.margin_px,
        .fill = if (options.fill) |value| std.mem.span(value) else "black",
        .background = if (options.background) |value| std.mem.span(value) else null,
        .shape = .{
            .direction = toShapeDirection(options.direction) catch return error.InvalidArgument,
        },
    };
}

fn toShapeDirection(direction: c_int) !shaper.ShapeDirection {
    return switch (direction) {
        zfr_direction_auto => .auto,
        zfr_direction_ltr => .ltr,
        zfr_direction_rtl => .rtl,
        zfr_direction_ttb => .ttb,
        else => error.InvalidArgument,
    };
}

fn statusFromError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => zfr_error_out_of_memory,
        error.FileNotFound,
        error.AccessDenied,
        error.NotDir,
        error.IsDir,
        error.NameTooLong,
        error.FileTooBig,
        error.StreamTooLong,
        error.ReadFailed,
        error.OpenFailed,
        error.FileBusy,
        error.WouldBlock,
        error.Unexpected,
        => zfr_error_io,
        error.InvalidFontFormat,
        error.MissingMandatoryTable,
        error.InvalidTable,
        error.TableOutOfBounds,
        error.UnsupportedCmapFormat,
        error.InvalidGlyphId,
        error.InvalidFaceIndex,
        error.InvalidVariationInstanceIndex,
        => zfr_error_parse,
        else => zfr_error_render,
    };
}

test "C API default render options are valid" {
    const options = zfr_default_render_options();
    try std.testing.expectEqual(@as(f64, 64.0), options.font_size_px);
    try std.testing.expectEqual(@as(f64, 8.0), options.margin_px);
    try std.testing.expectEqual(@as(u32, 0), options.face_index);
    try std.testing.expectEqual(zfr_direction_auto, options.direction);
}
