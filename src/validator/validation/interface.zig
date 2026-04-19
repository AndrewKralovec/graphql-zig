const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateInterfaceDefinition(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateImplementsInterfaces(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}
