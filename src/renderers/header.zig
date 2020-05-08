const std = @import("std");
const help = @import("../helpers.zig");
pub usingnamespace @import("./common.zig");

const RenderingError = error{
    SDLError,
    TTFError,
};

fn sdlError() RenderingError {
    _ = c.printf("SDL Method Failed: %s\n", c.SDL_GetError());
    return RenderingError.SDLError;
}

fn ttfError() RenderingError {
    _ = c.printf("TTF Method Failed: %s\n", c.TTF_GetError());
    return RenderingError.TTFError;
}

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
    ) !Font {
        return undefined;
    }
};

pub const Font = struct {
    sdlFont: *c.TTF_Font,
    pub fn init(ttfPath: []const u8, size: u16) !Font {
        return undefined;
    }
    pub fn deinit(font: *Font) void {
        return undefined;
    }
    pub fn loadFromName(
        loader: *const FontLoader,
        name: []const u8,
        fontSize: u16,
    ) !Font {
        return undefined;
    }
};

pub const Window = struct {
    cursor: Cursor,

    pub fn init(alloc: *std.mem.Allocator) !Window {
        return undefined;
    }
    pub fn deinit(window: *Window) void {
        return undefined;
    }

    /// defer popClipRect
    pub fn pushClipRect(window: *Window, rect: Rect) !void {
        return undefined;
    }
    pub fn popClipRect(window: *Window) void {
        return undefined;
    }

    pub fn waitEvent(window: *Window) !Event {
        return undefined;
    }
    pub fn pollEvent(window: *Window) !Event {
        return undefined;
    }

    pub fn clear(window: *Window, color: Color) !void {
        return undefined;
    }
    pub fn present(window: *Window) void {
        return undefined;
    }
    pub fn getSize(window: *Window) !WindowSize {
        return undefined;
    }
};

pub const Text = struct {
    size: TextSize,
    pub fn measure(
        font: *const Font,
        text: []const u8,
    ) !TextSize {
        return undefined;
    }
    pub fn init(
        font: *const Font,
        color: Color,
        text: []const u8, // 0-terminated
        size: ?TextSize,
        window: *const Window,
    ) !Text {
        return undefined;
    }
    pub fn deinit(text: *Text) void {
        return undefined;
    }
    pub fn render(text: *Text, window: *const Window, pos: Point) !void {
        return undefined;
    }
};

pub fn renderRect(window: *const Window, color: Color, rect: Rect) !void {
    return undefined;
}

pub fn init() RenderingError!void {
    return undefined;
}

pub fn deinit() void {
    return undefined;
}
