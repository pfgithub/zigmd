const ray = @import("raylib/workaround.zig");
const std = @import("std");
const help = @import("../helpers.zig");

// textinput: utf8encode. raylib gives a unicode codepoint, render wants an []u8.
