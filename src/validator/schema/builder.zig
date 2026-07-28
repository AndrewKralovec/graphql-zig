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
                // Extensions are processed in buildFieldIndex below.
            },
        }
    }

    try buildFieldIndex(&schema, document);

    return schema;
}

// TODO: review the repeat passes.
fn buildFieldIndex(schema: *Schema, document: ast.DocumentNode) !void {
    // Pass 1: base types (object and interface)
    for (document.definitions) |def| {
        const type_def = switch (def) {
            .TypeSystemDefinition => |ts| switch (ts) {
                .TypeDefinition => |td| td,
                else => continue,
            },
            else => continue,
        };
        switch (type_def) {
            .ObjectTypeDefinition => |obj| {
                if (obj.fields) |list| {
                    const map = try schema.getOrPutFieldMap(obj.name.value);
                    for (list) |field| try map.put(field.name.value, field);
                }
            },
            .InterfaceTypeDefinition => |iface| {
                if (iface.fields) |list| {
                    const map = try schema.getOrPutFieldMap(iface.name.value);
                    for (list) |field| try map.put(field.name.value, field);
                }
            },
            else => {},
        }
    }

    // Pass 2: extensions(object and interface)
    for (document.definitions) |def| {
        const type_ext = switch (def) {
            .TypeSystemExtension => |ts| switch (ts) {
                .TypeExtension => |te| te,
                else => continue,
            },
            else => continue,
        };
        switch (type_ext) {
            .ObjectTypeExtension => |ext| {
                if (ext.fields) |list| {
                    const map = try schema.getOrPutFieldMap(ext.name.value);
                    for (list) |field| try map.put(field.name.value, field);
                }
            },
            .InterfaceTypeExtension => |ext| {
                if (ext.fields) |list| {
                    const map = try schema.getOrPutFieldMap(ext.name.value);
                    for (list) |field| try map.put(field.name.value, field);
                }
            },
            else => {},
        }
    }

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
