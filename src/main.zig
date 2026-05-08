const std = @import("std");

pub fn main() !void {
    var stderr_buffer: [256]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    try stderr.print("zig_font_renderer CLI will be implemented in Unit 3.\n", .{});
    try stderr.flush();
}

test "cli placeholder remains minimal" {
    try std.testing.expect(true);
}
