const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("SDL.h");
});

const std = @import("std");
const List = std.SinglyLinkedList;

const CodeList = List([]u8);

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

    fn render(app: *App, screenSurface: *c.SDL_Renderer) void {
        // loop over app.code
        // check scroll value
        // if the line height hasn't been calculated, calculate it
        // if the recalculation is above the screen, increase the scroll
        // if it fits on screen, render it
    }
};

fn sdlError() !void {
    _ = c.printf("SDL_Init Failed: %s\n", c.SDL_GetError());
    return error.SDLError;
}

pub fn main() !void {
    const stdout = &std.io.getStdOut().outStream().stream;
    try stdout.print("Hello, {}!\n", .{"world"});

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) return sdlError();
    defer c.SDL_Quit();

    var window = c.SDL_CreateWindow("hello_sdl2", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 480, c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE);
    if (window == null) return sdlError();
    defer c.SDL_DestroyWindow(window);
    var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED);
    defer c.SDL_DestroyRenderer(renderer);

    var appV = App.init();
    var app = &appV;

    // var bitmapSurface = c.SDL_LoadBMP("img/hello.bmp");
    var bitmapSurface = c.SDL_LoadBMP_RW(c.SDL_RWFromFile("img/hello.bmp", "rb"), 1);
    var bitmapTex = c.SDL_CreateTextureFromSurface(renderer, bitmapSurface);
    defer c.SDL_DestroyTexture(bitmapTex);
    c.SDL_FreeSurface(bitmapSurface);

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
        if (c.SDL_RenderCopy(renderer, bitmapTex, null, null) < 0) return sdlError();
        c.SDL_RenderPresent(renderer);
    }

    try stdout.print("Quitting!\n", .{});
}
