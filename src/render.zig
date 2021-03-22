pub const renderer = @import("build_options").renderer;

pub usingnamespace @import("./renderers/common.zig");

pub usingnamespace switch (renderer) {
    .sdl => @import("./renderers/sdl.zig"),
    .raylib => @import("./renderers/raylib.zig"),
    .skia => @import("./renderers/skia.zig"),
    .sokol => @import("./renderers/sokol.zig"),
    .cairo => @import("./renderers/cairo.zig"),
};

// pub usingnamespace @import("./renderers/sdl.zig"); // for zls
