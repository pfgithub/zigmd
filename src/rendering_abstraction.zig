const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("SDL.h");
    @cInclude("SDL_ttf.h");
});

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
    pub fn init(ttfPath: [*c]const u8) !Font {
        var font = c.TTF_OpenFont(ttfPath, 24);
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
    fn fromSDL(color: c.SDL_Color) Color {
        return Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
    fn toSDL(color: Color) c.SDL_Color {
        return c.SDL_Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
};

pub const WindowSize = struct {
    w: c_int,
    h: c_int,
};

pub const Key = enum(c_int){
    Left,
    Right,
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
    fn fromSDL(event: c.SDL_Event) Event {
        return switch (event.type) {
            c.SDL_QUIT => Event{ .Quit = {} },
            c.SDL_KEYDOWN => Event {.KeyDown = .{.key = switch(event.key.keysym.scancode) {
                .SDL_SCANCODE_LEFT => Key.Left,
                .SDL_SCANCODE_RIGHT => Key.Right,
                else => Key.Unknown,
            }}},
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
            .w = screenWidth,
            .h = screenHeight,
        };
    }
};

pub const TextSize = struct {
    w: c_int,
    h: c_int,
};
pub fn measureText(font: *const Font, text: [*c]const u8) !TextSize {
    var w: c_int = undefined;
    var h: c_int = undefined;
    if (c.TTF_SizeUTF8(font.sdlFont, text, &w, &h) < 0) return ttfError();
    return TextSize{ .w = w, .h = h };
}

pub fn renderText(window: *const Window, font: *const Font, color: Color, text: [*c]const u8, x: c_int, y: c_int, size: TextSize) !void {
    var surface = c.TTF_RenderUTF8_Solid(font.sdlFont, text, color.toSDL());
    defer c.SDL_FreeSurface(surface);
    var texture = c.SDL_CreateTextureFromSurface(window.sdlRenderer, surface);
    defer c.SDL_DestroyTexture(texture);
    var rect = c.SDL_Rect{
        .x = x,
        .y = y,
        .w = size.w,
        .h = size.h,
    };
    if (c.SDL_RenderCopy(window.sdlRenderer, texture, null, &rect) < 0) return sdlError();
}

pub const Rect = struct {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
    fn toSDL(rect: *const Rect) c.SDL_Rect {
        return c.SDL_Rect{
            .x = rect.x,
            .y = rect.y,
            .w = rect.w,
            .h = rect.h,
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
