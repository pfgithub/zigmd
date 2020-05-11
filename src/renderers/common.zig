const std = @import("std");
const help = @import("../helpers.zig");

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
    pub fn equal(a: Color, b: Color) bool {
        return std.meta.eql(a, b);
    }
    pub fn interpolate(a: Color, b: Color, progress: f64) Color {
        // might crash with <0 or >1 progress, so just return the start/end color instead of clamping floatToInt. this behaviour is probably also more useful.
        if (progress > 1)
            return b;
        if (progress < 0)
            return a;
        return .{
            .r = @intCast(u8, @intCast(i9, a.r) - @floatToInt(i9, @intToFloat(f64, @intCast(i9, a.r) - @intCast(i9, b.r)) * progress)),
            .g = @intCast(u8, @intCast(i9, a.g) - @floatToInt(i9, @intToFloat(f64, @intCast(i9, a.g) - @intCast(i9, b.g)) * progress)),
            .b = @intCast(u8, @intCast(i9, a.b) - @floatToInt(i9, @intToFloat(f64, @intCast(i9, a.b) - @intCast(i9, b.b)) * progress)),
            .a = @intCast(u8, @intCast(i9, a.a) - @floatToInt(i9, @intToFloat(f64, @intCast(i9, a.a) - @intCast(i9, b.a)) * progress)),
        };
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
    quit: void,
    unknown: Unknown,
    keyDown: KeyEv,
    keyUp: KeyEv,
    mouseDown: Mouse,
    mouseUp: Mouse,
    mouseMotion: MouseMotion,
    textInput: TextInput,
    mouseWheel: MouseWheel,
    empty: Empty,
    pub const Unknown = struct {
        type: u32,
    };
    pub const KeyEv = struct {
        key: Key,
    };
    pub const Mouse = struct {
        pos: Point,
    };
    pub const MouseMotion = struct {
        pos: Point,
    };
    pub const TextInput = struct {
        text: [100]u8,
        length: u32,
    };
    pub const MouseWheel = struct {
        x: i64, // number of pixels to scroll
        y: i64,
    };
    pub const Empty = void;
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
pub const WH = struct {
    w: i64,
    h: i64,
    pub fn position(wh: WH, pt: Point) Rect {
        return .{ .x = pt.x, .y = pt.y, .w = wh.w, .h = wh.h };
    }
    pub fn xy(wh: WH, x: i64, y: i64) Rect {
        return wh.position(.{ .x = x, .y = y });
    }
};
pub const HAlign = enum { left, hcenter, right };
pub const VAlign = enum { top, vcenter, bottom };
pub const Rect = struct {
    x: i64,
    y: i64,
    w: i64,
    h: i64,
    pub fn containsPoint(rect: Rect, point: Point) bool {
        return point.x >= rect.x and point.x <= rect.x + rect.w and
            point.y >= rect.y and point.y <= rect.y + rect.h;
    }
    pub fn centerX(rect: Rect) i64 {
        return rect.x + @divFloor(rect.w, 2);
    }
    pub fn centerY(rect: Rect) i64 {
        return rect.y + @divFloor(rect.h, 2);
    }
    pub fn center(rect: Rect) Point {
        return .{
            .x = rect.centerX(),
            .y = rect.centerY(),
        };
    }
    pub fn position(rect: Rect, item: WH, halign: HAlign, valign: VAlign) Rect {
        return .{
            // rect.x + rect.w * percent - item.w * percent
            .x = switch (halign) {
                .left => rect.x,
                .hcenter => rect.x + @divFloor(rect.w, 2) - @divFloor(item.w, 2),
                .right => rect.x + rect.w - item.w,
            },
            .y = switch (valign) {
                .top => rect.y,
                .vcenter => rect.y + @divFloor(rect.h, 2) - @divFloor(item.h, 2),
                .bottom => rect.y + rect.h - item.h,
            },
            .w = item.w,
            .h = item.h,
        };
        // .overlap(rect)?
    }
    pub fn overlap(one: Rect, two: Rect) Rect {
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
        return rect.right(distance).addWidth(-distance);
    }
    pub fn down(rect: Rect, distance: i64) Rect {
        return .{ .x = rect.x, .y = rect.y + distance, .w = rect.w, .h = rect.h };
    }
    pub fn downCut(rect: Rect, distance: i64) Rect {
        return rect.down(distance).addHeight(-distance);
    }
    pub fn width(rect: Rect, newWidth: i64) Rect {
        return .{ .x = rect.x, .y = rect.y, .w = newWidth, .h = rect.h };
    }
    pub fn addWidth(rect: Rect, newWidth: i64) Rect {
        return rect.width(rect.w + newWidth);
    }
    pub fn setX1(rect: Rect, x1: i64) Rect {
        const newWidth = rect.w + (rect.x - x1);
        return .{ .x = x1, .y = rect.y, .w = newWidth, .h = rect.h };
    }
    pub fn setX2(rect: Rect, x2: i64) Rect {
        return rect.width(x2 - rect.x);
    }
    pub fn height(rect: Rect, newHeight: i64) Rect {
        return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = newHeight };
    }
    pub fn addHeight(rect: Rect, newHeight: i64) Rect {
        return rect.height(rect.h + newHeight);
    }
    pub fn setY2(rect: Rect, y2: i64) Rect {
        return rect.height(y2 - rect.y);
    }
    pub fn noHeight(rect: Rect) TopRect {
        return .{ .x = rect.x, .y = rect.y, .w = rect.w };
    }
};
pub const TopRect = struct {
    x: i64,
    y: i64,
    w: i64,
    pub fn centerX(rect: TopRect) i64 {
        return rect.x + @divFloor(rect.w, 2);
    }
    pub fn right(rect: TopRect, distance: i64) TopRect {
        return .{ .x = rect.x + distance, .y = rect.y, .w = rect.w };
    }
    pub fn rightCut(rect: TopRect, distance: i64) TopRect {
        return rect.right(distance).addWidth(-distance);
    }
    pub fn down(rect: TopRect, distance: i64) TopRect {
        return .{ .x = rect.x, .y = rect.y + distance, .w = rect.w };
    }
    pub fn width(rect: TopRect, newWidth: i64) TopRect {
        return .{ .x = rect.x, .y = rect.y, .w = newWidth };
    }
    pub fn addWidth(rect: TopRect, newWidth: i64) TopRect {
        return rect.width(rect.w + newWidth);
    }
    pub fn setX2(rect: TopRect, x2: i64) TopRect {
        return rect.width(x2 - rect.x);
    }
    pub fn height(rect: TopRect, h: i64) Rect {
        return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = h };
    }
    pub fn setY2(rect: TopRect, y2: i64) Rect {
        return rect.height(y2 - rect.y);
    }
};
