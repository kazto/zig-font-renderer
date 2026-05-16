const std = @import("std");
const ot_layout = @import("ot_layout.zig");
const types = @import("shaper_types.zig");

const ShapeDirection = types.ShapeDirection;
const ShapeOptions = types.ShapeOptions;
const ShapedGlyph = types.ShapedGlyph;

const default_feature_tags = [_][4]u8{
    "ccmp".*,
    "locl".*,
    "liga".*,
    "clig".*,
    "calt".*,
    "kern".*,
    "mark".*,
    "mkmk".*,
};

const vertical_default_feature_tags = [_][4]u8{
    "vert".*,
    "vrt2".*,
    "ccmp".*,
    "locl".*,
    "liga".*,
    "clig".*,
    "calt".*,
    "kern".*,
    "mark".*,
    "mkmk".*,
};

const arabic_default_feature_tags = [_][4]u8{
    "ccmp".*,
    "locl".*,
    "isol".*,
    "init".*,
    "medi".*,
    "fina".*,
    "rlig".*,
    "calt".*,
    "kern".*,
    "mark".*,
    "mkmk".*,
};

const vertical_arabic_default_feature_tags = [_][4]u8{
    "vert".*,
    "vrt2".*,
    "ccmp".*,
    "locl".*,
    "isol".*,
    "init".*,
    "medi".*,
    "fina".*,
    "rlig".*,
    "calt".*,
    "kern".*,
    "mark".*,
    "mkmk".*,
};

const indic_default_feature_tags = [_][4]u8{
    "ccmp".*,
    "locl".*,
    "nukt".*,
    "akhn".*,
    "rphf".*,
    "blwf".*,
    "half".*,
    "pstf".*,
    "vatu".*,
    "pres".*,
    "abvs".*,
    "blws".*,
    "psts".*,
    "haln".*,
    "calt".*,
    "kern".*,
    "mark".*,
    "mkmk".*,
};

const vertical_indic_default_feature_tags = [_][4]u8{
    "vert".*,
    "vrt2".*,
    "ccmp".*,
    "locl".*,
    "nukt".*,
    "akhn".*,
    "rphf".*,
    "blwf".*,
    "half".*,
    "pstf".*,
    "vatu".*,
    "pres".*,
    "abvs".*,
    "blws".*,
    "psts".*,
    "haln".*,
    "calt".*,
    "kern".*,
    "mark".*,
    "mkmk".*,
};

const UnicodeRange = struct {
    const latin_script_start = 0x0041;
    const latin_script_end = 0x024F;
    const greek_script_start = 0x0370;
    const greek_script_end = 0x03FF;
    const cyrillic_script_start = 0x0400;
    const cyrillic_script_end = 0x052F;
    const hebrew_script_start = 0x0590;
    const hebrew_script_end = 0x05FF;
    const arabic_script_first_start = 0x0600;
    const arabic_script_first_end = 0x06FF;
    const arabic_script_second_start = 0x0750;
    const arabic_script_second_end = 0x077F;
    const arabic_script_third_start = 0x08A0;
    const arabic_script_third_end = 0x08FF;
    const devanagari_script_start = 0x0900;
    const devanagari_script_end = 0x097F;
    const thai_script_start = 0x0E00;
    const thai_script_end = 0x0E7F;
    const kana_script_start = 0x3040;
    const kana_script_end = 0x30FF;
    const kana_extension_start = 0x31F0;
    const kana_extension_end = 0x31FF;
    const han_script_start = 0x3400;
    const han_script_end = 0x9FFF;
    const han_compatibility_start = 0xF900;
    const han_compatibility_end = 0xFAFF;
    const hangul_script_start = 0xAC00;
    const hangul_script_end = 0xD7AF;
    const hangul_jamo_start = 0x1100;
    const hangul_jamo_end = 0x11FF;
    const hangul_compatibility_jamo_start = 0x3130;
    const hangul_compatibility_jamo_end = 0x318F;
};

pub fn resolveLayoutOptions(options: ShapeOptions, glyphs: []const ShapedGlyph) ShapeOptions {
    var resolved = options;
    if (resolved.script_tag == null) {
        resolved.script_tag = inferScriptTag(glyphs);
    }
    if (resolved.language_tag == null) {
        resolved.language_tag = inferLanguageTag(glyphs);
    }
    if (resolved.feature_tags == null) {
        resolved.feature_tags = defaultFeatureTagsForDirectionAndScript(resolved.direction, resolved.script_tag);
    }
    return resolved;
}

pub fn defaultFeatureTagsForDirectionAndScript(direction: ShapeDirection, script_tag: ?[4]u8) []const [4]u8 {
    if (direction == .ttb) {
        return verticalFeatureTagsForScript(script_tag);
    }

    return defaultFeatureTagsForScript(script_tag);
}

pub fn defaultFeatureTagsForScript(script_tag: ?[4]u8) []const [4]u8 {
    if (script_tag) |tag| {
        if (std.mem.eql(u8, &tag, &ot_layout.OtLayout.arabic_script_tag)) return &arabic_default_feature_tags;
        if (std.mem.eql(u8, &tag, &ot_layout.OtLayout.devanagari_script_tag)) return &indic_default_feature_tags;
    }
    return &default_feature_tags;
}

pub fn verticalFeatureTagsForScript(script_tag: ?[4]u8) []const [4]u8 {
    if (script_tag) |tag| {
        if (std.mem.eql(u8, &tag, &ot_layout.OtLayout.arabic_script_tag)) return &vertical_arabic_default_feature_tags;
        if (std.mem.eql(u8, &tag, &ot_layout.OtLayout.devanagari_script_tag)) return &vertical_indic_default_feature_tags;
    }
    return &vertical_default_feature_tags;
}

pub fn inferScriptTag(glyphs: []const ShapedGlyph) ?[4]u8 {
    for (glyphs) |glyph| {
        if (scriptTagForCodepoint(glyph.codepoint)) |tag| return tag;
    }
    return null;
}

pub fn inferLanguageTag(glyphs: []const ShapedGlyph) ?[4]u8 {
    for (glyphs) |glyph| {
        if (languageTagForCodepoint(glyph.codepoint)) |tag| return tag;
    }
    return null;
}

pub fn scriptTagForCodepoint(codepoint: u21) ?[4]u8 {
    if (isInRange(codepoint, UnicodeRange.latin_script_start, UnicodeRange.latin_script_end)) return ot_layout.OtLayout.latin_script_tag;
    if (isInRange(codepoint, UnicodeRange.greek_script_start, UnicodeRange.greek_script_end)) return ot_layout.OtLayout.greek_script_tag;
    if (isInRange(codepoint, UnicodeRange.cyrillic_script_start, UnicodeRange.cyrillic_script_end)) return ot_layout.OtLayout.cyrillic_script_tag;
    if (isInRange(codepoint, UnicodeRange.hebrew_script_start, UnicodeRange.hebrew_script_end)) return ot_layout.OtLayout.hebrew_script_tag;
    if (isInRange(codepoint, UnicodeRange.arabic_script_first_start, UnicodeRange.arabic_script_first_end) or isInRange(codepoint, UnicodeRange.arabic_script_second_start, UnicodeRange.arabic_script_second_end) or isInRange(codepoint, UnicodeRange.arabic_script_third_start, UnicodeRange.arabic_script_third_end)) return ot_layout.OtLayout.arabic_script_tag;
    if (isInRange(codepoint, UnicodeRange.devanagari_script_start, UnicodeRange.devanagari_script_end)) return ot_layout.OtLayout.devanagari_script_tag;
    if (isInRange(codepoint, UnicodeRange.thai_script_start, UnicodeRange.thai_script_end)) return ot_layout.OtLayout.thai_script_tag;
    if (isInRange(codepoint, UnicodeRange.kana_script_start, UnicodeRange.kana_script_end) or isInRange(codepoint, UnicodeRange.kana_extension_start, UnicodeRange.kana_extension_end)) return ot_layout.OtLayout.kana_script_tag;
    if (isInRange(codepoint, UnicodeRange.han_script_start, UnicodeRange.han_script_end) or isInRange(codepoint, UnicodeRange.han_compatibility_start, UnicodeRange.han_compatibility_end)) return ot_layout.OtLayout.han_script_tag;
    if (isInRange(codepoint, UnicodeRange.hangul_script_start, UnicodeRange.hangul_script_end) or isInRange(codepoint, UnicodeRange.hangul_jamo_start, UnicodeRange.hangul_jamo_end) or isInRange(codepoint, UnicodeRange.hangul_compatibility_jamo_start, UnicodeRange.hangul_compatibility_jamo_end)) return ot_layout.OtLayout.hangul_script_tag;
    return null;
}

pub fn languageTagForCodepoint(codepoint: u21) ?[4]u8 {
    if (isTurkishSpecificLatin(codepoint)) return ot_layout.OtLayout.turkish_language_tag;
    if (isInRange(codepoint, UnicodeRange.hebrew_script_start, UnicodeRange.hebrew_script_end)) return ot_layout.OtLayout.hebrew_language_tag;
    if (isInRange(codepoint, UnicodeRange.arabic_script_first_start, UnicodeRange.arabic_script_first_end) or isInRange(codepoint, UnicodeRange.arabic_script_second_start, UnicodeRange.arabic_script_second_end) or isInRange(codepoint, UnicodeRange.arabic_script_third_start, UnicodeRange.arabic_script_third_end)) return ot_layout.OtLayout.arabic_language_tag;
    if (isInRange(codepoint, UnicodeRange.thai_script_start, UnicodeRange.thai_script_end)) return ot_layout.OtLayout.thai_language_tag;
    if (isInRange(codepoint, UnicodeRange.kana_script_start, UnicodeRange.kana_script_end) or isInRange(codepoint, UnicodeRange.kana_extension_start, UnicodeRange.kana_extension_end)) return ot_layout.OtLayout.japanese_language_tag;
    if (isInRange(codepoint, UnicodeRange.hangul_script_start, UnicodeRange.hangul_script_end) or isInRange(codepoint, UnicodeRange.hangul_jamo_start, UnicodeRange.hangul_jamo_end) or isInRange(codepoint, UnicodeRange.hangul_compatibility_jamo_start, UnicodeRange.hangul_compatibility_jamo_end)) return ot_layout.OtLayout.korean_language_tag;
    return null;
}

fn isTurkishSpecificLatin(codepoint: u21) bool {
    return codepoint == 0x011E or codepoint == 0x011F or
        codepoint == 0x0130 or codepoint == 0x0131 or
        codepoint == 0x015E or codepoint == 0x015F;
}

fn isInRange(codepoint: u21, start: u21, end: u21) bool {
    return codepoint >= start and codepoint <= end;
}

fn hasFeatureTag(tags: []const [4]u8, needle: [4]u8) bool {
    for (tags) |tag| {
        if (std.mem.eql(u8, &tag, &needle)) return true;
    }
    return false;
}

test "shape options infer script from text when unspecified" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x304B, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{}, &glyphs);
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.kana_script_tag, &resolved.script_tag.?);
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.japanese_language_tag, &resolved.language_tag.?);
}

test "shape options keep caller-provided script tag" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x304B, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{ .script_tag = ot_layout.OtLayout.latin_script_tag }, &glyphs);
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.latin_script_tag, &resolved.script_tag.?);
}

test "shape options keep caller-provided language tag" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x304B, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{ .language_tag = ot_layout.OtLayout.turkish_language_tag }, &glyphs);
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.turkish_language_tag, &resolved.language_tag.?);
}

test "shape options assign default feature policy" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{}, &glyphs);
    try std.testing.expect(resolved.feature_tags != null);
    try std.testing.expectEqualSlices(u8, &"liga".*, &resolved.feature_tags.?[2]);
}

test "vertical direction assigns vertical feature policy" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 0x304B, .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const resolved = resolveLayoutOptions(.{ .direction = .ttb }, &glyphs);
    try std.testing.expect(hasFeatureTag(resolved.feature_tags.?, "vert".*));
    try std.testing.expect(hasFeatureTag(resolved.feature_tags.?, "vrt2".*));
}

test "shape options keep caller-provided feature tags" {
    const glyphs = [_]ShapedGlyph{
        .{ .codepoint = 'A', .glyph_id = 1, .cluster = 0, .x_offset = 0, .y_offset = 0, .x_advance = 100, .y_advance = 0, .advance_width = 100, .lsb = 0, .kern_adjustment = 0 },
    };
    const selected = [_][4]u8{"salt".*};
    const resolved = resolveLayoutOptions(.{ .feature_tags = &selected }, &glyphs);
    try std.testing.expectEqualSlices(u8, &"salt".*, &resolved.feature_tags.?[0]);
}

test "default feature policy varies by script" {
    const arabic_tags = defaultFeatureTagsForScript(ot_layout.OtLayout.arabic_script_tag);
    try std.testing.expect(hasFeatureTag(arabic_tags, "init".*));
    try std.testing.expect(hasFeatureTag(arabic_tags, "fina".*));

    const indic_tags = defaultFeatureTagsForScript(ot_layout.OtLayout.devanagari_script_tag);
    try std.testing.expect(hasFeatureTag(indic_tags, "half".*));
    try std.testing.expect(hasFeatureTag(indic_tags, "haln".*));
}

test "script inference maps common Unicode ranges" {
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.latin_script_tag, &(scriptTagForCodepoint('A').?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.arabic_script_tag, &(scriptTagForCodepoint(0x0627).?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.han_script_tag, &(scriptTagForCodepoint(0x6F22).?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.hangul_script_tag, &(scriptTagForCodepoint(0xD55C).?));
}

test "language inference maps common Unicode ranges" {
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.turkish_language_tag, &(languageTagForCodepoint(0x0130).?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.arabic_language_tag, &(languageTagForCodepoint(0x0627).?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.japanese_language_tag, &(languageTagForCodepoint(0x304B).?));
    try std.testing.expectEqualSlices(u8, &ot_layout.OtLayout.korean_language_tag, &(languageTagForCodepoint(0xD55C).?));
}
