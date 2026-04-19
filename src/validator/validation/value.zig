const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

fn unsupportedType() void {}

pub fn validateValues(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn valueOfCorrectType(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}
