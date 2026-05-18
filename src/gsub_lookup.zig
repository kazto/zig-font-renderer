pub const GsubLookupType = enum(u16) {
    single_substitution = 1,
    alternate_substitution = 3,
    ligature_substitution = 4,
    contextual_substitution = 5,
    chained_contextual_substitution = 6,
};
