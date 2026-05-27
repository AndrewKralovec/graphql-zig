const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;

const validateArguments = @import("./argument.zig").validateArguments;
const validateValues = @import("./value.zig").validateValues;
const validateVariableUsage = @import("./variable.zig").validateVariableUsage;

pub fn validateDirectiveDefinition(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    def: ast.DirectiveDefinitionNode,
) !void {
    _ = diagnostics;
    _ = schema;
    _ = def;
    // TODO: validate type system name: validateTypeSystemName(diagnostics, def.name, "a directive definition")
    // TODO: validate argument definitions: validateArgumentDefinitions(diagnostics, schema, def.arguments, DirectiveLocation.ArgumentDefinition)
    // TODO: A directive definition must not contain the use of a directive which
}

pub fn validateDirectiveDefinitions(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
) !void {
    _ = diagnostics;
    _ = schema;
    // TODO: iterate over schema.directive_definitions
    // TODO: call validateDirectiveDefinition() for each
}

// TODO: This is a big function: should probably not be generic over the iterator
// type
pub fn validateDirectives(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: ?*const Schema,
    // TODO: See if this should be a iterator like rust. dirs: impl Iterator<Item = &'dir Node<ast::Directive>>,
    directives: ?[]const ast.DirectiveNode,
    dir_loc: ast.DirectiveLocation,
    var_defs: []const ast.VariableDefinitionNode,
) !void {
    _ = var_defs;
    const dirs = directives orelse return;

    var seen_directives = std.StringHashMap(bool).init(allocator);
    defer seen_directives.deinit();

    for (dirs) |dir| {
        try validateArguments(
            allocator,
            diagnostics,
            dir.arguments,
        );
    }

    _ = schema;
    _ = dir_loc;
    _ = var_defs;
}
