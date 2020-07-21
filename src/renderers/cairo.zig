usingnamespace @cImport({
    @cInclude("cairo_cbind.h");
});
const std = @import("std");
const help = @import("../helpers.zig");

pub usingnamespace @import("./common.zig");

var nextEventFrame: ?anyframe = null;
const RawEvent = union(enum) {
    render: *cairo_t,
    keypress: *GdkEventKey,
};
var eventResult: ?RawEvent = undefined;

pub fn waitNextEvent() ?RawEvent {
    suspend {
        nextEventFrame = @frame();
    }
    nextEventFrame = null;
    return eventResult;
}

export fn zig_on_draw_event(cr: *cairo_t) callconv(.C) void {
    eventResult = .{ .render = cr };
    resume nextEventFrame orelse @panic("no one is waiting for an event");
}
export fn zig_on_keypress_event(evk: *GdkEventKey) callconv(.C) void {
    eventResult = .{ .keypress = evk };
    resume nextEventFrame orelse @panic("no one is waiting for an event");
}

pub fn asyncMain() void {
    while (waitNextEvent()) |ev| {
        switch (ev) {
            .render => |cr| {
                cairo_set_source_rgb(cr, 0, 0, 0);
                cairo_select_font_face(cr, "Sans", .CAIRO_FONT_SLANT_NORMAL, .CAIRO_FONT_WEIGHT_NORMAL); // you're supposed to use backend specific fns
                cairo_set_font_size(cr, 40.0);

                cairo_move_to(cr, 10.0, 50.0);
                cairo_show_text(cr, "Cairo Test."); // you're supposed to use cairo_show_glyphs instead of this.
                // this is useless because it can't measure text
                // so I need to use cairo_show_glyphs
            },
            .keypress => |kp| {
                std.debug.warn("Keypress: {}\n", .{kp});
            },
        }
    }
}
// one of the reasons for this is I think buttons could look neat if they tilted and that would work better if there was a bit of gradient
// would look neat
// reminder to try that
// mostly I want shadows and rounded rectangles though.
// and sane, working text rendering

pub fn main() !void {
    _ = async asyncMain(); // run until first suspend
    _ = nextEventFrame orelse @panic("main fn did not suspend at waitNextEvent");
    if (start_gtk(0, undefined) != 0) return error.Failure;
}
