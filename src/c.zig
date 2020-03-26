const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("SDL.h");
    @cInclude("SDL_ttf.h");
    @cInclude("fontconfig/fontconfig.h");

    @cInclude("tree_sitter/api.h");
});

pub usingnamespace c;
