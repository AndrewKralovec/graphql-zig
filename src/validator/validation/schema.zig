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
// Return a Duplicate Root Operation Type error in case of a duplicate name.
pub fn validateRootOperationDefinitions(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
) !void {
    _ = allocator;

    const SeenOp = struct { op_type: ast.OperationType, name: []const u8 };
    var seen: [3]SeenOp = undefined;
    var seen_count: usize = 0;

    const op_types = [_]ast.OperationType{ .Query, .Mutation, .Subscription };
    for (op_types) |op_type| {
        // Root Operation Named Type must be of Object Type.
        //
        // Return a Object Type error if it's any other type definition.
        const named_type = schema.rootOperation(op_type) orelse continue;
        const name = named_type.name.value;
        const type_def = schema.type_definitions.get(name) orelse {
            try diagnostics.push(.UndefinedDefinition);
            continue;
        };

        switch (type_def) {
            .ObjectTypeDefinition => {},
            else => try diagnostics.push(.RootOperationObjectType),
        }

        var is_dup = false;
        for (seen[0..seen_count]) |prev| {
            if (std.mem.eql(u8, prev.name, name)) {
                try diagnostics.push(.DuplicateRootOperationType);
                is_dup = true;
                break;
            }
        }
        if (!is_dup) {
            seen[seen_count] = .{ .op_type = op_type, .name = name };
            seen_count += 1;
        }
    }
}
