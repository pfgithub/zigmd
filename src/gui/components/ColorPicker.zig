const std = @import("std");
const Alloc = std.mem.Allocator;

const main = @import("../../main.zig");
const help = @import("../../helpers.zig");
const gui = @import("../../gui.zig");
const win = @import("../../render.zig");
const Auto = gui.Auto;
const ImEvent = gui.ImEvent;

const ColorPicker = @This();

id: gui.ID,

pub fn init(imev: *ImEvent) ColorPicker {
    return .{ .id = imev.newID() };
}

pub fn deinit(cp: *ColorPicker) void {}

pub fn render(cp: *ColorPicker, imev: *ImEvent) !void {
    // 3 sliders and a preview box and a hex input
}
