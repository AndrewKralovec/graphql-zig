const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;

pub fn validateSchemaDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
) !void {
    // A GraphQL schema must have a Query root operation.
    if (schema.rootOperation(.Query) == null) {
        try diagnostics.push(.QueryRootOperationType);
    }

    try validateRootOperationDefinitions(allocator, diagnostics, schema);

    // TODO: validate directives applied to the schema definition itself.
    // Requires extending Schema to store the original SchemaDefinitionNode
    // (currently only root_operations are extracted by setSchemaDefinition).
    // When added, call:
    //   validateDirectives(allocator, diagnostics, schema, schema_def.directives,
    //                      .Schema, &[_]ast.VariableDefinitionNode{})
}

// All root operations in a schema definition must be unique.
//
// Return a Unique Operation Definition error in case of a duplicate name.
pub fn validateRootOperationDefinitions(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
) !void {
    _ = allocator;

    const op_types = [_]ast.OperationType{ .Query, .Mutation, .Subscription };
    for (op_types) |op_type| {
        const named_type = schema.rootOperation(op_type) orelse continue;

        const type_def = schema.type_definitions.get(named_type.name.value) orelse {
            // Root operation references a type that does not exist.
            try diagnostics.push(.UndefinedDefinition);
            continue;
        };

        // Root Operation Named Type must be of Object Type.
        //
        // Return a Object Type error if it's any other type definition.
        switch (type_def) {
            .ObjectTypeDefinition => {}, // valid root operations must be Object types
            else => {
                try diagnostics.push(.RootOperationObjectType);
            },
        }
    }
}
