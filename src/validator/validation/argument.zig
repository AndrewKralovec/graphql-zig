const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;

pub fn validateArguments(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    arguments: ?[]const ast.ArgumentNode,
) !void {
    const args = arguments orelse return;
    try checkUniqueArguments(
        allocator,
        diagnostics,
        args,
    );
}

fn checkUniqueArguments(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    args: []const ast.ArgumentNode,
) !void {
    var seen_args = std.StringHashMap(void).init(allocator);
    defer seen_args.deinit();

    for (args) |arg| {
        const name = arg.name.value;
        const entry = try seen_args.getOrPut(name);
        if (entry.found_existing) {
            try diagnostics.push(.UniqueArgumentName);
        }
    }
}
