const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

/// Given a type definition, find all the type names that can be used for fragment spreading.
///
/// Spec: https://spec.graphql.org/October2021/#GetPossibleTypes()
fn getPossibleTypes(
    allocator: std.mem.Allocator,
) !std.StringHashMap(void) {
    _ = allocator;
    // TODO: add validation logic
}

pub fn validateFragmentSpreadType(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateInlineFragment(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateFragmentSpread(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateFragmentDefinition(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}

fn validateFragmentCycles(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateFragmentTypeDefinitionCondition(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}

fn collectUsedFragments(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}

fn validateFragmentsUsed(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}
