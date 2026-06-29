const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const validateDirectives = @import("./directive.zig").validateDirectives;
const validateFieldDefinitions = @import("./field.zig").validateFieldDefinitions;
const BuiltInScalars = @import("../schema/validation.zig").BuiltInScalars;

pub fn validateInterfaceDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    iface_def: ast.InterfaceTypeDefinitionNode,
) !void {
    try validateDirectives(
        allocator,
        diagnostics,
        schema,
        iface_def.directives,
        .Interface,
        &[_]ast.VariableDefinitionNode{},
    );

    // Interface must not implement itself.
    //
    // Return Recursive Definition error.
    //
    // NOTE(@lrlna): we should also check for more sneaky cyclic references for interfaces like this, for example:
    //
    // interface Node implements Named & Node {
    //   id: ID!
    //   name: String
    // }
    //
    // interface Named implements Node & Named {
    //   id: ID!
    //   name: String
    // }
    // NOTE: cyclic references between two or more interfaces are not yet caught here.
    if (iface_def.interfaces) |interfaces| {
        for (interfaces) |iface_ref| {
            if (std.mem.eql(u8, iface_ref.name.value, iface_def.name.value)) {
                try diagnostics.push(.RecursiveInterfaceDefinition);
            }
        }
    }

    // Interface Type field validation.
    try validateFieldDefinitions(allocator, diagnostics, schema, builtin_scalars, iface_def.fields);

    // validate there is at least one field on the type
    // https://spec.graphql.org/draft/#sel-HAHbnBFBABABxB4a
    const fields = iface_def.fields orelse &[_]ast.FieldDefinitionNode{};
    if (fields.len == 0) {
        try diagnostics.push(.EmptyFieldSet);
    }

    // Implements Interfaces validation.
    try validateImplementsInterfaces(
        allocator,
        diagnostics,
        schema,
        iface_def.name.value,
        iface_def.interfaces,
    );

    // When defining an interface that implements another interface, the
    // implementing interface must define each field that is specified by
    // the implemented interface.
    //
    // Returns a Missing Field error.
    try validateMissingInterfaceFields(diagnostics, schema, iface_def.fields, iface_def.interfaces);

    // Validate that fields in the implementing type have return types that are
    // proper subtypes of the super-interface fields.
    try validateImplementationFieldTypes(
        allocator,
        diagnostics,
        schema,
        iface_def.name.value,
        iface_def.fields,
        iface_def.interfaces,
    );

    // Validate that fields in the implementing type have matching arguments
    // per the IsValidImplementation rule.
    try validateImplementationFieldArguments(
        allocator,
        diagnostics,
        schema,
        iface_def.name.value,
        iface_def.fields,
        iface_def.interfaces,
    );
}

pub fn validateImplementsInterfaces(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    implementor_name: []const u8,
    implements_interfaces: ?[]const ast.NamedTypeNode,
) !void {
    _ = allocator;
    _ = implementor_name;
    const interfaces = implements_interfaces orelse return;

    // Every named interface must resolve to an InterfaceTypeDefinition — UndefinedDefinition.
    for (interfaces) |iface_ref| {
        const is_interface = switch (schema.type_definitions.get(iface_ref.name.value) orelse {
            try diagnostics.push(.UndefinedDefinition);
            continue;
        }) {
            .InterfaceTypeDefinition => true,
            else => false,
        };
        if (!is_interface) {
            try diagnostics.push(.UndefinedDefinition);
        }
    }

    // Implements Interfaces must be defined.
    //
    // Returns Undefined Definition error.
    // E.g. if `T implements B` and `B implements A`, then `T` must list `implements A`.
    // Returns TransitiveImplementedInterfaces error.
    for (interfaces) |iface_ref| {
        const via_def = switch (schema.type_definitions.get(iface_ref.name.value) orelse continue) {
            .InterfaceTypeDefinition => |i| i,
            else => continue,
        };
        const transitive = via_def.interfaces orelse continue;
        for (transitive) |transitive_ref| {
            const already_listed = for (interfaces) |listed| {
                if (std.mem.eql(u8, listed.name.value, transitive_ref.name.value)) break true;
            } else false;
            if (!already_listed) {
                try diagnostics.push(.TransitiveImplementedInterfaces);
            }
        }
    }
}

fn validateMissingInterfaceFields(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    implementor_fields: ?[]const ast.FieldDefinitionNode,
    implements_interfaces: ?[]const ast.NamedTypeNode,
) !void {
    const interfaces = implements_interfaces orelse return;
    const impl_fields = implementor_fields orelse &[_]ast.FieldDefinitionNode{};

    for (interfaces) |iface_ref| {
        const interface_def = switch (schema.type_definitions.get(iface_ref.name.value) orelse continue) {
            .InterfaceTypeDefinition => |i| i,
            else => continue,
        };
        const iface_fields = interface_def.fields orelse continue;
        for (iface_fields) |iface_field| {
            const found = for (impl_fields) |f| {
                if (std.mem.eql(u8, f.name.value, iface_field.name.value)) break true;
            } else false;
            if (!found) {
                try diagnostics.push(.MissingInterfaceField);
            }
        }
    }
}

/// GraphQL spec: [IsValidImplementationFieldType](https://spec.graphql.org/draft/#IsValidImplementationFieldType())
pub fn isValidImplementationFieldType(
    schema: *const Schema,
    iface_type: *const ast.TypeNode,
    impl_type: *const ast.TypeNode,
) bool {
    switch (iface_type.*) {
        .NonNullType => |iface_nn| {
            // NonNull interface field requires NonNull implementation.
            const impl_nn = switch (impl_type.*) {
                .NonNullType => |nn| nn,
                else => return false,
            };
            return isValidImplementationFieldType(schema, iface_nn.type, impl_nn.type);
        },
        .NamedType => |iface_named| {
            // Nullable named: impl may be Named or NonNull(Named).
            const impl_named = switch (impl_type.*) {
                .NamedType => |n| n,
                .NonNullType => |nn| switch (nn.type.*) {
                    .NamedType => |n| n,
                    else => return false,
                },
                .ListType => return false,
            };
            if (std.mem.eql(u8, iface_named.name.value, impl_named.name.value)) return true;
            // TODO: schema.isSubtype(iface_named, impl_named) — requires union/abstract
            //       subtype tracking in Schema, which is not yet implemented.
            return false;
        },
        .ListType => |iface_list| {
            // Nullable list: impl may be List or NonNull(List); recurse on element type.
            const impl_item = switch (impl_type.*) {
                .ListType => |l| l.type,
                .NonNullType => |nn| switch (nn.type.*) {
                    .ListType => |l| l.type,
                    else => return false,
                },
                .NamedType => return false,
            };
            return isValidImplementationFieldType(schema, iface_list.type, impl_item);
        },
    }
}

/// Validates that every field on each implemented interface has a matching field
/// on the implementor with a covariant return type.
///
/// Called for both Object types and Interface types.
///
/// https://spec.graphql.org/draft/#IsValidImplementationFieldType()
pub fn validateImplementationFieldTypes(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    implementor_name: []const u8,
    implementor_fields: ?[]const ast.FieldDefinitionNode,
    implements_interfaces: ?[]const ast.NamedTypeNode,
) !void {
    _ = allocator;
    _ = implementor_name;
    const interfaces = implements_interfaces orelse return;
    const impl_fields = implementor_fields orelse return;

    for (interfaces) |iface_ref| {
        const interface_def = switch (schema.type_definitions.get(iface_ref.name.value) orelse continue) {
            .InterfaceTypeDefinition => |i| i,
            else => continue,
        };
        const iface_fields = interface_def.fields orelse continue;
        for (iface_fields) |iface_field| {
            const impl_field = blk: {
                for (impl_fields) |f| {
                    if (std.mem.eql(u8, f.name.value, iface_field.name.value)) break :blk f;
                }
                continue; // missing field is reported by validateMissingInterfaceFields
            };
            if (!isValidImplementationFieldType(schema, iface_field.type, impl_field.type)) {
                try diagnostics.push(.InvalidImplementationFieldType);
            }
        }
    }
}

/// GraphQL spec: [IsValidImplementation](https://spec.graphql.org/draft/#IsValidImplementation())
///
/// Validates that implementing field arguments satisfy the interface contract:
/// - Every argument on the interface field must exist on the implementing field with the same type
/// - Extra arguments on the implementing field must not be required
pub fn validateImplementationFieldArguments(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    implementor_name: []const u8,
    implementor_fields: ?[]const ast.FieldDefinitionNode,
    implements_interfaces: ?[]const ast.NamedTypeNode,
) !void {
    _ = allocator;
    _ = implementor_name;
    const interfaces = implements_interfaces orelse return;
    const impl_fields = implementor_fields orelse return;

    for (interfaces) |iface_ref| {
        const interface_def = switch (schema.type_definitions.get(iface_ref.name.value) orelse continue) {
            .InterfaceTypeDefinition => |i| i,
            else => continue,
        };
        const iface_fields = interface_def.fields orelse continue;
        for (iface_fields) |iface_field| {
            const impl_field = blk: {
                for (impl_fields) |f| {
                    if (std.mem.eql(u8, f.name.value, iface_field.name.value)) break :blk f;
                }
                continue; // missing field is reported elsewhere
            };

            const iface_args = iface_field.arguments orelse &[_]ast.InputValueDefinitionNode{};
            const impl_args = impl_field.arguments orelse &[_]ast.InputValueDefinitionNode{};

            // Every argument on the interface field must exist on the implementing field
            // with the same type (type is invariant for arguments).
            for (iface_args) |iface_arg| {
                const impl_arg: ?ast.InputValueDefinitionNode = for (impl_args) |a| {
                    if (std.mem.eql(u8, a.name.value, iface_arg.name.value)) break a;
                } else null;

                if (impl_arg == null) {
                    try diagnostics.push(.MissingInterfaceFieldArgument);
                } else if (!typeEql(iface_arg.type, impl_arg.?.type)) {
                    try diagnostics.push(.InvalidImplementationFieldArgumentType);
                }
            }

            // Extra arguments on the implementing field must not be required.
            for (impl_args) |impl_arg| {
                const in_interface = for (iface_args) |a| {
                    if (std.mem.eql(u8, a.name.value, impl_arg.name.value)) break true;
                } else false;
                if (!in_interface and impl_arg.isRequiredArgument()) {
                    try diagnostics.push(.ExtraRequiredImplementationFieldArgument);
                }
            }
        }
    }
}

/// Exact structural equality between two TypeNodes, comparing named type names at leaves.
/// Used for argument type invariance checking in interface implementation validation.
fn typeEql(a: *const ast.TypeNode, b: *const ast.TypeNode) bool {
    return switch (a.*) {
        .NamedType => |an| switch (b.*) {
            .NamedType => |bn| std.mem.eql(u8, an.name.value, bn.name.value),
            else => false,
        },
        .ListType => |al| switch (b.*) {
            .ListType => |bl| typeEql(al.type, bl.type),
            else => false,
        },
        .NonNullType => |an| switch (b.*) {
            .NonNullType => |bn| typeEql(an.type, bn.type),
            else => false,
        },
    };
}
