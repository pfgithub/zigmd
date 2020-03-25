const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const fmt = b.addFmt(&[_][]const u8{ "src", "build.zig" });

    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("zigmd", "src/main.zig");
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_ttf");
    exe.linkSystemLibrary("fontconfig");
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(&fmt.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
