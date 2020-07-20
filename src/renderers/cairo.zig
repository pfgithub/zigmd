usingnamespace @cImport({
    @cInclude("cairo_cbind.h");
});
const std = @import("std");
const help = @import("../helpers.zig");

pub usingnamespace @import("./common.zig");

var nextEventFrame: ?anyframe = null;
const RawEvent = struct { cr: *cairo_t };
var eventResult: ?RawEvent = undefined;

pub fn waitNextEvent() ?RawEvent {
    suspend {
        nextEventFrame = @frame();
    }
    nextEventFrame = null;
    return eventResult;
}

export fn zig_on_draw_event(widget: *GtkWidget, cr: *cairo_t) callconv(.C) void {
    eventResult = .{ .cr = cr };
    resume nextEventFrame orelse @panic("no one is waiting for an event");
}

pub fn asyncMain() void {
    while (waitNextEvent()) |ev| {
        const cr = ev.cr;
        cairo_set_source_rgb(cr, 0, 0, 0);
        cairo_select_font_face(cr, "Sans", .CAIRO_FONT_SLANT_NORMAL, .CAIRO_FONT_WEIGHT_NORMAL);
        cairo_set_font_size(cr, 40.0);

        cairo_move_to(cr, 10.0, 50.0);
        cairo_show_text(cr, "Cairo Test.");
    }
}

pub fn main() !void {
    _ = async asyncMain(); // run until first suspend
    _ = nextEventFrame orelse @panic("main fn did not suspend at waitNextEvent");
    if (start_gtk(0, undefined) != 0) return error.Failure;
}
