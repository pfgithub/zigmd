const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");

    switch (@import("./render.zig").renderer) {
        .sdl => {
            @cInclude("SDL.h");
            @cInclude("SDL_ttf.h");
            @cInclude("fontconfig/fontconfig.h");
        },
        .raylib => {
            @cDefine("SUPPORT_EVENTS_WAITING", "");
            @cInclude("raylib.h");
            @cInclude("abi_workaround.h");
        },
    }

    @cInclude("tree_sitter/api.h");
});

pub usingnamespace c;
