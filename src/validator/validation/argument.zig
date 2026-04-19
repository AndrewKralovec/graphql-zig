const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateArguments(ctx: *Validator, arguments: ?[]const ast.ArgumentNode) !void {
    // TODO: add validation logic
    _ = ctx;
    _ = arguments;
}
