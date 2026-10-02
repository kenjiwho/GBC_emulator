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
    // integrate with vcpkg
    const vcpkg_triplet = switch (target.result.cpu.arch) {
        .x86_64 => "x64-windows",
        .x86 => "x86-windows",
        .arm => "arm-windows",
        .aarch64 => "arm64-windows",
        else => @panic("Unsupported architecture"),
    };
    const vcpkg_cmd = b.addSystemCommand(&.{
        "vcpkg",
        "install",
        "--triplet",
        vcpkg_triplet,
    });
    // add vcpkg.json as a file input
    vcpkg_cmd.addFileInput(b.path("vcpkg.json"));
    vcpkg_cmd.addArg("--x-install-root");
    // add output directory arg (vcpkg_installed will be inside .zig-cache)
    const vcpkg_out_dir = vcpkg_cmd.addOutputDirectoryArg("vcpkg_installed");

    const vcpkg_bin = vcpkg_out_dir.path(b, b.pathJoin(&.{ vcpkg_triplet, "bin" }));
    const vcpkg_lib = vcpkg_out_dir.path(b, b.pathJoin(&.{ vcpkg_triplet, "lib" }));
    const vcpkg_include = vcpkg_out_dir.path(b, b.pathJoin(&.{ vcpkg_triplet, "include" }));

    const zsdl3 = b.dependency("zsdl3", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zsdl3", zsdl3.module("zsdl3"));
    exe.root_module.addIncludePath(vcpkg_include);
    exe.root_module.addLibraryPath(vcpkg_lib);

    const install_sdl3 = b.addInstallBinFile(vcpkg_bin.path(b, "SDL3.dll"), "SDL3.dll");
    const install_sdl3_ttf = b.addInstallBinFile(vcpkg_bin.path(b, "SDL3_ttf.dll"), "SDL3_ttf.dll");

    // make this step depend on the vcpkg command
    install_sdl3.step.dependOn(&vcpkg_cmd.step);
    install_sdl3_ttf.step.dependOn(&vcpkg_cmd.step);
    // exe step depends on both
    exe.step.dependOn(&vcpkg_cmd.step);
    exe.step.dependOn(&install_sdl3.step);
    exe.step.dependOn(&install_sdl3_ttf.step);

    exe.root_module.linkSystemLibrary("SDL3", .{});
    exe.root_module.linkSystemLibrary("SDL3_ttf", .{});
}
