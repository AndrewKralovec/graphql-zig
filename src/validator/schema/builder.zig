const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("./schema.zig").Schema;

pub fn buildSchema(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    document: ast.DocumentNode,
) !Schema {
    var schema = Schema.init(allocator);
    errdefer schema.deinit();

    for (document.definitions) |def| {
        switch (def) {
            .ExecutableDefinition => {
                try diagnostics.push(.NonExecutableDefinition);
            },
            .TypeSystemDefinition => |ts| switch (ts) {
                .SchemaDefinition => |schema_def| {
                    schema.setSchemaDefinition(schema_def);
                },
                .TypeDefinition => |type_def| {
                    const name = typeDefName(type_def);
                    const entry = try schema.type_definitions.getOrPut(name);
                    if (entry.found_existing) {
                        try diagnostics.push(.UniqueDefinition);
                    } else {
                        entry.value_ptr.* = type_def;
                    }
                },
                .DirectiveDefinition => |dir_def| {
                    const entry = try schema.directive_definitions.getOrPut(dir_def.name.value);
                    if (entry.found_existing) {
                        try diagnostics.push(.UniqueDefinition);
                    } else {
                        entry.value_ptr.* = dir_def;
                    }
                },
            },
            .TypeSystemExtension => {
                // TODO: apply type extensions (extend keyword)
            },
        }
    }

    return schema;
}

fn typeDefName(type_def: ast.TypeDefinitionNode) []const u8 {
    return switch (type_def) {
        .ScalarTypeDefinition => |n| n.name.value,
        .ObjectTypeDefinition => |n| n.name.value,
        .InterfaceTypeDefinition => |n| n.name.value,
        .UnionTypeDefinition => |n| n.name.value,
        .EnumTypeDefinition => |n| n.name.value,
        .InputObjectTypeDefinition => |n| n.name.value,
    };
}
