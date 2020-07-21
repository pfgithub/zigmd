usingnamespace @cImport({
    @cInclude("cairo_cbind.h");
});
const std = @import("std");
const help = @import("../helpers.zig");

pub usingnamespace @import("./common.zig");

// has bitfield
const GdkEventKey_f = extern struct {
    type_: GdkEventType,
    window: *GdkWindow,
    send_event: gint8,
    time: gint32,
    state: guint,
    keyval: guint,
    length: gint,
    string: [*]gchar,
    hardware_keycode: guint16,
    group: guint8,
    is_modifier: u8, // bitfield u1
    fn c(me: *GdkEventKey_f) *GdkEventKey {
        return @ptrCast(*GdkEventKey, me);
    }
};

var nextEventFrame: ?anyframe = null;
const RawEvent = union(enum) {
    render: *cairo_t,
    keypress: *GdkEventKey_f,
    keyrelease: *GdkEventKey_f,
};
var eventResult: ?RawEvent = undefined;

pub fn waitNextEvent() ?RawEvent {
    suspend {
        nextEventFrame = @frame();
    }
    nextEventFrame = null;
    return eventResult;
}

fn pushEvent(event: RawEvent) void {
    eventResult = event;
    resume nextEventFrame orelse @panic("No one is waiting for an event. TODO event queue thing.");
}

export fn zig_on_draw_event(cr: *cairo_t) callconv(.C) void {
    pushEvent(.{ .render = cr });
}
export fn zig_on_keypress_event(evk: *GdkEventKey_f, im_context: *GtkIMContext) callconv(.C) gboolean {
    pushEvent(.{ .keypress = evk });
    return gtk_im_context_filter_keypress(im_context, evk.c()); // don't do this for modifier keys obv
}
export fn zig_on_keyrelease_event(evk: *GdkEventKey_f) callconv(.C) void {
    pushEvent(.{ .keyrelease = evk });
}
export fn zig_on_commit_event(context: *GtkIMContext, str: [*:0]gchar, user_data: gpointer) callconv(.C) void {
    std.debug.warn("On commit event `{s}`\n", .{str});
}
export fn zig_on_delete_surrounding_event(context: *GtkIMContext, offset: gint, n_chars: gint, user_data: gpointer) callconv(.C) gboolean {
    @panic("TODO implement IME support");
}
export fn zig_on_preedit_changed_event(context: *GtkIMContext, user_data: gpointer) callconv(.C) void {
    @panic("TODO implement IME support");
}
export fn zig_on_retrieve_surrounding_event(context: *GtkIMContext, user_data: gpointer) callconv(.C) gboolean {
    @panic("TODO implement IME support");
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
            .keyrelease => |kp| {
                std.debug.warn("Keyrelease: {}\n", .{kp});
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
