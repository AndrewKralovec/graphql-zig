const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateInputObjectDefinition(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateArgumentDefinitions(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

fn validateInputValueDefinitions(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}
