const std = @import("std");

pub const ParserError = error{
    InvalidFontFormat,
    InvalidFaceIndex,
    MissingMandatoryTable,
    TableOutOfBounds,
    InvalidTable,
    UnsupportedCmapFormat,
    InvalidGlyphId,
};

pub const TableMetadata = struct {
    tag: [4]u8,
    offset: u32,
    length: u32,
};

pub const HMetric = struct {
    advance_width: u16,
    lsb: i16,
};

pub const VMetric = struct {
    advance_height: u16,
    tsb: i16,
};

pub const GlyphInfo = struct {
    id: u16,
    advance_width: u16,
    lsb: i16,
};

test {
    _ = std;
}
