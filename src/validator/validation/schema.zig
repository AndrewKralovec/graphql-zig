const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const validateDirectives = @import("./directive.zig").validateDirectives;

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

    try validateDirectives(
        allocator,
        diagnostics,
        schema,
        schema.schema_directives,
        .Schema,
        // schemas don't use variables
        &[_]ast.VariableDefinitionNode{},
    );
}

// The query, mutation, and subscription root types must all be different
// types if provided.
//
// Return a Duplicate Root Operation Type error in case of a duplicate name.
pub fn validateRootOperationDefinitions(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
) !void {
    _ = allocator;

    var seen: [3][]const u8 = undefined;
    var seen_count: usize = 0;

    for (schema.iterRootOperations().slice()) |op| {
        const name = op.named_type.name.value;

        // Root Operation Named Type must be of Object Type.
        //
        // Return a Object Type error if it's any other type definition.
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
            if (std.mem.eql(u8, prev, name)) {
                try diagnostics.push(.DuplicateRootOperationType);
                is_dup = true;
                break;
            }
        }
        if (!is_dup) {
            seen[seen_count] = name;
            seen_count += 1;
        }
    }
}
