const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const validateDirectives = @import("./directive.zig").validateDirectives;
const validateTypeSystemName = @import("../schema/validation.zig").validateTypeSystemName;

pub fn validateEnumDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    enum_def: ast.EnumTypeDefinitionNode,
) !void {
    try validateDirectives(
        allocator,
        diagnostics,
        schema,
        enum_def.directives,
        .Enum,
        &[_]ast.VariableDefinitionNode{},
    );

    const values = enum_def.values orelse &[_]ast.EnumValueDefinitionNode{};
    for (values) |enum_val| {
        try validateEnumValue(allocator, diagnostics, schema, enum_val);
    }

    // validate there is at least one enum value on the enum type
    // https://spec.graphql.org/draft/#sel-DAHfFVFBAAEXBAAh7S
    if (values.len == 0) {
        try diagnostics.push(.EmptyValueSet);
    }
}

fn validateEnumValue(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    enum_val: ast.EnumValueDefinitionNode,
) !void {
    try validateTypeSystemName(
        diagnostics,
        enum_val.name,
        "an enum value",
    );
    try validateDirectives(
        allocator,
        diagnostics,
        schema,
        enum_val.directives,
        .EnumValue,
        &[_]ast.VariableDefinitionNode{},
    );
}
