const hm = @import("header_match.zig");
const std = @import("std");

const Writer = struct {
    pub const Error: type = hm.AnyType;
    pub const __h_ALLOW_EXTRA = true;
};

pub fn writeToStream(out: anytype) blk: {
    hm.conformsTo(Writer, @TypeOf(out));
    break :blk @TypeOf(out).Error;
}!void {
    try out.writeAll("test");
}

pub fn main() !void {
    var bad_stream = std.io.getStdOut().writer();
    try writeToStream(bad_stream);
}
