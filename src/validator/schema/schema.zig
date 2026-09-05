const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const introspection = @import("./introspection.zig");

pub const Implementers = struct {
    objects: std.StringHashMap(void),
    interfaces: std.StringHashMap(void),

    pub fn deinit(self: *Implementers) void {
        self.objects.deinit();
        self.interfaces.deinit();
    }
};

pub const ImplementersMap = std.StringHashMap(Implementers);

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
    /// Directives applied to the `schema { ... }` block itself. Null when no
    /// explicit schema definition was present in the document.
    schema_directives: ?[]const ast.DirectiveNode,

    /// Maps type_name -> (field_name -> FieldDefinitionNode). Built once in buildSchema().
    /// Contains only explicit Object/Interface fields. Meta-fields are resolved lazily in typeField.
    field_index: std.StringArrayHashMap(std.StringArrayHashMap(ast.FieldDefinitionNode)),

    pub fn init(allocator: std.mem.Allocator) Schema {
        return Schema{
            .allocator = allocator,
            .type_definitions = std.StringArrayHashMap(ast.TypeDefinitionNode).init(allocator),
            .directive_definitions = std.StringArrayHashMap(ast.DirectiveDefinitionNode).init(allocator),
            .root_operations = .{ null, null, null },
            .schema_directives = null,
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

    pub fn iterRootOperations(self: *const Schema) std.BoundedArray(RootOperation, 3) {
        var ops = std.BoundedArray(RootOperation, 3){};
        for ([_]ast.OperationType{ .Query, .Mutation, .Subscription }) |op_type| {
            if (self.root_operations[@intFromEnum(op_type)]) |named_type| {
                ops.appendAssumeCapacity(.{ .op_type = op_type, .named_type = named_type });
            }
        }
        return ops;
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
        self.schema_directives = schema_def.directives;
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

    /// Returns the type with the given name, if it is a scalar type
    pub fn getScalar(self: *const Schema, name: []const u8) ?ast.ScalarTypeDefinitionNode {
        return switch (self.type_definitions.get(name) orelse return null) {
            .ScalarTypeDefinition => |n| n,
            else => null,
        };
    }

    /// Returns the type with the given name, if it is a object type
    pub fn getObject(self: *const Schema, name: []const u8) ?ast.ObjectTypeDefinitionNode {
        return switch (self.type_definitions.get(name) orelse return null) {
            .ObjectTypeDefinition => |n| n,
            else => null,
        };
    }

    /// Returns the type with the given name, if it is a interface type
    pub fn getInterface(self: *const Schema, name: []const u8) ?ast.InterfaceTypeDefinitionNode {
        return switch (self.type_definitions.get(name) orelse return null) {
            .InterfaceTypeDefinition => |n| n,
            else => null,
        };
    }

    /// Returns the type with the given name, if it is a union type
    pub fn getUnion(self: *const Schema, name: []const u8) ?ast.UnionTypeDefinitionNode {
        return switch (self.type_definitions.get(name) orelse return null) {
            .UnionTypeDefinition => |n| n,
            else => null,
        };
    }

    pub fn getEnum(self: *const Schema, name: []const u8) ?ast.EnumTypeDefinitionNode {
        return switch (self.type_definitions.get(name) orelse return null) {
            .EnumTypeDefinition => |n| n,
            else => null,
        };
    }

    /// Returns the type with the given name, if it is a enum type
    pub fn getInputObject(self: *const Schema, name: []const u8) ?ast.InputObjectTypeDefinitionNode {
        return switch (self.type_definitions.get(name) orelse return null) {
            .InputObjectTypeDefinition => |n| n,
            else => null,
        };
    }

    /// Returns true if a value of this type can be used as an input value.
    ///
    /// # Spec
    /// This implements spec function
    /// [`IsInputType(type)`](https://spec.graphql.org/draft/#IsInputType())
    pub fn isInputType(self: *const Schema, ty: *const ast.TypeNode) bool {
        const type_def = self.type_definitions.get(ty.innerNamedType().name.value) orelse return false;
        return type_def.isInputType();
    }

    /// Returns true if a value of this type can be used as an output value.
    ///
    /// # Spec
    /// This implements spec function
    /// [`IsOutputType(type)`](https://spec.graphql.org/draft/#IsOutputType())
    pub fn isOutputType(self: *const Schema, ty: *const ast.TypeNode) bool {
        const type_def = self.type_definitions.get(ty.innerNamedType().name.value) orelse return false;
        return type_def.isOutputType();
    }

    /// Returns a map of interface names to the types that implement them.
    pub fn implementersMap(self: *const Schema, allocator: std.mem.Allocator) !ImplementersMap {
        var map = ImplementersMap.init(allocator);
        errdefer {
            var it = map.valueIterator();
            while (it.next()) |v| v.deinit();
            map.deinit();
        }
        for (self.type_definitions.values()) |type_def| {
            switch (type_def) {
                .ObjectTypeDefinition => |obj| {
                    for (obj.interfaces orelse &[_]ast.NamedTypeNode{}) |iface| {
                        const gop = try map.getOrPut(iface.name.value);
                        if (!gop.found_existing) gop.value_ptr.* = .{
                            .objects = std.StringHashMap(void).init(allocator),
                            .interfaces = std.StringHashMap(void).init(allocator),
                        };
                        try gop.value_ptr.objects.put(obj.name.value, {});
                    }
                },
                .InterfaceTypeDefinition => |iface| {
                    for (iface.interfaces orelse &[_]ast.NamedTypeNode{}) |implemented| {
                        const gop = try map.getOrPut(implemented.name.value);
                        if (!gop.found_existing) gop.value_ptr.* = .{
                            .objects = std.StringHashMap(void).init(allocator),
                            .interfaces = std.StringHashMap(void).init(allocator),
                        };
                        try gop.value_ptr.interfaces.put(iface.name.value, {});
                    }
                },
                else => {},
            }
        }
        return map;
    }

    /// Gets or creates the inner field map for the named type. Used by the builder.
    pub fn getOrPutFieldMap(self: *Schema, type_name: []const u8) !*std.StringArrayHashMap(ast.FieldDefinitionNode) {
        const entry = try self.field_index.getOrPut(type_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.StringArrayHashMap(ast.FieldDefinitionNode).init(self.allocator);
        }
        return entry.value_ptr;
    }

    pub const RootOperation = struct {
        op_type: ast.OperationType,
        named_type: ast.NamedTypeNode,
    };
};
