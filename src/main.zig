const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("SDL.h");
    @cInclude("SDL_ttf.h");
});

const std = @import("std");
const List = std.SinglyLinkedList;

const CodeLine = struct {
    code: []u8,
    height: ?u32, // update whenever height is calculated, such as when rendering text
};
const CodeList = List([]CodeLine);

pub const ImDataStore = struct {
    // data: Map(key: u128, value: *ImData)
    // get(key, default)
    // tick: finds any data that was not used last frame and deinits it
    //
    //eg: I don't remember the use case
    //
};

pub const ImGlobals = struct {
    // if(click) click = false // stopPropagation
};

const TextSize = struct {
    w: c_int,
    h: c_int,
};

pub fn measureText(font: *c.TTF_Font, text: [*c]const u8) !TextSize {
    var w: c_int = undefined;
    var h: c_int = undefined;
    if (c.TTF_SizeUTF8(font, text, &w, &h) < 0) return ttfError();
    return TextSize{ .w = w, .h = h };
}

pub fn renderText(renderer: *c.SDL_Renderer, font: *c.TTF_Font, color: c.SDL_Color, text: [*c]const u8, x: c_int, y: c_int, size: TextSize) !void {
    var surface = c.TTF_RenderUTF8_Solid(font, text, color);
    defer c.SDL_FreeSurface(surface);
    var texture = c.SDL_CreateTextureFromSurface(renderer, surface);
    defer c.SDL_DestroyTexture(texture);
    var rect = c.SDL_Rect{
        .x = x,
        .y = y,
        .w = size.w,
        .h = size.h,
    };
    if (c.SDL_RenderCopy(renderer, texture, null, &rect) < 0) return sdlError();
}

pub const App = struct {
    code: CodeList,
    scrollY: i32, // scrollX is only for individual parts of the UI, such as tables.
    fn init() App {
        return .{
            .code = CodeList.init(),
            .scrollY = 0,
        };
    }
    fn deinit(app: *App) void {}

    fn render(app: *App, renderer: *c.SDL_Renderer, font: *c.TTF_Font, color: c.SDL_Color) !void {
        // loop over app.code
        // check scroll value
        // if the line height hasn't been calculated OR recalculate all is set, calculate it
        // if the recalculation is above the screen, increase the scroll by that number
        // if click and mouse position is within the character, set the cursor either before or after
        // if it fits on screen, render it
        var screenWidth: c_int = 0;
        var screenHeight: c_int = 0;

        if (c.SDL_GetRendererOutputSize(renderer, &screenWidth, &screenHeight) < 0) return sdlError();

        var x: c_int = 0;
        var y: c_int = 0;
        var lineHeight: c_int = 10;
        for ([_](*const [1:0]u8){ "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", " ", "h", "e", "l", "l", "o", " ", "t", "h", "e", "r", "e", "\n", "h", "i", " ", "h", "i", " ", "h", "i", " ", "h", "i", " ", "h", "i", " ", "h", "i", " ", "h", "i", " ", "h", "i", " ", "h", "i" }) |char| {
            if (char[0] == '\n') {
                x = 0;
                y += lineHeight;
                lineHeight = 10;
            } else {
                var textSize = try measureText(font, char);
                if (x + textSize.w > screenWidth) {
                    x = 0;
                    y += lineHeight;
                    lineHeight = 10;
                }
                try renderText(renderer, font, color, char, x, y, textSize);
                x += textSize.w;
                if (lineHeight < textSize.h) lineHeight = textSize.h;
            }
        }
    }
};

const SDLErrors = error{
    SDLError,
    TTFError,
};

fn sdlError() SDLErrors {
    _ = c.printf("SDL Method Failed: %s\n", c.SDL_GetError());
    return SDLErrors.SDLError;
}

fn ttfError() SDLErrors {
    _ = c.printf("TTF Method Failed: %s\n", c.TTF_GetError());
    return SDLErrors.TTFError;
}

pub fn main() !void {
    const stdout = &std.io.getStdOut().outStream().stream;
    try stdout.print("Hello, {}!\n", .{"world"});

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) return sdlError();
    defer c.SDL_Quit();

    if (c.TTF_Init() < 0) return sdlError();
    defer c.TTF_Quit();

    var window = c.SDL_CreateWindow("hello_sdl2", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 480, c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE);
    if (window == null) return sdlError();
    defer c.SDL_DestroyWindow(window);
    var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED);
    if (renderer == null) return sdlError();
    defer c.SDL_DestroyRenderer(renderer);

    var font = c.TTF_OpenFont("font/FreeSans.ttf", 24);
    if (font == null) return ttfError();

    var appV = App.init();
    var app = &appV;

    var event: c.SDL_Event = undefined;
    // if in foreground, loop pollevent
    // if in background, waitevent
    while (c.SDL_WaitEvent(&event) != 0) {
        if (event.type == c.SDL_QUIT) {
            break;
        }
        if (event.type == c.SDL_MOUSEMOTION) {
            try stdout.print("MouseMotion: {}\n", .{event.motion});
        } else {
            try stdout.print("Event: {}\n", .{event.type});
        }

        if (c.SDL_RenderClear(renderer) < 0) return sdlError();
        try app.render(renderer.?, font.?, c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        c.SDL_RenderPresent(renderer);
    }

    try stdout.print("Quitting!\n", .{});
}
