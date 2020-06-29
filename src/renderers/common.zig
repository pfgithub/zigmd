const std = @import("std");
const help = @import("../helpers.zig");

pub const RenderingError = error{Unrecoverable};
pub const FontLoadError = error{FontNotFound};

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
    Alt, // LAlt/RAlt?
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
    windowFocus: FocusChange,
    windowBlur: FocusChange,
    resize: Resize,
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
        pub fn slice(text: *const TextInput) []const u8 {
            return text.text[0..text.length];
        }
    };
    pub const MouseWheel = struct {
        x: i64, // number of pixels to scroll
        y: i64,
    };
    pub const Resize = WH;
    pub const FocusChange = struct {};
    pub const Empty = void;
    pub const Type = @TagType(@This());
};

pub const Cursor = enum {
    default,
    pointer,
    ibeam,
    move,
    resizeNwSe,
    resizeNeSw,
    resizeNS,
    resizeEW,
};

pub const TextSize = struct {
    w: i64,
    h: i64,
};

pub const Point = struct {
    x: i64,
    y: i64,
    pub const origin = Point{ .x = 0, .y = 0 };
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

/// AutoRectType(some rect type, .{.x, .y}, .{.h})
/// => struct{x, y, w? (if somerect type has w), h}
/// pub const Rect = AutoRectType(.{.x, .y, .w, .h});
/// pub const TopRect = AutoRectType(.{.x, .y, .w});
/// pub const LeftRect = AutoRectType(.{.x, .y, .h});
/// pub const Point = AutoRectType(.{.x, .y});
/// what about BottomRect/RightRect? those need x2, y2 and are needed to create
/// auto-sized tabs starting on the right side.
fn RectType(comptime Extends: type, comptime sets: var, comptime takes: var) type {}
fn RectFns(comptime This: type) type {
    return struct {
        pub fn x2(rect: This) i64 {
            return rect.x + rect.w;
        }
        pub fn y2(rect: This) i64 {
            return rect.y + rect.h;
        }
        pub fn containsPoint(rect: This, point: Point) bool {
            return point.x >= rect.x and point.x <= rect.x + rect.w and
                point.y >= rect.y and point.y <= rect.y + rect.h;
        }
        pub fn centerX(rect: This) i64 {
            return rect.x + @divFloor(rect.w, 2);
        }
        pub fn centerY(rect: This) i64 {
            return rect.y + @divFloor(rect.h, 2);
        }
        pub fn center(rect: This) Point {
            return .{
                .x = rect.centerX(),
                .y = rect.centerY(),
            };
        }
        // fn copySetReturn()
        // copySet(rect, .{.h = null}) // remove h (returns noHeight)
        fn copySet(rect: This, set: var) This {
            // var return type would be nice here
            // so copyset could set .h on a toprect
            // without a mess of return logic
            var copy = rect;
            inline for (@typeInfo(@TypeOf(set)).Struct.fields) |field| {
                if (!@hasField(This, field.name)) @compileError("Does not have field");
                @field(copy, field.name) = @field(set, field.name);
            }
            return copy;
        }
        pub fn right(rect: This, distance: i64) This {
            return copySet(rect, .{ .x = rect.x + distance });
        }
        pub fn rightCut(rect: This, distance: i64) This {
            return rect.right(distance).addWidth(-distance);
        }
        pub fn down(rect: This, distance: i64) This {
            return copySet(rect, .{ .y = rect.y + distance });
        }
        pub fn downCut(rect: This, distance: i64) This {
            return rect.down(distance).addHeight(-distance);
        }
        pub fn width(rect: This, newWidth: i64) This {
            return copySet(rect, .{ .w = newWidth });
        }
        pub fn addWidth(rect: This, newWidth: i64) This {
            return copySet(rect, .{ .w = rect.w + newWidth });
        }
        pub fn height(rect: This, newHeight: i64) This {
            return copySet(rect, .{ .h = newHeight });
        }
        pub fn addHeight(rect: This, newHeight: i64) This {
            return copySet(rect, .{ .h = rect.h + newHeight });
        }
        pub fn setX(rect: This, x: i64) This {
            return copySet(rect, .{ .x = x });
        }
        pub fn setX1(rect: This, x1: i64) This {
            return copySet(rect, .{ .w = rect.w + (rect.x - x1), .x = x1 });
        }
        pub fn setX2(rect: This, x2_: i64) This {
            return rect.width(x2_ - rect.x);
        }
        pub fn setY1(rect: This, y1: i64) This {
            return copySet(rect, .{ .h = rect.h + (rect.y - y1), .y = y1 });
        }
        pub fn setY2(rect: This, y2_: i64) This {
            return rect.height(y2_ - rect.y);
        }
    };
}

pub const Rect = struct {
    x: i64,
    y: i64,
    w: i64,
    h: i64,
    pub usingnamespace RectFns(Rect);
    pub fn noHeight(rect: Rect) TopRect {
        return .{ .x = rect.x, .y = rect.y, .w = rect.w };
    }
    pub fn inset(rect: Rect, top_: i64, right_: i64, bottom_: i64, left_: i64) Rect {
        return rect.downCut(top_).rightCut(left_).addWidth(-right_).addHeight(-bottom_);
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
};
pub const TopRect = struct {
    x: i64,
    y: i64,
    w: i64,
    // usingnamespace rectFns(.{.x, .y, .w}, TopRect);
    // before each fn, @compileError if it needs more rect
    pub fn x2(rect: Rect) i64 {
        return rect.x + rect.w;
    }
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
    pub fn setX1(rect: TopRect, x1: i64) TopRect {
        const newWidth = rect.w + (rect.x - x1); // #3234 workaround
        return .{ .x = x1, .y = rect.y, .w = newWidth };
    }
    pub fn setX2(rect: TopRect, x2_: i64) TopRect {
        return rect.width(x2_ - rect.x);
    }
    pub fn height(rect: TopRect, h: i64) Rect {
        return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = h };
    }
    pub fn setY2(rect: TopRect, y2_: i64) Rect {
        return rect.height(y2_ - rect.y);
    }
};
