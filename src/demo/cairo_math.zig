// useful characters
// https://www.compart.com/en/unicode/category/Sm
// integral: ∫, ∬, ∭, ⌠⎮⌡
// parenthesis: (, ⎛⎜⎝, ), ⎞⎟⎠, [, ⎡⎢⎣, ], ⎤⎥⎦
// curlies: {, ⎧⎪⎨⎩, }, ⎫⎪⎬⎭
// powers: ⁰¹²³⁴⁵⁶⁷⁸⁹
// roots: √∛∜

// 2
// ⌠ ⎛ 10 - 24 ⎞²
// ⎮ ⎜ ——————— ⎟  dx
// ⌡ ⎝    5    ⎠
// 0

const std = @import("std");

const Term = union(enum) {
    int_literal: []const u8,
    unary_op: struct { op: enum { negative } },
    bin_op: struct { op: enum { add, mul, div, nthroot, pow }, lhs: *Term, rhs: *Term },
    parens: *Term,
    pub fn new(alloc: *std.mem.Allocator) Term {}
};

const DisplayTerm = union(enum) {
    int_literal: []const u8,
};

// an expression eg integral( pow( div( sub(10, 24), 5 ) , 2) )
// is turned into a displayable thing
