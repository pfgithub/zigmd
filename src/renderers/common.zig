const std = @import("std");
const help = @import("../helpers.zig");

pub const WindowSize = struct {
    w: i64,
    h: i64,
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return Color.rgba(r, g, b, 255);
    }
    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{ .r = r, .g = g, .b = b, .a = a };
    }
    pub fn hex(comptime color: u24) Color {
        return Color{
            .r = (color >> 16),
            .g = (color >> 8) & 0xFF,
            .b = color & 0xFF,
            .a = 0xFF,
        };
    }
    fn equal(a: Color, b: Color) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
    }
};

pub const Key = enum(u64) {
    Left,
    Right,
    Backspace,
    Return,
    Delete,
    Unknown,
    S,
    Escape,
};

pub const Event = union(enum) {
    Quit: void,
    pub const UnknownEvent = struct {
        type: u32,
    };
    Unknown: UnknownEvent,
    pub const KeyEvent = struct {
        key: Key,
    };
    KeyDown: KeyEvent,
    KeyUp: KeyEvent,
    pub const MouseEvent = struct {
        pos: Point,
    };
    MouseDown: MouseEvent,
    MouseUp: MouseEvent,
    pub const MouseMotionEvent = struct {
        pos: Point,
    };
    MouseMotion: MouseMotionEvent,
    pub const TextInputEvent = struct {
        text: [100]u8,
        length: u32,
    };
    TextInput: TextInputEvent,
    pub const EmptyEvent = void;
    Empty: EmptyEvent,
    pub const empty = Event{ .Empty = {} };
    pub const Type = @TagType(@This());
};

pub const Cursor = enum {
    default,
    pointer,
    ibeam,
};

pub const TextSize = struct {
    w: i64,
    h: i64,
};

pub const Point = struct {
    x: i64,
    y: i64,
};
pub const Rect = struct {
    x: i64,
    y: i64,
    w: i64,
    h: i64,
    pub fn containsPoint(rect: Rect, point: Point) bool {
        return point.x >= rect.x and point.x <= rect.x + rect.w and
            point.y >= rect.y and point.y <= rect.y + rect.h;
    }
    pub fn center(rect: Rect) Point {
        return .{
            .x = rect.x + @divFloor(rect.w, 2),
            .y = rect.y + @divFloor(rect.h, 2),
        };
    }
    fn overlap(one: Rect, two: Rect) Rect {
        var fx = if (one.x > two.x) one.x else two.x;
        var fy = if (one.y > two.y) one.y else two.y;
        var onex2 = one.x + one.w;
        var twox2 = two.x + two.w;
        var oney2 = one.y + one.h;
        var twoy2 = two.y + two.h;
        var fx2 = if (onex2 > twox2) twox2 else onex2;
        var fy2 = if (oney2 > twoy2) twoy2 else oney2;
        return .{
            .x = fx,
            .y = fy,
            .w = fx2 - fx,
            .h = fy2 - fy,
        };
    }
    pub fn right(rect: Rect, distance: i64) Rect {
        return .{ .x = rect.x + distance, .y = rect.y, .w = rect.w, .h = rect.h };
    }
    pub fn rightCut(rect: Rect, distance: i64) Rect {
        return .{ .x = rect.x + distance, .y = rect.y, .w = rect.w - distance, .h = rect.h };
    }
    pub fn down(rect: Rect, distance: i64) Rect {
        return .{ .x = rect.x, .y = rect.y + distance, .w = rect.w, .h = rect.h };
    }
    pub fn downCut(rect: Rect, distance: i64) Rect {
        return .{ .x = rect.x, .y = rect.y + distance, .w = rect.w, .h = rect.h - distance };
    }
    pub fn width(rect: Rect, newWidth: i64) Rect {
        return .{ .x = rect.x, .y = rect.y, .w = newWidth, .h = rect.h };
    }
    pub fn height(rect: Rect, newHeight: i64) Rect {
        return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = newHeight };
    }
};
pub const TopRect = struct {
    x: i64,
    y: i64,
    w: i64,
    pub fn right(rect: TopRect, distance: i64) TopRect {
        return .{ .x = rect.x + distance, .y = rect.y, .w = rect.w };
    }
    pub fn rightCut(rect: TopRect, distance: i64) TopRect {
        return .{ .x = rect.x + distance, .y = rect.y, .w = rect.w - distance };
    }
    pub fn down(rect: TopRect, distance: i64) TopRect {
        return .{ .x = rect.x, .y = rect.y + distance, .w = rect.w };
    }
    pub fn width(rect: TopRect, newWidth: i64) TopRect {
        return .{ .x = rect.x, .y = rect.y, .w = newWidth };
    }
    pub fn height(rect: TopRect, h: i64) Rect {
        return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = h };
    }
};
