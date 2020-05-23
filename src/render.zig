pub const renderer = @import("build_options").renderer;

pub usingnamespace switch (renderer) {
    .sdl => @import("./renderers/sdl.zig"),
    .raylib => @import("./renderers/raylib.zig"),
};
