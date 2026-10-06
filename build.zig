const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });

    const exe = b.addExecutable(.{
        .name = "GBC_emulator",
        .root_module = exe_module,
    });

    const exe_check = b.addExecutable(.{
        .name = "GBC_emulator",
        .root_module = exe_module,
    });

    if (target.result.os.tag == .windows) {
        manage_dependencies_windows(b, target, optimize, exe);
        manage_dependencies_windows(b, target, optimize, exe_check);
    } else {
        manage_dependencies(b, target, optimize, exe);
        manage_dependencies(b, target, optimize, exe_check);
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    const check = b.step("check", "Check if foo compiles");
    check.dependOn(&exe_check.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

fn manage_dependencies(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, exe: *std.Build.Step.Compile) void {
    // prevent sframe relocation error
    exe.use_llvm = true;
    exe.use_lld = true;

    const zsdl3 = b.dependency("zsdl3", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zsdl3", zsdl3.module("zsdl3"));
    exe.root_module.linkSystemLibrary("SDL3", .{});
    exe.root_module.linkSystemLibrary("SDL3_ttf", .{});
}

fn manage_dependencies_windows(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, exe: *std.Build.Step.Compile) void {
    const zsdl3 = b.dependency("zsdl3", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zsdl3", zsdl3.module("zsdl3"));

    const sdl3_dep = b.dependency("sdl3_bin", .{});
    const sdl3_image_dep = b.dependency("sdl3_image_bin", .{});
    const sdl3_mixer_dep = b.dependency("sdl3_mixer_bin", .{});
    const sdl3_ttf_dep = b.dependency("sdl3_ttf_bin", .{});

    exe.root_module.addLibraryPath(sdl3_dep.path("."));
    exe.root_module.addLibraryPath(sdl3_image_dep.path("."));
    exe.root_module.addLibraryPath(sdl3_mixer_dep.path("."));
    exe.root_module.addLibraryPath(sdl3_ttf_dep.path("."));

    exe.root_module.linkSystemLibrary("SDL3", .{});
    exe.root_module.linkSystemLibrary("SDL3_ttf", .{});

    const install_sdl3 = b.addInstallBinFile(sdl3_dep.path("SDL3.dll"), "SDL3.dll");
    const install_ttf = b.addInstallBinFile(sdl3_ttf_dep.path("SDL3_ttf.dll"), "SDL3_ttf.dll");

    exe.step.dependOn(&install_sdl3.step);
    exe.step.dependOn(&install_ttf.step);
}
