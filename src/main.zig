const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("SDL.h");
});

const std = @import("std");

pub fn main() !void {
    const stdout = &std.io.getStdOut().outStream().stream;
    try stdout.print("Hello, {}!\n", .{"world"});

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) return error.SDLInitFailed;
    defer c.SDL_Quit();

    var window = c.SDL_CreateWindow("hello_sdl2", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 480, c.SDL_WINDOW_SHOWN);
    if (window == null) return error.SDLWindowCreateFailed;
    defer c.SDL_DestroyWindow(window);
    var screenSurface = c.SDL_GetWindowSurface(window);

    _ = c.SDL_FillRect(screenSurface, null, c.SDL_MapRGB(screenSurface.*.format, 0xFF, 0xFF, 0xFF));
    _ = c.SDL_UpdateWindowSurface(window);
    c.SDL_Delay(2000);
    c.SDL_DestroyWindow(window);
}
