const std = @import("std");
const graphql = @import("graphql");

const warmup_ns: u64 = 100_000_000;
const calibrate_target_ns: u64 = 200_000_000;
const calibrate_max_iters: u64 = 10_000_000;
const num_samples: usize = 5;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("graphql Benchmarks\n", .{});
    try stdout.print("==================\n\n", .{});

    for (fixtures) |fixture| {
        try runBench("lexer", fixture, benchLexer, stdout);
        try runBench("parser", fixture, benchParser, stdout);
    }
}

//
// Fixtures
//

const Fixture = struct {
    name: []const u8,
    source: []const u8,
};

const fixtures = [_]Fixture{
    .{ .name = "tiny", .source = @embedFile("fixtures/tiny.graphql") },
    .{ .name = "simple", .source = @embedFile("fixtures/simple.graphql") },
    .{ .name = "medium", .source = @embedFile("fixtures/medium.graphql") },
    .{ .name = "complex", .source = @embedFile("fixtures/complex.graphql") },
    .{ .name = "schema_sdl", .source = @embedFile("fixtures/schema_sdl.graphql") },
};

//
// Bench functions
//

fn benchLexer(allocator: std.mem.Allocator, source: []const u8) anyerror!void {
    _ = try graphql.lexer.tokenize(allocator, source);
}

fn benchParser(allocator: std.mem.Allocator, source: []const u8) anyerror!void {
    _ = try graphql.parser.parse(allocator, source);
}

fn measureIters(
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
    comptime func: fn (std.mem.Allocator, []const u8) anyerror!void,
    iters: u64,
) !u64 {
    var timer = try std.time.Timer.start();
    for (0..iters) |_| {
        _ = arena.reset(.retain_capacity);
        try func(arena.allocator(), source);
    }
    return timer.read();
}

fn calibrate(
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
    comptime func: fn (std.mem.Allocator, []const u8) anyerror!void,
) !u64 {
    var iters: u64 = 1;

    while (true) {
        const elapsed = try measureIters(arena, source, func, iters);
        if (elapsed >= calibrate_target_ns) return iters;

        if (elapsed < 1_000) {
            iters *|= 8; // saturating multiply for very fast operations
        } else {
            // scale so the next run lands near calibrate_target_ns
            const scale = @max(calibrate_target_ns / elapsed, 2);
            iters *|= scale;
        }

        if (iters > calibrate_max_iters) return calibrate_max_iters;
    }
}

fn runBench(
    label: []const u8,
    fixture: Fixture,
    comptime func: fn (std.mem.Allocator, []const u8) anyerror!void,
    writer: anytype,
) !void {
    const source = fixture.source;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // warm until warmup_ns elapsed to prime allocator pages and instruction cache
    var warmup_timer = try std.time.Timer.start();
    while (warmup_timer.read() < warmup_ns) {
        _ = arena.reset(.retain_capacity);
        try func(arena.allocator(), source);
    }

    const iters = try calibrate(&arena, source, func);

    var samples: [num_samples]f64 = undefined;
    for (&samples) |*s| {
        const ns = try measureIters(&arena, source, func, iters);
        s.* = @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(iters));
    }

    var sum: f64 = 0;
    for (samples) |s| sum += s;
    const mean = sum / @as(f64, @floatFromInt(num_samples));

    // multi sample approach see https://bheisler.github.io/criterion.rs/book/analysis.html
    var variance: f64 = 0;
    for (samples) |s| {
        const d = s - mean;
        variance += d * d;
    }
    const stddev = std.math.sqrt(variance / @as(f64, @floatFromInt(num_samples - 1)));

    const mean_ns: u64 = @intFromFloat(mean);
    const stddev_ns: u64 = @intFromFloat(stddev);
    const mops: f64 = 1_000.0 / mean;
    const mbs: f64 = (1_000_000_000.0 / mean) * @as(f64, @floatFromInt(source.len)) / 1_000_000.0;

    try writer.print(
        "Benchmark/{s}/{s}\t{d}\t{d} ns/op\t±{d} ns\t{d:.3} Mop/s\t{d:.2} MB/s\t{d} B\n",
        .{ label, fixture.name, iters, mean_ns, stddev_ns, mops, mbs, source.len },
    );
}
