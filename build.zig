const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-game",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(b.path("external/glfw/include"));
    exe.addLibraryPath(b.path("external/glfw/lib-vc2022"));
    exe.linkSystemLibrary("glfw3");

    exe.addIncludePath(b.path("external/wgpu-native/"));
    exe.addLibraryPath(b.path("external/wgpu-native/"));
    exe.linkSystemLibrary("wgpu_native");

    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("shell32");
    exe.linkSystemLibrary("advapi32");
    exe.linkSystemLibrary("opengl32");
    exe.linkSystemLibrary("ws2_32");
    exe.linkSystemLibrary("bcrypt");
    exe.linkSystemLibrary("userenv");
    exe.linkSystemLibrary("d3dcompiler");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
