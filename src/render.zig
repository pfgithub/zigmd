pub const renderer: enum { sdl, raylib } = .sdl; // should be passed in by build somehow but there is nothing in builtin that allows that

pub usingnamespace switch (renderer) {
    .sdl => @import("./renderers/sdl.zig"),
    .raylib => @import("./renderers/raylib.zig"),
};
