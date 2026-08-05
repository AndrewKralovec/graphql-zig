const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const introspection = @import("./introspection.zig");

pub const TypeFieldResult = union(enum) {
    found: ast.FieldDefinitionNode,
    no_such_type,
    no_such_field: ast.TypeDefinitionNode,
};

pub const Schema = struct {
    allocator: std.mem.Allocator,
    type_definitions: std.StringArrayHashMap(ast.TypeDefinitionNode),
    directive_definitions: std.StringArrayHashMap(ast.DirectiveDefinitionNode),
    root_operations: [3]?ast.NamedTypeNode,

    /// Maps type_name -> (field_name -> FieldDefinitionNode). Built once in buildSchema().
    /// Contains only explicit Object/Interface fields. Meta-fields are resolved lazily in typeField.
    field_index: std.StringArrayHashMap(std.StringArrayHashMap(ast.FieldDefinitionNode)),

    pub fn init(allocator: std.mem.Allocator) Schema {
        return Schema{
            .allocator = allocator,
            .type_definitions = std.StringArrayHashMap(ast.TypeDefinitionNode).init(allocator),
            .directive_definitions = std.StringArrayHashMap(ast.DirectiveDefinitionNode).init(allocator),
            .root_operations = .{ null, null, null },
            .field_index = std.StringArrayHashMap(std.StringArrayHashMap(ast.FieldDefinitionNode)).init(allocator),
        };
    }

    pub fn deinit(self: *Schema) void {
        self.type_definitions.deinit();
        self.directive_definitions.deinit();
        for (self.field_index.values()) |*inner| inner.deinit();
        self.field_index.deinit();
    }

    /// Returns the name of the object type for the root operation with the given operation kind
    pub fn rootOperation(self: *const Schema, op_type: ast.OperationType) ?ast.NamedTypeNode {
        return self.root_operations[@intFromEnum(op_type)];
    }

    /// Returns true if type_name is the query root operation type.
    pub fn isQueryRoot(self: *const Schema, type_name: []const u8) bool {
        const root = self.rootOperation(.Query) orelse return false;
        return std.mem.eql(u8, root.name.value, type_name);
    }

    /// Returns the definition of a type’s explicit field or meta-field.
    pub fn typeField(
        self: *const Schema,
        type_name: []const u8,
        field_name: []const u8,
    ) TypeFieldResult {
        const type_def = self
            .type_definitions
            .get(type_name) orelse return .no_such_type;

        // only obj and interface types have explicit fields in the index
        const explicit_field: ?ast.FieldDefinitionNode = switch (type_def) {
            .ObjectTypeDefinition, .InterfaceTypeDefinition => blk: {
                const m = self.field_index.get(type_name) orelse break :blk null;
                break :blk m.get(field_name);
            },
            else => null,
        };
        if (explicit_field) |def| return .{ .found = def };

        const meta = introspection.MetaFields.get();
        if (std.mem.eql(u8, field_name, "__typename")) {
            switch (type_def) {
                .ObjectTypeDefinition,
                .InterfaceTypeDefinition,
                .UnionTypeDefinition,
                => return .{ .found = meta.__typename },
                else => {},
            }
        }

        if (self.isQueryRoot(type_name)) {
            if (std.mem.eql(u8, field_name, "__schema")) return .{ .found = meta.__schema };
            if (std.mem.eql(u8, field_name, "__type")) return .{ .found = meta.__type };
        }

        return .{ .no_such_field = type_def };
    }

    pub fn setSchemaDefinition(self: *Schema, schema_def: ast.SchemaDefinitionNode) void {
        for (schema_def.operation_types) |op_type_def| {
            self.root_operations[@intFromEnum(op_type_def.operation)] = op_type_def.type;
        }
    }

    /// Returns whether `maybe_subtype` is a subtype of `abstract_type`, which means either:
    ///
    /// * `maybe_subtype` implements the interface `abstract_type`
    /// * `maybe_subtype` is a member of the union type `abstract_type`
    pub fn isSubtype(self: *const Schema, abstract_name: []const u8, concrete_name: []const u8) bool {
        const abstract_def = self.type_definitions.get(abstract_name) orelse return false;
        switch (abstract_def) {
            .InterfaceTypeDefinition => {
                const concrete_def = self.type_definitions.get(concrete_name) orelse return false;
                const ifaces: ?[]const ast.NamedTypeNode = switch (concrete_def) {
                    .ObjectTypeDefinition => |obj| obj.interfaces,
                    .InterfaceTypeDefinition => |iface| iface.interfaces,
                    else => return false,
                };
                for (ifaces orelse return false) |iface| {
                    if (std.mem.eql(u8, iface.name.value, abstract_name)) return true;
                }
                return false;
            },
            .UnionTypeDefinition => |union_def| {
                for (union_def.types orelse return false) |member| {
                    if (std.mem.eql(u8, member.name.value, concrete_name)) return true;
                }
                return false;
            },
            else => return false,
        }
    }

    /// Gets or creates the inner field map for the named type. Used by the builder.
    pub fn getOrPutFieldMap(self: *Schema, type_name: []const u8) !*std.StringArrayHashMap(ast.FieldDefinitionNode) {
        const entry = try self.field_index.getOrPut(type_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.StringArrayHashMap(ast.FieldDefinitionNode).init(self.allocator);
        }
        return entry.value_ptr;
    }
};
