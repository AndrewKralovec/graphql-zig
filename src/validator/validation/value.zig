const std = @import("std");
const ast = @import("../../graphql.zig").ast;
// const validator = @import("../../graphql.zig").validator;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;

fn unsupportedType() void {}

pub fn validateValues(
    diagnostics: *DiagnosticList,
    schema: ?*const Schema,
    ty: *ast.TypeNode,
    argument: ast.ArgumentNode,
    var_defs: []const ast.VariableDefinitionNode,
) !void {
    _ = diagnostics;
    _ = schema;
    _ = ty;
    _ = argument;
    _ = var_defs;
    // TODO: add validation logic
}

pub fn valueOfCorrectType(
    ctx: *DiagnosticList,
) !void {
    _ = ctx;
    // TODO: add validation logic
}
