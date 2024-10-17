const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const vtk_mod = b.addModule("vtk", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    vtk_mod.addImport("vaxis", vaxis_dep.module("vaxis"));

    const Example = enum {
        flexcolumn,
        flexrow,
        listview,
        playground,
        richtext,
        text,
    };
    const example_option = b.option(Example, "example", "Example to run (default: text_input)") orelse .text;
    const example_step = b.step("example", "Run example");
    const example = b.addExecutable(.{
        .name = "example",
        // future versions should use b.path, see zig PR #19597
        .root_source_file = b.path(
            b.fmt("examples/{s}.zig", .{@tagName(example_option)}),
        ),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));
    example.root_module.addImport("vtk", vtk_mod);

    const example_run = b.addRunArtifact(example);
    example_step.dependOn(&example_run.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
