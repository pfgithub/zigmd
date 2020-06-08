const std = @import("std");

const main = @import("../main.zig");
const win = @import("../render.zig");
const help = @import("../helpers.zig");
usingnamespace @import("../gui.zig");

const Internal = struct {
    mouseDown: bool = false,
    click: bool = false,
    rerender: bool = undefined,
    latestAssignedID: u32 = 0,

    hoverID: u64 = 0,
    clickID: u64 = 0,
    scrollID: u64 = 0,
    prevScrollDelta: win.Point = undefined,
    next: Next = Next{},

    const Next = struct {
        hoverID: u64 = 0,
        clickID: u64 = 0,
        scrollID: u64 = 0,
    };
};
const Data = struct {
    settings: struct {
        style: Style,
        updateMode: main.UpdateMode,
    },
};
data: Data,
internal: Internal = Internal{},
click: bool = false,
mouseDown: bool = false,
mouseUp: bool = undefined,
mouseDelta: win.Point = undefined,
cursor: win.Point = win.Point{ .x = 0, .y = 0 },
keyDown: ?win.Key = undefined,
key: KeyArr = KeyArr.initDefault(false),
keyUp: ?win.Key = undefined,
textInput: ?win.Event.TextInput = undefined,
time: u64 = undefined,
animationEnabled: bool = false,
scrollDelta: win.Point = win.Point{ .x = 0, .y = 0 },
// unfortunately, sdl scrolling is really bad. numbers are completely random and useless,
// and it only scrolls by whole ticks. this is one of the places raylib is better.
window: *win.Window = undefined,
render: bool = false,
const KeyArr = help.EnumArray(win.Key, bool);

pub fn newID(imev: *ImEvent) ID {
    imev.internal.latestAssignedID += 1;
    return .{ .id = imev.internal.latestAssignedID };
}

pub const Hover = struct {
    click: bool,
    hover: bool,
};
pub fn hover(imev: *ImEvent, id: ID, rect_: win.Rect) Hover {
    if (imev.mouseUp) {
        imev.internal.next.clickID = 0;
    }
    const rect = if (imev.window.clippingRectangle()) |cr| rect_.overlap(cr) else rect_;
    if (rect.containsPoint(imev.cursor)) {
        imev.internal.next.hoverID = id.id;
        if (imev.mouseDown) {
            imev.internal.next.clickID = id.id;
        }
    }
    return .{
        .hover = imev.internal.hoverID == id.id and if (imev.internal.clickID != 0)
            imev.internal.hoverID == imev.internal.clickID
        else
            true,
        .click = imev.internal.clickID == id.id,
    };
}
pub fn scroll(imev: *ImEvent, id: ID, rect_: win.Rect) win.Point {
    const rect = if (imev.window.clippingRectangle()) |cr| rect_.overlap(cr) else rect_;
    // overview:
    // - if scrolled:
    if (!std.meta.eql(imev.scrollDelta, win.Point.origin)) {
        if (rect.containsPoint(imev.cursor))
            imev.internal.next.scrollID = id.id;
        // there needs to be some way to keep the current scroll id if:
        //      the last scroll was <300ms ago
        // and  the last scroll is still under the cursor
    }
    if (imev.internal.scrollID == id.id) {
        return imev.internal.prevScrollDelta;
    }
    return .{ .x = 0, .y = 0 };
}

pub fn apply(imev: *ImEvent, ev: win.Event, window: *win.Window) void {
    // clear instantanious flags (mouseDown, mouseUp)
    if (imev.internal.mouseDown) {
        imev.internal.mouseDown = false;
    }
    imev.mouseUp = false;
    imev.internal.rerender = false;
    imev.keyDown = null;
    imev.keyUp = null;
    imev.textInput = null;
    imev.time = win.time();
    imev.window = window;
    imev.internal.prevScrollDelta = imev.scrollDelta;
    imev.scrollDelta = .{ .x = 0, .y = 0 };

    // is this worth it or should it be written manually? // not worth it
    // inline for (@typeInfo(Internal.Next).Struct.fields) |field| {
    //     @field(imev.internal, field.name) = @field(imev.internal.next, field.name);
    //     @field(imev.internal.next, field.name) = 0;
    // }

    imev.internal.hoverID = imev.internal.next.hoverID;
    imev.internal.next.hoverID = 0;

    imev.internal.clickID = imev.internal.next.clickID;

    imev.internal.scrollID = imev.internal.next.scrollID;
    imev.internal.next.scrollID = 0;

    const startCursor = imev.cursor;

    // apply event
    switch (ev) {
        .mouseMotion => |mmv| {
            imev.cursor = mmv.pos;
        },
        .mouseDown => |clk| {
            imev.internal.mouseDown = true;
            imev.cursor = clk.pos;
            imev.internal.click = true;
        },
        .mouseUp => |clk| {
            imev.mouseUp = true;
            imev.cursor = clk.pos;
            imev.internal.click = false;
        },
        .keyDown => |keyev| {
            imev.keyDown = keyev.key;
            _ = imev.key.set(keyev.key, true);
        },
        .keyUp => |keyev| {
            _ = imev.key.set(keyev.key, false);
            imev.keyUp = keyev.key;
        },
        .textInput => |textin| {
            imev.textInput = textin;
        },
        .mouseWheel => |wheel| {
            imev.scrollDelta = .{ .x = wheel.x, .y = wheel.y };
        },
        else => {},
    }

    // transfer internal to ev itself
    imev.mouseDown = imev.internal.mouseDown;
    imev.click = imev.internal.click;
    imev.mouseDelta = .{ .x = imev.cursor.x - startCursor.x, .y = imev.cursor.y - startCursor.y };
}
pub fn rerender(imev: *ImEvent) void {
    imev.internal.rerender = true;
}
