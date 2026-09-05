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

    var seen_schema_def = false;
    for (document.definitions) |def| {
        switch (def) {
            .ExecutableDefinition => {
                try diagnostics.push(.NonExecutableDefinition);
            },
            .TypeSystemDefinition => |ts| switch (ts) {
                .SchemaDefinition => |schema_def| {
                    if (seen_schema_def) {
                        try diagnostics.push(.UniqueDefinition);
                    } else {
                        seen_schema_def = true;
                        schema.setSchemaDefinition(schema_def);
                    }
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

    try buildFieldIndex(&schema, diagnostics, document);

    return schema;
}

fn buildFieldIndex(schema: *Schema, diagnostics: *DiagnosticList, document: ast.DocumentNode) !void {
    // NOTE: two passes ensure definition fields always precede extension fields in insertion order regardless of document order
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
                    for (list) |field| {
                        const entry = try map.getOrPut(field.name.value);
                        if (entry.found_existing) {
                            try diagnostics.push(.UniqueDefinition);
                        } else {
                            entry.value_ptr.* = field;
                        }
                    }
                }
            },
            .InterfaceTypeDefinition => |iface| {
                if (iface.fields) |list| {
                    const map = try schema.getOrPutFieldMap(iface.name.value);
                    for (list) |field| {
                        const entry = try map.getOrPut(field.name.value);
                        if (entry.found_existing) {
                            try diagnostics.push(.UniqueDefinition);
                        } else {
                            entry.value_ptr.* = field;
                        }
                    }
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
                const existing = schema.type_definitions.get(ext.name.value) orelse {
                    try diagnostics.push(.UndefinedDefinition);
                    continue;
                };
                if (existing != .ObjectTypeDefinition) {
                    try diagnostics.push(.TypeExtensionKindMismatch);
                    continue;
                }
                if (ext.fields) |list| {
                    const map = try schema.getOrPutFieldMap(ext.name.value);
                    for (list) |field| {
                        const entry = try map.getOrPut(field.name.value);
                        if (entry.found_existing) {
                            try diagnostics.push(.UniqueDefinition);
                        } else {
                            entry.value_ptr.* = field;
                        }
                    }
                }
            },
            .InterfaceTypeExtension => |ext| {
                const existing = schema.type_definitions.get(ext.name.value) orelse {
                    try diagnostics.push(.UndefinedDefinition);
                    continue;
                };
                if (existing != .InterfaceTypeDefinition) {
                    try diagnostics.push(.TypeExtensionKindMismatch);
                    continue;
                }
                if (ext.fields) |list| {
                    const map = try schema.getOrPutFieldMap(ext.name.value);
                    for (list) |field| {
                        const entry = try map.getOrPut(field.name.value);
                        if (entry.found_existing) {
                            try diagnostics.push(.UniqueDefinition);
                        } else {
                            entry.value_ptr.* = field;
                        }
                    }
                }
            },
            inline else => |ext| {
                const existing = schema.type_definitions.get(ext.name.value) orelse {
                    try diagnostics.push(.UndefinedDefinition);
                    continue;
                };
                if (!extensionKindMatchesDef(type_ext, existing)) {
                    try diagnostics.push(.TypeExtensionKindMismatch);
                }
            },
        }
    }
}

fn extensionKindMatchesDef(ext: ast.TypeExtensionNode, def: ast.TypeDefinitionNode) bool {
    return switch (ext) {
        .ScalarTypeExtension => def == .ScalarTypeDefinition,
        .ObjectTypeExtension => def == .ObjectTypeDefinition,
        .InterfaceTypeExtension => def == .InterfaceTypeDefinition,
        .UnionTypeExtension => def == .UnionTypeDefinition,
        .EnumTypeExtension => def == .EnumTypeDefinition,
        .InputObjectTypeExtension => def == .InputObjectTypeDefinition,
    };
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
