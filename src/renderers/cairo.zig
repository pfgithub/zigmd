usingnamespace @cImport({
    @cInclude("cairo_cbind.h");
});
const std = @import("std");
const help = @import("../helpers.zig");

usingnamespace @import("./common.zig");

const ER = RenderingError;
const ERF = RenderingError || FontLoadError;

pub const FontLoader = struct {
    pub fn init() FontLoader {
        return .{};
    }
    pub fn deinit(loader: *FontLoader) void {}
    pub fn loadFromName(
        loader: *const FontLoader,
        name: []const u8,
        fontSize: u16,
    ) ERF!Font {
        return Font{};
    }
};
pub const Font = struct {
    pub fn init(ttfPath: []const u8, size: u16) ER!Font {
        return Font{};
    }
    pub fn deinit(font: *Font) void {}
    pub fn loadFromName(
        loader: *const FontLoader,
        name: []const u8,
        fontSize: u16,
    ) ERF!Font {
        return Font{};
    }
};

/// call this before doing any draw functions
fn setClip(window: *Window) void {
    const cr = window.cairo orelse return;
    const clipTo = window.clippingRectangle() orelse return;

    cairo_rectangle(cr, rect.x, rect.y, rect.w, rect.h);
    cairo_clip(cr);
}

pub const Window = struct {
    // public
    cursor: Cursor,
    debug: struct {
        showClippingRects: bool = false,
    },

    clippingRectangles: std.ArrayList(Rect),
    cairo: ?*cairo_t,

    const AllCursors = help.EnumArray(Cursor, *sdl.SDL_Cursor);

    pub fn init(alloc: *std.mem.Allocator) ER!Window {
        var clippingRectangles = std.ArrayList(Rect).init(alloc);
        errdefer clippingRectanges.deinit();

        return Window{
            .cursor = .default,
            .debug = .{},
            .cairo = null,
        };
    }
    pub fn deinit(window: *Window) void {
        window.clippingRectangles.deinit();
    }

    pub fn pushClipRect(window: *Window, rect: Rect) ER!void {
        if (window.debug.showClippingRects) {
            var crcolr = window.clippingRectangles.items.len;
            var crcol = @intCast(u8, std.math.min(crcolr * 8, 255));
            renderRect(
                window,
                Color{ .r = crcol, .g = crcol, .b = crcol, .a = 255 },
                rect,
            ) catch @panic("unhandled");
        }
        const resRect = if (window.clippingRectangles.items.len >= 1)
            rect.overlap(window.clippingRectangles.items[window.clippingRectangles.items.len - 1])
        else
            rect;

        window.clippingRectangles.append(resRect) catch return ER.Unrecoverable;
        errdefer _ = window.clippingRectangles.pop();
    }
    pub fn popClipRect(window: *Window) void {
        _ = window.clippingRectangles.pop();

        _ = if (window.clippingRectangles.items.len >= 1)
            sdl.SDL_RenderSetClipRect(
                window.sdlRenderer,
                &rectToSDL(window.clippingRectangles.items[window.clippingRectangles.items.len - 1]),
            )
        else
            sdl.SDL_RenderSetClipRect(window.sdlRenderer, null);
    }

    pub fn clippingRectangle(window: *Window) ?Rect {
        return if (window.clippingRectangles.items.len >= 1)
            window.clippingRectangles.items[window.clippingRectangles.items.len - 1]
            // stdlib really needs a way to get the last item from an arraylist
        else
            null;
    }

    pub fn waitEvent(window: *Window) ER!Event {
        // gtk timeout or something
        return waitNextEvent();
    }
    pub fn pollEvent(window: *Window) Event {
        return waitNextEvent();
    }

    pub fn clear(window: *Window, color: Color) ER!void {
        const cr = window.cairo orelse return;
        setClip(window);
        cairo_set_source_rgb(cr, color.r, color.g, color.b);
        cairo_paint(cr);
    }
    pub fn present(window: *Window) void {}
    pub fn getSize(window: *Window) ER!WH {
        return .{ .w = 500, .h = 500 };
    }
};

pub const Text = struct {
    text: [:0]const u8,
    window: *Window,
    pub fn measure(
        font: *const Font,
        text: []const u8,
    ) ER!TextSize {
        return TextSize{ .w = text.len * 10, .h = 20 };
    }
    pub fn init(
        font: *const Font,
        color: Color,
        text: []const u8,
        size: ?TextSize,
        window: *Window,
    ) ER!Text {
        const tmpAlloc = std.heap.c_allocator;
        const nullTerminated = std.mem.dupeZ(tmpAlloc, u8, text) catch return error.Unrecoverable;
        errdefer tmpAlloc.free(nullTerminated);

        return Text{
            .window = window,
            .text = nullTerminated,
        };
    }
    pub fn deinit(text: *Text) void {
        std.heap.c_allocator.free(text.text);
    }
    pub fn render(text: *Text, pos: Point) ER!void {
        setClip(text.window);
        const cr = text.window.cairo orelse return;
        cairo_set_source_rgb(cr, 0, 0, 0);
        cairo_select_font_face(cr, "Sans", .CAIRO_FONT_SLANT_NORMAL, .CAIRO_FONT_WEIGHT_NORMAL); // you're supposed to use backend specific fns
        cairo_set_font_size(cr, 40.0);
        cairo_move_to(cr, pos.x, pos.y);
        cairo_show_text(cr, text.text);
    }
};
pub fn renderRect(window: *const Window, color: Color, rect: Rect) ER!void {
    setClip(window);
    const cr = window.cairo orelse return;
    cairo_set_source_rgb(cr, color.r, color.g, color.b);
    cairo_set_line_width(cr, 0);
    cairo_rectangle(cr, rect.x, rect.y, rect.w, rect.h);
    cairo_stroke_preserve(cr);
    cairo_fill(cr);
}

pub fn init() RenderingError!void {
    if (start_gtk(0, undefined) != 0) return error.Unrecoverable;
}

pub fn deinit() void {}

pub fn time_() u64 {
    return @intCast(i64, std.time.milliTimestamp());
}

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
    textcommit: []const u8,
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
    pushEvent(.{ .textcommit = std.mem.span(str) });
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

fn roundedRectangle(cr: *cairo_t, x: f64, y: f64, w: f64, h: f64, corner_radius: f64) void {
    const radius = corner_radius;
    const degrees = std.math.pi / 180.0;

    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - radius, y + radius, radius, -90 * degrees, 0 * degrees);
    cairo_arc(cr, x + w - radius, y + h - radius, radius, 0 * degrees, 90 * degrees);
    cairo_arc(cr, x + radius, y + h - radius, radius, 90 * degrees, 180 * degrees);
    cairo_arc(cr, x + radius, y + radius, radius, 180 * degrees, 270 * degrees);
    cairo_close_path(cr);
}

fn range(max: usize) []const void {
    return @as([]const void, &[_]void{}).ptr[0..max];
}

pub fn asyncMain() void {
    var layout: ?*PangoLayout = null;
    defer if (layout) |l| g_object_unref(l);
    while (waitNextEvent()) |ev| {
        switch (ev) {
            .render => |cr| {
                roundedRectangle(cr, 10, 10, 80, 80, 10);
                cairo_set_source_rgb(cr, 0.5, 0.5, 1);
                cairo_fill(cr);
                // cairo_set_source_rgba(cr, 0.5, 0, 0, 0.5);
                // cairo_set_line_width(cr, 10.0);
                // cairo_stroke(cr);

                const text = "Cairo Test. 🙋→⎋ يونيكود.\n" ++ @embedFile("cairo.zig");
                const font = "Monospace 12";

                if (layout == null) {
                    layout = pango_cairo_create_layout(cr);

                    pango_layout_set_text(layout, text, -1);
                    {
                        const description = pango_font_description_from_string(font);
                        defer pango_font_description_free(description);
                        pango_layout_set_font_description(layout, description);
                    }
                }

                cairo_save(cr);
                cairo_move_to(cr, 50, 150);
                pango_cairo_show_layout(cr, layout);
                cairo_restore(cr);
            },
            .keypress => |kp| {
                std.debug.warn("Key↓: {}\n", .{kp.keyval});
            },
            .keyrelease => |kp| {
                std.debug.warn("Key↑: {}\n", .{kp.keyval});
            },
            .textcommit => |str| {
                std.debug.warn("On commit event `{}`\n", .{str});
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
