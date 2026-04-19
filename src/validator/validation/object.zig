const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateObjectTypeDefinition(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}
