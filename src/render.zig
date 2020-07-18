// pub const renderer = @import("build_options").renderer;
//
// pub usingnamespace switch (renderer) {
//     .sdl => @import("./renderers/sdl.zig"),
//     .raylib => @import("./renderers/raylib.zig"),
//     .skia => @import("./renderers/skia.zig"),
// };

pub usingnamespace @import("./renderers/sdl.zig"); // for zls
