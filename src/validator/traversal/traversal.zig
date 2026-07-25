const std = @import("std");

// Tracks a path of names visited during recursive cycle-detection traversal.
// Maps to apollo-rs RecursionStack + RecursionGuard pattern
pub const RecursionStack = struct {
    items: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator) RecursionStack {
        return .{ .items = std.ArrayList([]const u8).init(allocator) };
    }

    fn deinit(self: *RecursionStack) void {
        self.items.deinit();
    }

    fn withRoot(allocator: std.mem.Allocator, root: []const u8) !RecursionStack {
        var s = RecursionStack.init(allocator);
        try s.items.append(root);
        return s;
    }

    fn contains(self: *const RecursionStack, name: []const u8) bool {
        for (self.items.items) |n| {
            if (std.mem.eql(u8, n, name)) return true;
        }
        return false;
    }

    fn first(self: *const RecursionStack) ?[]const u8 {
        if (self.items.items.len == 0) return null;
        return self.items.items[0];
    }

    fn push(self: *RecursionStack, name: []const u8) !void {
        if (self.items.items.len >= 32) return error.DeeplyNestedType;
        try self.items.append(name);
    }

    fn pop(self: *RecursionStack) void {
        _ = self.items.pop();
    }
};
