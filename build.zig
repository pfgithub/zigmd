const std = @import("std");
const Builder = std.build.Builder;

pub const Renderer = enum { sdl, raylib };

pub fn addBuildOptions(b: *Builder, renderer: Renderer, mode: var, exe: var) void {
    exe.linkLibC();

    switch (renderer) {
        .sdl => {
            // sdl
            exe.linkSystemLibrary("SDL2");
            exe.linkSystemLibrary("SDL2_ttf");
            exe.linkSystemLibrary("fontconfig");
        },
        .raylib => {
            // raylib
            exe.linkSystemLibrary("raylib");
            exe.addIncludeDir("src/renderers/raylib");
            exe.addCSourceFile("src/renderers/raylib/abi_workaround.c", &[_][]const u8{});
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
}

pub fn build(b: *Builder) void {
    const fmt = b.addFmt(&[_][]const u8{ "src", "build.zig" });

    const choice = b.option([]const u8, "render", "renderer <sdl|raylib>") orelse "sdl";
    const renderer = std.meta.stringToEnum(Renderer, choice) orelse {
        std.debug.warn("Must be <sdl|raylib>, got <{}>.", .{choice});
        return;
    };

    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zigmd", "src/main.zig");
    exe.setBuildMode(mode);
    addBuildOptions(b, renderer, mode, exe);
    exe.install();

    const testt = b.addTest("src/main.zig");
    addBuildOptions(b, renderer, mode, testt);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const fmt_step = b.step("fmt", "Format the code");
    fmt_step.dependOn(&fmt.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&fmt.step);
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Test the app");
    test_step.dependOn(&fmt.step);
    test_step.dependOn(&testt.step);
}
