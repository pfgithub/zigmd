const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("SDL.h");
    @cInclude("SDL_ttf.h");
});
const std = @import("std");

// usingnamespace c ?

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

pub const Font = struct {
    sdlFont: *c.TTF_Font,
    pub fn init(ttfPath: [*c]const u8, size: u16) !Font {
        var font = c.TTF_OpenFont(ttfPath, size);
        if (font == null) return ttfError();
        errdefer c.TTF_CloseFont(font);

        return Font{
            .sdlFont = font.?,
        };
    }
    pub fn deinit(font: *Font) void {
        c.TTF_CloseFont(font.sdlFont);
    }
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
    fn fromSDL(color: c.SDL_Color) Color {
        return Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
    fn toSDL(color: Color) c.SDL_Color {
        return c.SDL_Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
    fn equal(a: Color, b: Color) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
    }
};

pub const WindowSize = struct {
    w: u64,
    h: u64,
};

pub const Key = enum(u64) {
    Left,
    Right,
    Backspace,
    Return,
    Delete,
    Unknown,
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
    pub const MouseEvent = struct {
        x: i32,
        y: i32,
    };
    MouseDown: MouseEvent,
    MouseUp: MouseEvent,
    pub const MouseMotionEvent = struct {
        x: i32,
        y: i32,
    };
    MouseMotion: MouseMotionEvent,
    pub const TextInputEvent = struct {
        text: [100]u8,
        length: u32,
    };
    TextInput: TextInputEvent,
    fn fromSDL(event: c.SDL_Event) Event {
        return switch (event.type) {
            c.SDL_QUIT => Event{ .Quit = {} },
            c.SDL_KEYDOWN => Event{
                .KeyDown = .{
                    .key = switch (event.key.keysym.scancode) {
                        .SDL_SCANCODE_LEFT => .Left,
                        .SDL_SCANCODE_RIGHT => .Right,
                        .SDL_SCANCODE_BACKSPACE => .Backspace,
                        .SDL_SCANCODE_RETURN => .Return,
                        .SDL_SCANCODE_DELETE => .Delete,
                        else => Key.Unknown,
                    },
                },
            },
            c.SDL_MOUSEBUTTONDOWN => Event{
                .MouseDown = .{
                    .x = event.button.x,
                    .y = event.button.y,
                },
            },
            c.SDL_MOUSEBUTTONUP => Event{
                .MouseUp = .{
                    .x = event.button.x,
                    .y = event.button.y,
                },
            },
            c.SDL_MOUSEMOTION => Event{
                .MouseMotion = .{
                    .x = event.motion.x,
                    .y = event.motion.y,
                },
            },
            c.SDL_TEXTINPUT => blk: {
                var text: [100]u8 = undefined;
                std.mem.copy(u8, &text, &event.text.text); // does the event.text.text memory get leaked? what happens to it?
                break :blk Event{
                    .TextInput = .{ .text = text, .length = @intCast(u32, c.strlen(&event.text.text)) },
                };
            },
            else => Event{ .Unknown = UnknownEvent{ .type = event.type } },
        };

        // if (event.type == c.SDL_QUIT) {
        //     break;
        // }
        // if (event.type == c.SDL_MOUSEMOTION) {
        //     try stdout.print("MouseMotion: {}\n", .{event.motion});
        // } else if (event.type == c.SDL_MOUSEWHEEL) {
        //     try stdout.print("MouseWheel: {}\n", .{event.wheel});
        // } else if (event.type == c.SDL_KEYDOWN) {
        //     // use for hotkeys
        //     try stdout.print("KeyDown: {} {}\n", .{ event.key.keysym.sym, event.key.keysym.mod });
        // } else if (event.type == c.SDL_TEXTINPUT) {
        //     // use for typing
        //     try stdout.print("TextInput: {}\n", .{event.text});
        // } else {
        //     try stdout.print("Event: {}\n", .{event.type});
        // }
    }
    pub const Type = @TagType(@This());
};

pub const Window = struct {
    sdlWindow: *c.SDL_Window,
    sdlRenderer: *c.SDL_Renderer,
    pub fn init() !Window {
        var window = c.SDL_CreateWindow(
            "hello_sdl2",
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            640,
            480,
            c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
        );
        if (window == null) return sdlError();
        errdefer c.SDL_DestroyWindow(window);

        var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED);
        if (renderer == null) return sdlError();
        errdefer c.SDL_DestroyRenderer(renderer);

        return Window{
            .sdlWindow = window.?,
            .sdlRenderer = renderer.?,
        };
    }
    pub fn deinit(window: *Window) void {
        c.SDL_DestroyRenderer(window.sdlRenderer);
        c.SDL_DestroyWindow(window.sdlWindow);
    }

    pub fn waitEvent(window: *Window) !Event {
        var event: c.SDL_Event = undefined;
        if (c.SDL_WaitEvent(&event) != 1) return sdlError();
        return Event.fromSDL(event);
    }

    pub fn clear(window: *Window) !void {
        if (c.SDL_SetRenderDrawColor(window.sdlRenderer, 0, 0, 0, 0) != 0) return sdlError();
        if (c.SDL_RenderClear(window.sdlRenderer) < 0) return sdlError();
    }
    pub fn present(window: *Window) void {
        c.SDL_RenderPresent(window.sdlRenderer);
    }
    pub fn getSize(window: *Window) !WindowSize {
        var screenWidth: c_int = undefined;
        var screenHeight: c_int = undefined;
        if (c.SDL_GetRendererOutputSize(window.sdlRenderer, &screenWidth, &screenHeight) < 0) return sdlError();
        return WindowSize{
            .w = @intCast(u64, screenWidth), // should never fail
            .h = @intCast(u64, screenHeight),
        };
    }
};

pub const TextSize = struct {
    w: u64,
    h: u64,
};
pub fn measureText(font: *const Font, text: [*c]const u8) !TextSize {
    var w: c_int = undefined;
    var h: c_int = undefined;
    if (c.TTF_SizeUTF8(font.sdlFont, text, &w, &h) < 0) return ttfError();
    return TextSize{ .w = @intCast(u64, w), .h = @intCast(u64, h) };
}

pub fn renderText(window: *const Window, font: *const Font, color: Color, text: [*c]const u8, x: u64, y: u64, size: TextSize) !void {
    var surface = c.TTF_RenderUTF8_Blended(font.sdlFont, text, color.toSDL());
    defer c.SDL_FreeSurface(surface);
    var texture = c.SDL_CreateTextureFromSurface(window.sdlRenderer, surface);
    defer c.SDL_DestroyTexture(texture);
    var rect = c.SDL_Rect{
        .x = @intCast(c_int, x),
        .y = @intCast(c_int, y),
        .w = @intCast(c_int, size.w),
        .h = @intCast(c_int, size.h),
    };
    if (c.SDL_RenderCopy(window.sdlRenderer, texture, null, &rect) < 0) return sdlError();
}

pub const Rect = struct {
    x: u64,
    y: u64,
    w: u64,
    h: u64,
    fn toSDL(rect: *const Rect) c.SDL_Rect {
        return c.SDL_Rect{
            .x = @intCast(c_int, rect.x),
            .y = @intCast(c_int, rect.y),
            .w = @intCast(c_int, rect.w),
            .h = @intCast(c_int, rect.h),
        };
    }
};
pub fn renderRect(window: *const Window, color: Color, rect: Rect) !void {
    var sdlRect = rect.toSDL();
    if (c.SDL_SetRenderDrawColor(window.sdlRenderer, color.r, color.g, color.b, color.a) != 0) return sdlError();
    if (c.SDL_RenderFillRect(window.sdlRenderer, &sdlRect) != 0) return sdlError();
}

pub fn init() RenderingError!void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) return sdlError();
    errdefer c.SDL_Quit();

    if (c.TTF_Init() < 0) return sdlError();
    errdefer c.TTF_Quit();

    c.SDL_StartTextInput(); // todo
}

pub fn deinit() void {
    c.TTF_Quit();
    c.SDL_Quit();
}
