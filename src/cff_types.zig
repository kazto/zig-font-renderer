const std = @import("std");
const font_parser = @import("font_parser.zig");

pub const CffError = font_parser.ParserError || std.mem.Allocator.Error || error{
    UnsupportedCffOperator,
};

pub const Cff = struct {
    pub const zero_offset = 0;
    pub const first_index = 0;
    pub const header_min_size = 4;
    pub const header_size_offset = 2;
    pub const index_count_size = 2;
    pub const index2_count_size = 4;
    pub const index_off_size_size = 1;
    pub const index_off_size_offset = 2;
    pub const index2_off_size_offset = 4;
    pub const index_first_object_offset = 1;
    pub const index_empty_count = 0;
    pub const index_empty_off_size = 0;
    pub const max_offset_size = 4;
    pub const offset_accumulator_shift_bits = 8;
    pub const dict_escape_operator = 12;
    pub const dict_operator_max = 21;
    pub const top_dict_charstrings_operator = 17;
    pub const top_dict_private_operator = 18;
    pub const top_dict_fd_array_escaped_operator = 36;
    pub const top_dict_fd_select_escaped_operator = 37;
    pub const private_subrs_operator = 19;
    pub const fd_select_format_0 = 0;
    pub const fd_select_format_3 = 3;
    pub const operand_stack_max = 48;
    pub const transient_array_size = 32;
    pub const max_subr_depth = 16;
};

pub const Cff2 = struct {
    pub const header_min_size = 5;
    pub const header_size_offset = 2;
    pub const top_dict_length_offset = 3;
    pub const top_dict_data_offset = 5;
    pub const top_dict_variation_store_operator = 24;
};

pub const Type2 = struct {
    pub const escaped_dotsection = 0;
    pub const escaped_vstem3 = 1;
    pub const escaped_hstem3 = 2;
    pub const escaped_and = 3;
    pub const escaped_or = 4;
    pub const escaped_not = 5;
    pub const escaped_abs = 9;
    pub const escaped_add = 10;
    pub const escaped_sub = 11;
    pub const escaped_div = 12;
    pub const escaped_neg = 14;
    pub const escaped_eq = 15;
    pub const escaped_drop = 18;
    pub const escaped_put = 20;
    pub const escaped_get = 21;
    pub const escaped_ifelse = 22;
    pub const escaped_random = 23;
    pub const escaped_mul = 24;
    pub const escaped_sqrt = 26;
    pub const escaped_dup = 27;
    pub const escaped_exch = 28;
    pub const escaped_index = 29;
    pub const escaped_roll = 30;
    pub const escaped_callothersubr = 16;
    pub const escaped_pop = 17;
    pub const escaped_setcurrentpoint = 33;
    pub const escaped_flex = 35;
    pub const escaped_hflex = 34;
    pub const escaped_hflex1 = 36;
    pub const escaped_flex1 = 37;

    pub const hstem = 1;
    pub const hstem3 = 2;
    pub const vstem = 3;
    pub const vstem3 = 1;
    pub const vmoveto = 4;
    pub const rlineto = 5;
    pub const hlineto = 6;
    pub const vlineto = 7;
    pub const rrcurveto = 8;
    pub const closepath = 9;
    pub const callsubr = 10;
    pub const return_op = 11;
    pub const escape = 12;
    pub const endchar = 14;
    pub const blend = 16;
    pub const hstemhm = 18;
    pub const hintmask = 19;
    pub const cntrmask = 20;
    pub const rmoveto = 21;
    pub const hmoveto = 22;
    pub const vstemhm = 23;
    pub const rcurveline = 24;
    pub const rlinecurve = 25;
    pub const vvcurveto = 26;
    pub const hhcurveto = 27;
    pub const callgsubr = 29;
    pub const vhcurveto = 30;
    pub const hvcurveto = 31;
};

pub const Transform = struct {
    xx: f64 = 1.0,
    yx: f64 = 0.0,
    xy: f64 = 0.0,
    yy: f64 = 1.0,
    dx: f64 = 0.0,
    dy: f64 = 0.0,

    pub fn apply(self: Transform, x: i32, y: i32) TransformedPoint {
        const fx: f64 = @floatFromInt(x);
        const fy: f64 = @floatFromInt(y);
        return .{
            .x = self.xx * fx + self.xy * fy + self.dx,
            .y = self.yx * fx + self.yy * fy + self.dy,
        };
    }
};

pub const TransformedPoint = struct {
    x: f64,
    y: f64,
};

pub const CffIndex = struct {
    data: []const u8,
    count: u32,
    off_size: u8,
    offsets_offset: usize,
    object_data_offset: usize,
    end_offset: usize,
};

pub const CffContext = struct {
    cff: []const u8,
    charstrings: CffIndex,
    global_subrs: CffIndex,
    local_subrs: ?CffIndex = null,
    fd_array_offset: ?usize = null,
    fd_select_offset: ?usize = null,
    cff2_blend_region_count: ?u16 = null,
    is_cff2: bool = false,
};

pub const TopDictInfo = struct {
    charstrings_offset: ?usize = null,
    private_size: ?usize = null,
    private_offset: ?usize = null,
    fd_array_offset: ?usize = null,
    fd_select_offset: ?usize = null,
    variation_store_offset: ?usize = null,
};

pub const Type2State = struct {
    stack: [Cff.operand_stack_max]i32 = undefined,
    othersubr_return_stack: [Cff.operand_stack_max]i32 = undefined,
    transient: [Cff.transient_array_size]i32 = [_]i32{0} ** Cff.transient_array_size,
    stack_len: usize = 0,
    othersubr_return_len: usize = 0,
    x: i32 = 0,
    y: i32 = 0,
    hint_count: usize = 0,
    subpath_start_x: i32 = 0,
    subpath_start_y: i32 = 0,
    subpath_open: bool = false,
    has_current_point: bool = false,
};
