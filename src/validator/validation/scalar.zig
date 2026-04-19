const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateScalarDefinition(ctx: *Validator, scalar_def: ast.ScalarTypeDefinitionNode) anyerror!void {
    _ = ctx;
    _ = scalar_def;
    // TODO: add validation logic
}
