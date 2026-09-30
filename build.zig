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

    exe.use_llvm = true;
    exe.use_lld = true;

    const exe_check = b.addExecutable(.{
        .name = "GBC_emulator",
        .root_module = exe_module,
    });

    exe_check.use_llvm = true;
    exe_check.use_lld = true;

    // ------------------------ Dependencies ------------------------
    const zsdl3 = b.dependency("zsdl3", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zsdl3", zsdl3.module("zsdl3"));
    exe.root_module.linkSystemLibrary("SDL3", .{});
    // --------------------------------------------------------------

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
