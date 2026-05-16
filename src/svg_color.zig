const std = @import("std");

pub const SvgColorError = error{InvalidSvgColor};

pub fn validate(value: []const u8) SvgColorError!void {
    if (value.len == 0) return SvgColorError.InvalidSvgColor;
    for (value) |byte| {
        switch (byte) {
            'a'...'z', 'A'...'Z', '0'...'9', '#', '(', ')', ',', '.', '%', '-', ' ' => {},
            else => return SvgColorError.InvalidSvgColor,
        }
    }
}

test "svg color validation rejects attribute-breaking characters" {
    try validate("#ff00aa");
    try validate("rgb(10, 20, 30)");
    try std.testing.expectError(SvgColorError.InvalidSvgColor, validate("\" onload=\"alert(1)"));
    try std.testing.expectError(SvgColorError.InvalidSvgColor, validate(""));
}
