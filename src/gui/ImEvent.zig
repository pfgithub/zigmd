const std = @import("std");

const main = @import("../main.zig");
const win = @import("../render.zig");
const help = @import("../helpers.zig");
usingnamespace @import("../gui.zig");

pub fn Set(comptime Child: type) type {
    return struct {
        const AL = std.ArrayList(Child);
        const SetThis = @This();
        data: AL,
        pub fn init(alloc: *std.mem.Allocator) SetThis {
            return .{ .data = AL.init(alloc) };
        }
        pub fn deinit(set: *SetThis) void {
            set.data.deinit();
        }
        /// o(n) atm, don't use too often with big lists.
        pub fn add(set: *SetThis, item: Child) !void {
            if (!set.has(item)) {
                try set.data.append(item);
            }
        }
        /// o(n) atm, don't use too often with big lists.
        pub fn has(set: *SetThis, item: Child) bool {
            return for (set.data.items) |itm| {
                if (itm == item) break true;
            } else false;
        }
        pub fn clear(set: *SetThis) void {
            set.data.allocator.free(set.data.toOwnedSlice());
        }
        pub fn isEmpty(set: *SetThis) bool {
            return set.data.items.len == 0;
        }
        // /// move all items from set -> to. to must be empty, set will be emptied.
        /// clear to and move all items from set -> to. set will be empty after.
        pub fn move(set: *SetThis, to: *SetThis) void {
            // if (to.data.items.len != 0) @panic("expected .clear() first");
            // to.data.deinit();
            to.clear();
            to.* = .{ .data = AL.fromOwnedSlice(set.data.allocator, set.data.toOwnedSlice()) };
        }
        /// clear to and copy all items from set -> to.
        pub fn copyTo(set: *SetThis, to: *SetThis) !void {
            to.clear();
            try to.data.appendSlice(set.data.items);
        }
    };
}

const Internal = struct {
    mouseDown: bool = false,
    click: bool = false,
    rerender: bool = false,
    latestAssignedID: u32 = 0,

    // a set would be better than an arraylist because this is only unique values
    // .add, .has, .clear
    hoverIDs: Set(u64),
    clickIDs: Set(u64),
    scrollIDs: Set(u64),
    prevScrollDelta: win.Point = undefined,
    prevMouseDelta: win.Point = undefined, // TODO
    next: Next,
    mouseDownLastFrame: bool = false,

    const Next = struct {
        hoverIDs: Set(u64),
        clickIDs: Set(u64),
        scrollIDs: Set(u64),
    };
};
const Data = struct {
    settings: struct {
        style: Style,
        updateMode: main.UpdateMode,
    },
};
data: Data,
internal: Internal,
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
alloc: *std.mem.Allocator,
// arena: *std.mem.Allocator,
const KeyArr = help.EnumArray(win.Key, bool);

pub fn init(data: Data, alloc: *std.mem.Allocator) ImEvent {
    return .{
        .data = data,
        .alloc = alloc,
        .internal = .{
            .hoverIDs = Set(u64).init(alloc),
            .clickIDs = Set(u64).init(alloc),
            .scrollIDs = Set(u64).init(alloc),
            .next = .{
                .hoverIDs = Set(u64).init(alloc),
                .clickIDs = Set(u64).init(alloc),
                .scrollIDs = Set(u64).init(alloc),
            },
        },
    };
}
pub fn deinit(imev: *ImEvent) void {
    Auto.destroy(&imev.internal, .{ .hoverIDs, .clickIDs, .scrollIDs });
    Auto.destroy(&imev.internal.next, .{ .hoverIDs, .clickIDs, .scrollIDs });
}

pub fn newID(imev: *ImEvent) ID {
    imev.internal.latestAssignedID += 1;
    return .{ .id = imev.internal.latestAssignedID };
}

pub const Hover = struct {
    click: bool,
    hover: bool,
    mouseDown: bool,
};
/// eg making a window that doesn't allow clicks through but when clicked activates and clicks the selected thing:
/// hover(auto.id, rect, .take) // take body clicks and do nothing
/// hover(auto.id.next(1), rect, .passthrough) // take any clicks and move window to foreground
/// sidenote: should auto.id.next be removed in favor of the react style "just call everything every time"?
/// that can be safety-checked
pub const PassthroughMode = enum { take, passthrough };
fn addOrReplace(item: anytype, list: *Set(@TypeOf(item)), mode: PassthroughMode) void {
    switch (mode) {
        .take => list.clear(),
        .passthrough => {},
    }
    list.add(item) catch @panic("oom not handled");
}
pub fn hover(imev: *ImEvent, id: ID, rect_: win.Rect) Hover {
    return imev.hoverMode(id, rect_, .take);
}
pub fn hoverMode(imev: *ImEvent, id: ID, rect_: win.Rect, mode: PassthroughMode) Hover {
    if (imev.mouseUp) {
        imev.internal.next.clickIDs.clear();
    }
    const rect = if (imev.window.clippingRectangle()) |cr| rect_.overlap(cr) else rect_;
    if (rect.containsPoint(imev.cursor)) {
        addOrReplace(id.id, &imev.internal.next.hoverIDs, mode);
        if (imev.mouseDown) {
            addOrReplace(id.id, &imev.internal.next.clickIDs, mode);
        }
    }
    const hovering = imev.internal.hoverIDs.has(id.id) and if (!imev.internal.clickIDs.isEmpty())
        imev.internal.clickIDs.has(id.id)
    else
        true;
    const clicking = imev.internal.clickIDs.has(id.id);
    return .{
        .hover = hovering,
        .click = clicking,
        .mouseDown = clicking and imev.internal.mouseDownLastFrame,
    };
}
pub fn scroll(imev: *ImEvent, id: ID, rect_: win.Rect) win.Point {
    const rect = if (imev.window.clippingRectangle()) |cr| rect_.overlap(cr) else rect_;
    // overview:
    // - if scrolled:
    if (!std.meta.eql(imev.scrollDelta, win.Point.origin)) {
        if (rect.containsPoint(imev.cursor)) {
            addOrReplace(id.id, &imev.internal.next.scrollIDs, .take);
        }
        // there needs to be some way to keep the current scroll id if:
        //      the last scroll was <300ms ago
        // and  the last scroll is still under the cursor
    }
    if (imev.internal.scrollIDs.has(id.id)) {
        return imev.internal.prevScrollDelta;
    }
    return .{ .x = 0, .y = 0 };
}

pub fn tabindex(imev: *ImEvent, id: ID) bool {
    // true if focused, false else.
    // press tab to go to next indexed item
    // if this id is lost, go to the first item with an id that still exists
}

pub fn apply(imev: *ImEvent, ev: win.Event, window: *win.Window) void {
    // clear instantanious flags (mouseDown, mouseUp)
    imev.internal.mouseDownLastFrame = imev.mouseDown;
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

    imev.internal.next.hoverIDs.move(&imev.internal.hoverIDs);
    imev.internal.next.clickIDs.copyTo(&imev.internal.clickIDs) catch @panic("oom not handled");
    imev.internal.next.scrollIDs.move(&imev.internal.scrollIDs);

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
