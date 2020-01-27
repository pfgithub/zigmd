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

        return Font {
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

        return Window {
            .sdlWindow = window.?,
            .sdlRenderer = renderer.?,
        };
    }
    pub fn deinit(window: *Window) void {
        c.SDL_DestroyRenderer(window.sdlRenderer);
        c.SDL_DestroyWindow(window.sdlWindow);
    }

    pub fn clear(window: *Window) !void {
        if (c.SDL_RenderClear(renderer) < 0) return sdlError();
    }
    pub fn present(window: *Window) void {
        c.SDL_RenderPresent(renderer);
    }
    pub fn getSize(window: *Window) !WindowSize {
        var screenWidth: c_int = undefined;
        var screenHeight: c_int = undefined;
        if (c.SDL_GetRendererOutputSize(window.sdlRenderer, &screenWidth, &screenHeight) < 0) return sdlError();
        return WindowSize {
            .w = screenWidth,
            .h = screenHeight,
        };
    }
};

pub const TextSize = struct {
    w: c_int,
    h: c_int,
};
pub fn measureText(font: *Font, text: [*c]const u8) !TextSize {
    var w: c_int = undefined;
    var h: c_int = undefined;
    if (c.TTF_SizeUTF8(font.sdlFont, text, &w, &h) < 0) return ttfError();
    return TextSize{ .w = w, .h = h };
}

pub fn renderText(window: *Window, font: *Font, color: Color, text: [*c]const u8, x: u32, y: u32, size: TextSize) !void {
    var surface = c.TTF_RenderUTF8_Solid(font.sdlFont, text, color);
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
