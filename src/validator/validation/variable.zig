const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const Validator = @import("../validator.zig").Validator;

pub fn validateVariableDefinitions(
    ctx: *DiagnosticList,
    schema: ?*const Schema,
    variable_definitions: []const ast.VariableDefinitionNode,
) !void {
    _ = ctx;
    _ = schema;
    _ = variable_definitions;
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
    validator: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    operation: ast.OperationDefinitionNode,
) !void {
    _ = validator;
    _ = exec_doc;
    _ = operation;
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
