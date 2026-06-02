const std = @import("std");
const ast = @import("../../graphql.zig").ast;

pub const Schema = struct {
    allocator: std.mem.Allocator,
    type_definitions: std.StringArrayHashMap(ast.TypeDefinitionNode),
    root_operations: [3]?ast.NamedTypeNode,

    pub fn init(allocator: std.mem.Allocator) Schema {
        return Schema{
            .allocator = allocator,
            .type_definitions = std.StringArrayHashMap(ast.TypeDefinitionNode).init(allocator),
            .root_operations = .{ null, null, null },
        };
    }

    pub fn deinit(self: *Schema) void {
        self.type_definitions.deinit();
    }

    /// Returns the name of the object type for the root operation with the given operation kind
    pub fn rootOperation(self: *const Schema, op_type: ast.OperationType) ?ast.NamedTypeNode {
        return self.root_operations[@intFromEnum(op_type)];
    }

    /// Returns the definition of a type’s explicit field or meta-field.
    pub fn typeField(
        self: *const Schema,
        named_type: ast.NamedTypeNode,
        field_name: []const u8,
    ) ?ast.FieldDefinitionNode {
        const type_def = self.type_definitions.get(named_type.name.value) orelse return null;
        const fields: ?[]const ast.FieldDefinitionNode = switch (type_def) {
            .ObjectTypeDefinition => |obj| obj.fields,
            .InterfaceTypeDefinition => |iface| iface.fields,
            else => null,
        };
        const field_list = fields orelse return null;
        for (field_list) |field| {
            if (std.mem.eql(u8, field.name.value, field_name)) {
                return field;
            }
        }
        return null;
    }

    pub fn setSchemaDefinition(self: *Schema, schema_def: ast.SchemaDefinitionNode) void {
        for (schema_def.operation_types) |op_type_def| {
            self.root_operations[@intFromEnum(op_type_def.operation)] = op_type_def.type;
        }
    }
};
