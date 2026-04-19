const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

fn walkSelections() void {
    // TODO: add validation logic
}

pub fn validateOperation(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateSubscription(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}
