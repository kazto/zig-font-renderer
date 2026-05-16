const std = @import("std");

const test_vertical_origin_y = 200;
const test_vertical_origin_result_y = 193.0;

pub const Point = struct {
    x: i16,
    y: i16,
    on_curve: bool,
};

pub const GlyphRange = struct {
    start: usize,
    end: usize,
};

pub const Transform = struct {
    xx: f64 = 1.0,
    yx: f64 = 0.0,
    xy: f64 = 0.0,
    yy: f64 = 1.0,
    dx: f64 = 0.0,
    dy: f64 = 0.0,

    pub fn translate(x: i32, y: i32) Transform {
        return .{ .dx = @floatFromInt(x), .dy = @floatFromInt(y) };
    }

    pub fn compose(self: Transform, inner: Transform) Transform {
        return .{
            .xx = self.xx * inner.xx + self.xy * inner.yx,
            .xy = self.xx * inner.xy + self.xy * inner.yy,
            .yx = self.yx * inner.xx + self.yy * inner.yx,
            .yy = self.yx * inner.xy + self.yy * inner.yy,
            .dx = self.xx * inner.dx + self.xy * inner.dy + self.dx,
            .dy = self.yx * inner.dx + self.yy * inner.dy + self.dy,
        };
    }

    pub fn apply(self: Transform, x: i32, y: i32) TransformedPoint {
        return .{
            .x = self.xx * @as(f64, @floatFromInt(x)) + self.xy * @as(f64, @floatFromInt(y)) + self.dx,
            .y = self.yx * @as(f64, @floatFromInt(x)) + self.yy * @as(f64, @floatFromInt(y)) + self.dy,
        };
    }

    pub fn applyPoint(self: Transform, point: TransformedPoint) TransformedPoint {
        return .{
            .x = self.xx * point.x + self.xy * point.y + self.dx,
            .y = self.yx * point.x + self.yy * point.y + self.dy,
        };
    }
};

pub const TransformedPoint = struct {
    x: f64,
    y: f64,
};

pub const SimpleGlyphOutline = struct {
    end_points: []u16,
    points: []Point,

    pub fn deinit(self: SimpleGlyphOutline, allocator: std.mem.Allocator) void {
        allocator.free(self.end_points);
        allocator.free(self.points);
    }
};

pub const Bounds = struct {
    min_x: i32,
    min_y: i32,
    max_x: i32,
    max_y: i32,

    pub fn include(self: *Bounds, other: Bounds) void {
        self.min_x = @min(self.min_x, other.min_x);
        self.min_y = @min(self.min_y, other.min_y);
        self.max_x = @max(self.max_x, other.max_x);
        self.max_y = @max(self.max_y, other.max_y);
    }

    pub fn width(self: Bounds) i32 {
        return @max(1, self.max_x - self.min_x);
    }

    pub fn height(self: Bounds) i32 {
        return @max(1, self.max_y - self.min_y);
    }
};

pub fn midpoint(a: i16, b: i16) i32 {
    return @divTrunc(@as(i32, a) + @as(i32, b), 2);
}

pub fn readF2Dot14(data: []const u8, offset: usize) !f64 {
    if (offset + 2 > data.len) return error.InvalidTable;
    const raw = std.mem.readInt(i16, data[offset..][0..2], .big);
    return @as(f64, @floatFromInt(raw)) / 16384.0;
}

test "midpoint uses integer midpoint" {
    try std.testing.expectEqual(@as(i32, 5), midpoint(0, 10));
    try std.testing.expectEqual(@as(i32, -1), midpoint(-3, 1));
}

test "transform compose applies nested composite placement" {
    const parent = Transform{ .dx = 100, .dy = 50 };
    const child = Transform{ .xx = 2, .yy = 2, .dx = 10, .dy = 20 };
    const composed = parent.compose(child);
    const point = composed.apply(5, 6);

    try std.testing.expectEqual(@as(f64, 120), point.x);
    try std.testing.expectEqual(@as(f64, 82), point.y);
}

test "glyph transform includes vertical shaping offset" {
    const transform = Transform.translate(10, -20);
    const point = transform.apply(0, test_vertical_origin_y);

    try std.testing.expectEqual(@as(f64, 10), point.x);
    try std.testing.expectEqual(@as(f64, 180), point.y);
}

test "glyph transform applies vertical origin from VORG" {
    const scale = 0.5;
    const transform = Transform{ .yy = scale, .dy = @as(f64, @floatFromInt(test_vertical_origin_y)) * (1.0 - scale) };
    const point = transform.apply(0, 186);

    try std.testing.expectEqual(@as(f64, test_vertical_origin_result_y), point.y);
}

test "read F2Dot14 scale values" {
    const one = [_]u8{ 0x40, 0x00 };
    const half = [_]u8{ 0x20, 0x00 };
    try std.testing.expectEqual(@as(f64, 1.0), try readF2Dot14(&one, 0));
    try std.testing.expectEqual(@as(f64, 0.5), try readF2Dot14(&half, 0));
}
