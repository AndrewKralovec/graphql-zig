const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;

const validateScalarDefinition = @import("../validation/scalar.zig").validateScalarDefinition;
const validateObjectTypeDefinition = @import("../validation/object.zig").validateObjectTypeDefinition;
const validateInterfaceDefinition = @import("../validation/interface.zig").validateInterfaceDefinition;
const validateUnionDefinition = @import("../validation/union.zig").validateUnionDefinition;
const validateEnumDefinition = @import("../validation/enum.zig").validateEnumDefinition;
const validateInputObjectDefinition = @import("../validation/input.zig").validateInputObjectDefinition;
const validateDirectiveDefinitions = @import("../validation/directive.zig").validateDirectiveDefinitions;

pub fn validateSchema(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
) !void {
    var builtin_scalars = BuiltInScalars.init(allocator);
    defer builtin_scalars.deinit();

    var it = schema.type_definitions.iterator();
    while (it.next()) |entry| {
        const type_def = entry.value_ptr.*;
        try validateTypeSystemName(diagnostics, typeDefNameNode(type_def), "a type");
        switch (type_def) {
            .ScalarTypeDefinition => |n| try validateScalarDefinition(allocator, diagnostics, schema, n),
            .ObjectTypeDefinition => |n| try validateObjectTypeDefinition(allocator, diagnostics, schema, &builtin_scalars, n),
            .InterfaceTypeDefinition => |n| try validateInterfaceDefinition(allocator, diagnostics, schema, &builtin_scalars, n),
            .UnionTypeDefinition => |n| try validateUnionDefinition(allocator, diagnostics, schema, n),
            .EnumTypeDefinition => |n| try validateEnumDefinition(allocator, diagnostics, schema, n),
            .InputObjectTypeDefinition => |n| try validateInputObjectDefinition(allocator, diagnostics, schema, &builtin_scalars, n),
        }
    }

    try validateDirectiveDefinitions(diagnostics, schema);
}

/// Validate type system names according to GraphQL spec
/// https://spec.graphql.org/draft/#sec-Names.Reserved-Names
pub fn validateTypeSystemName(
    diagnostics: *DiagnosticList,
    name: ast.NameNode,
    describe: []const u8,
) !void {
    _ = describe;
    if (std.mem.startsWith(u8, name.value, "__")) {
        try diagnostics.push(.ReservedName);
    }
}

fn typeDefNameNode(type_def: ast.TypeDefinitionNode) ast.NameNode {
    return switch (type_def) {
        .ScalarTypeDefinition => |n| n.name,
        .ObjectTypeDefinition => |n| n.name,
        .InterfaceTypeDefinition => |n| n.name,
        .UnionTypeDefinition => |n| n.name,
        .EnumTypeDefinition => |n| n.name,
        .InputObjectTypeDefinition => |n| n.name,
    };
}

/// Keeps track of usage of built-in scalars in a schema to determine which definitions
/// should be removed or added.
///
/// https://spec.graphql.org/draft/#sec-Scalars.Built-in-Scalars
pub const BuiltInScalars = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BuiltInScalars {
        return BuiltInScalars{ .allocator = allocator };
    }

    pub fn deinit(self: *BuiltInScalars) void {
        _ = self;
    }

    /// Returns true if the given name is a built-in scalar type.
    pub fn recordTypeRef(self: *BuiltInScalars, schema: *const Schema, name: []const u8) bool {
        _ = self;
        _ = schema;
        const builtins = [_][]const u8{ "String", "Int", "Float", "Boolean", "ID" };
        for (builtins) |b| {
            if (std.mem.eql(u8, name, b)) return true;
        }
        return false;
    }
};
