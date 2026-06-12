const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;

const max_walk_depth = 500;

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

const WalkError = error{RecursionLimitExceeded} || std.mem.Allocator.Error;

fn walkSelectionsWithDedupedFragments(
    exec_doc: *const ExecutableDocument,
    selection_set: ast.SelectionSetNode,
    used: *std.StringHashMap(void),
    seen_fragments: *std.StringHashMap(void),
    depth: usize,
) WalkError!void {
    if (depth >= max_walk_depth) return error.RecursionLimitExceeded;

    _ = exec_doc;
    _ = selection_set;
    _ = used;
    _ = seen_fragments;
    // TODO: add validation logic
}

pub fn validateUnusedVariables(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    operation: ast.OperationDefinitionNode,
) !void {
    const var_defs = operation.variable_definitions orelse return;
    if (var_defs.len == 0) return;

    // Start off by considering all variables unused: names are removed from this as we find them.
    var unused_vars = std.StringHashMap(void).init(diagnostics.allocator); // TODO: Pass an allocator
    defer unused_vars.deinit();

    _ = exec_doc;
    // TODO: add validation logic
}

pub fn validateVariableUsage(
    diagnostics: *DiagnosticList,
    var_usage: ast.InputValueDefinitionNode,
    var_defs: []const ast.VariableDefinitionNode,
    argument: ast.ArgumentNode,
) !void {
    _ = diagnostics;
    _ = var_usage;
    _ = var_defs;
    _ = argument;
    // TODO: check if argument value is a Variable
    // TODO: find the matching VariableDefinition by name
    // TODO: call isVariableUsageAllowed and push DisallowedVariableUsage diagnostic if not
}

fn isVariableUsageAllowed(
    variable_def: ast.VariableDefinitionNode,
    variable_usage: ast.InputValueDefinitionNode,
) bool {
    _ = variable_def;
    _ = variable_usage;
    // TODO: implement spec rule — https://spec.graphql.org/draft/#sec-All-Variable-Usages-Are-Allowed
    return true;
}
