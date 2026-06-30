const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const validateDirectives = @import("./directive.zig").validateDirectives;

pub fn validateScalarDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    scalar_def: ast.ScalarTypeDefinitionNode,
) !void {
    // All built-in scalars must be omitted for brevity.
    if (isBuiltInScalar(scalar_def.name.value)) return;

    try validateDirectives(
        allocator,
        diagnostics,
        schema,
        scalar_def.directives,
        .Scalar,
        &[_]ast.VariableDefinitionNode{},
    );
}

// TODO: consolidate with the identical private helper in value.zig
fn isBuiltInScalar(name: []const u8) bool {
    return std.mem.eql(u8, name, "String") or
        std.mem.eql(u8, name, "Int") or
        std.mem.eql(u8, name, "Float") or
        std.mem.eql(u8, name, "Boolean") or
        std.mem.eql(u8, name, "ID");
}
