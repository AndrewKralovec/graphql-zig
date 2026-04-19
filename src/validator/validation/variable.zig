const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateVariableDefinitions(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

fn variablesInValue(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic

}
fn variablesInArguments(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

fn variablesInDirectives(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateUnusedVariables(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateVariableUsage(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

fn isVariableUsageAllowed() void {
    // TODO: add validation logic
}
