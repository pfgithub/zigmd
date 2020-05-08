const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const fmt = b.addFmt(&[_][]const u8{ "src", "build.zig" });

    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("zigmd", "src/main.zig");
    exe.setBuildMode(mode);

    exe.linkLibC();

    const choice = b.option([]const u8, "render", "renderer <sdl|raylib>") orelse {
        std.debug.warn("Expected -Drender=<sdl|raylib>\n", .{});
        return;
    };
    const renderer = std.meta.stringToEnum(enum { sdl, raylib }, choice) orelse {
        std.debug.warn("Must be <sdl|raylib>, got <{}>.", .{choice});
        return;
    };

    switch (renderer) {
        .sdl => {
            // sdl
            exe.linkSystemLibrary("SDL2");
            exe.linkSystemLibrary("SDL2_ttf");
            exe.linkSystemLibrary("fontconfig");
        },
        .raylib => {
            exe.linkSystemLibrary("raylib");
        },
    }

    // tree-sitter
    if (mode == .ReleaseFast) {
        exe.addCSourceFile("deps/build/tree-sitter/lib/src/lib.c", &[_][]const u8{});
        exe.addIncludeDir("deps/build/tree-sitter/lib/src");
        exe.addIncludeDir("deps/build/tree-sitter/lib/include");
    } else {
        exe.addObjectFile("deps/build/tree-sitter/lib/src/lib.o");
    }

    exe.linkSystemLibrary("c++");
    exe.addIncludeDir("deps/build/tree-sitter/lib/include");
    exe.addCSourceFile("deps/build/tree-sitter-markdown/src/parser.c", &[_][]const u8{});
    exe.addObjectFile("deps/build/tree-sitter-markdown/src/scanner.o");
    exe.addCSourceFile("deps/build/tree-sitter-json/src/parser.c", &[_][]const u8{});

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    fmt.step.dependOn(&run_cmd.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&fmt.step);
}
