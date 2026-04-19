const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateSchemaDefinition(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateRootOperationDefinitions(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}
