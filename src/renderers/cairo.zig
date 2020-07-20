usingnamespace @cImport({
    @cInclude("cairo_cbind.h");
});
const std = @import("std");
const help = @import("../helpers.zig");

pub usingnamespace @import("./common.zig");

var nextEventFrame: anyframe = undefined;
var eventResult: struct { cr: *cairo_t } = undefined;

pub fn waitNextEvent() ?*cairo_t {
    suspend {
        nextEventFrame = @frame();
    }
    return eventResult.cr;
}

export fn zig_on_draw_event(widget: *GtkWidget, cr: *cairo_t) callconv(.C) void {
    // going to resume an async function in order to pretend to have an event loop
    eventResult = .{ .cr = cr };
    resume nextEventFrame;
}

pub fn asyncMain() void {
    // waitNextEvent must be called
    while (waitNextEvent()) |cr| {
        cairo_set_source_rgb(cr, 0, 0, 0);
        cairo_select_font_face(cr, "Sans", .CAIRO_FONT_SLANT_NORMAL, .CAIRO_FONT_WEIGHT_NORMAL);
        cairo_set_font_size(cr, 40.0);

        cairo_move_to(cr, 10.0, 50.0);
        cairo_show_text(cr, "Cairo Test.");
    }
}

pub fn main() !void {
    _ = async asyncMain();
    if (start_gtk(0, undefined) != 0) return error.Failure;
}
