const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const fmt = b.addFmt(&[_][]const u8{ "src", "build.zig" });

    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("zigmd", "src/main.zig");
    exe.setBuildMode(mode);

    // sdl
    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_ttf");
    exe.linkSystemLibrary("fontconfig");

    // tree-sitter
    exe.linkSystemLibrary("c++");
    exe.addIncludeDir("deps/build/tree-sitter/lib/include");
    exe.addObjectFile("deps/build/tree-sitter/lib/src/lib.o");
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
