const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-triangle",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.addIncludePath(b.path("external/glfw/include"));

    switch (target.result.os.tag) {
        .windows => {
            exe.addLibraryPath(b.path("external/glfw/lib-vc2022"));

            exe.addIncludePath(b.path("external/wgpu-native/wgpu-windows-x86_64-release"));
            exe.addLibraryPath(b.path("external/wgpu-native/wgpu-windows-x86_64-release"));

            exe.linkSystemLibrary("gdi32");
            exe.linkSystemLibrary("user32");
            exe.linkSystemLibrary("shell32");
            exe.linkSystemLibrary("advapi32");
            exe.linkSystemLibrary("opengl32");
            exe.linkSystemLibrary("ws2_32");
            exe.linkSystemLibrary("bcrypt");
            exe.linkSystemLibrary("userenv");
            exe.linkSystemLibrary("d3dcompiler");
        },
        .macos => {
            if (!std.mem.eql(u8, target.result.osArchName(), "aarch64")) {
                return error.UnsupportedTarget;
            }
            exe.addLibraryPath(b.path("external/glfw/lib-arm64"));
            exe.addIncludePath(b.path("external/wgpu-native/wgpu-macos-aarch64-release"));
            exe.addLibraryPath(b.path("external/wgpu-native/wgpu-macos-aarch64-release"));

            exe.linkSystemLibrary("objc");

            exe.linkFramework("Foundation");
            exe.linkFramework("CoreFoundation");
            exe.linkFramework("IOKit");
            exe.linkFramework("Metal");
            exe.linkFramework("Cocoa");
        },
        else => return error.UnsupportedTarget,
    }
    exe.linkSystemLibrary("glfw3");
    exe.linkSystemLibrary("wgpu_native");
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
