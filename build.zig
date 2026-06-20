const std = @import("std");

pub fn build(b: *std.Build) void {
    // Set the target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Define the build options
    const lib = b.addStaticLibrary(.{
        .name = "graphql",
        .root_source_file = b.path("src/graphql.zig"),
        .target = target,
        .optimize = optimize,
        .version = .{
            .major = 0,
            .minor = 2,
            .patch = 0,
        },
    });

    // Define options for the `build_config` module
    const debug_mode = b.option(bool, "debug", "Enable debug mode") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "debug", debug_mode);

    // Attach options for the `build_config` module to the library
    lib.root_module.addOptions("build_config.zig", options);

    // Install the library
    b.installArtifact(lib);

    // Export the module so other projects can depend on it
    const module = b.addModule("graphql", .{
        .root_source_file = b.path("src/graphql.zig"),
    });
    module.addOptions("build_config.zig", options);

    // Add a test step
    const tests = b.addTest(.{
        .root_source_file = b.path("src/graphql.zig"),
    });
    tests.root_module.addOptions("build_config.zig", options);

    const test_step = b.step("test", "Run unit tests");
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    // always compiled ReleaseFast for bench results
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_source_file = b.path("bench/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_exe.root_module.addImport("graphql", module);

    const run_bench = b.addRunArtifact(bench_exe);
    if (b.args) |args| run_bench.addArgs(args);

    const bench_step = b.step("bench", "Run parser/lexer benchmarks");
    bench_step.dependOn(&run_bench.step);
}
