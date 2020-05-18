const std = @import("std");
const help = @import("../helpers.zig");
pub usingnamespace @import("./common.zig");

const ER = RenderingError;
const ERF = RenderingError || FontLoadError;

pub const FontLoader = struct {
    pub fn init() FontLoader {
        return undefined;
    }
    pub fn deinit(loader: *FontLoader) void {
        return undefined;
    }
    pub fn loadFromName(
        loader: *const FontLoader,
        name: []const u8,
        fontSize: u16,
    ) ERF!Font {
        return undefined;
    }
};

pub const Font = struct {
    pub fn init(ttfPath: []const u8, size: u16) ER!Font {
        return undefined;
    }
    pub fn deinit(font: *Font) void {
        return undefined;
    }
    pub fn loadFromName(
        loader: *const FontLoader,
        name: []const u8,
        fontSize: u16,
    ) ERF!Font {
        return undefined;
    }
};

pub const Window = struct {
    cursor: Cursor,

    pub fn init(alloc: *std.mem.Allocator) ER!Window {
        return undefined;
    }
    pub fn deinit(window: *Window) void {
        return undefined;
    }

    /// defer popClipRect
    pub fn pushClipRect(window: *Window, rect: Rect) ER!void {
        return undefined;
    }
    pub fn popClipRect(window: *Window) void {
        return undefined;
    }

    pub fn waitEvent(window: *Window) ER!Event {
        return undefined;
    }
    pub fn pollEvent(window: *Window) Event {
        return undefined;
    }

    pub fn clear(window: *Window, color: Color) ER!void {
        return undefined;
    }
    pub fn present(window: *Window) void {
        return undefined;
    }
    pub fn getSize(window: *Window) ER!WH {
        return undefined;
    }
};

pub const Text = struct {
    size: TextSize,
    pub fn measure(
        font: *const Font,
        text: []const u8,
    ) ER!TextSize {
        return undefined;
    }
    pub fn init(
        font: *const Font,
        color: Color,
        text: []const u8, // 0-terminated
        size: ?TextSize,
        window: *const Window,
    ) ER!Text {
        return undefined;
    }
    pub fn deinit(text: *Text) void {
        return undefined;
    }
    pub fn render(text: *Text, window: *const Window, pos: Point) ER!void {
        return undefined;
    }
};

pub fn renderRect(window: *const Window, color: Color, rect: Rect) ER!void {
    return undefined;
}

pub fn init() ER!void {
    return undefined;
}

pub fn deinit() void {
    return undefined;
}

pub fn time() u64 {
    return undefined;
}
