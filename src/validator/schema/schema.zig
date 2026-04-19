const std = @import("std");
const ast = @import("../../graphql.zig").ast;

pub const Schema = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Schema {
        return Schema{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Schema) void {
        _ = self;
    }
};
