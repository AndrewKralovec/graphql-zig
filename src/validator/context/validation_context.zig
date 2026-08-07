const std = @import("std");
const Schema = @import("../schema/schema.zig").Schema;
const ast = @import("../../graphql.zig").ast;

/// Names of types that implement a given interface, split by kind.
/// Mirrors apollo-rs `schema::Implementers`.
pub const Implementers = struct {
    /// Concrete object types that implement the interface.
    objects: std.StringHashMap(void),
    /// Interface types that implement the interface.
    interfaces: std.StringHashMap(void),

    pub fn deinit(self: *Implementers) void {
        self.objects.deinit();
        self.interfaces.deinit();
    }
};

pub const ImplementersMap = std.StringHashMap(Implementers);

/// Scan every Object and Interface type in the schema and build the reverse-lookup map.
/// Mirrors Schema::implementers_map() in apollo-rs.
fn buildImplementersMap(allocator: std.mem.Allocator, schema: *const Schema) !ImplementersMap {
    var map = ImplementersMap.init(allocator);
    errdefer {
        var it = map.valueIterator();
        while (it.next()) |v| v.deinit();
        map.deinit();
    }

    for (schema.type_definitions.values()) |type_def| {
        switch (type_def) {
            .ObjectTypeDefinition => |obj| {
                for (obj.interfaces orelse &[_]ast.NamedTypeNode{}) |iface| {
                    const gop = try map.getOrPut(iface.name.value);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = .{
                            .objects = std.StringHashMap(void).init(allocator),
                            .interfaces = std.StringHashMap(void).init(allocator),
                        };
                    }
                    try gop.value_ptr.objects.put(obj.name.value, {});
                }
            },
            .InterfaceTypeDefinition => |iface| {
                for (iface.interfaces orelse &[_]ast.NamedTypeNode{}) |implemented| {
                    const gop = try map.getOrPut(implemented.name.value);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = .{
                            .objects = std.StringHashMap(void).init(allocator),
                            .interfaces = std.StringHashMap(void).init(allocator),
                        };
                    }
                    try gop.value_ptr.interfaces.put(iface.name.value, {});
                }
            },
            else => {},
        }
    }

    return map;
}

/// Shared context with things that may be used throughout executable validation.
pub const ExecutableValidationContext = struct {
    allocator: std.mem.Allocator,
    /// When null, rules that require a schema to validate are disabled.
    inner_schema: ?*const Schema,
    /// Lazily built reverse-lookup map from interface name to its implementers.
    /// Null until first call to implementersMap().
    cached_implementers_map: ?ImplementersMap,

    pub fn init(
        allocator: std.mem.Allocator,
        s: ?*const Schema,
    ) ExecutableValidationContext {
        return ExecutableValidationContext{
            .allocator = allocator,
            .inner_schema = s,
            .cached_implementers_map = null,
        };
    }

    pub fn deinit(self: *ExecutableValidationContext) void {
        if (self.cached_implementers_map) |*m| {
            var it = m.valueIterator();
            while (it.next()) |v| v.deinit();
            m.deinit();
        }
    }

    /// Returns the schema to validate against, if any.
    pub fn schema(self: *const ExecutableValidationContext) ?*const Schema {
        return self.inner_schema;
    }

    /// Returns the cached implementers map, building it on first call.
    /// The returned pointer is stable for the lifetime of this context.
    pub fn implementersMap(self: *ExecutableValidationContext) !*const ImplementersMap {
        if (self.cached_implementers_map == null) {
            if (self.inner_schema) |s| {
                self.cached_implementers_map = try buildImplementersMap(self.allocator, s);
            } else {
                self.cached_implementers_map = ImplementersMap.init(self.allocator);
            }
        }
        if (self.cached_implementers_map) |*m| return m;
        unreachable;
    }

    /// Returns a context for operation validation.
    pub fn operationContext(
        self: *ExecutableValidationContext,
        variables: ?[]const ast.VariableDefinitionNode,
    ) OperationValidationContext {
        return OperationValidationContext.init(self.allocator, self, variables);
    }
};

/// Shared context when validating things inside an operation.
pub const OperationValidationContext = struct {
    allocator: std.mem.Allocator,
    /// Parent context. The cached implementers_map is shared between all operation contexts
    /// via this reference, matching the OnceLock pattern in apollo-rs.
    executable: *ExecutableValidationContext,
    /// The variables defined for this operation.
    variables: ?[]const ast.VariableDefinitionNode,
    validated_fragments: std.StringHashMap(void),

    pub fn init(
        allocator: std.mem.Allocator,
        executable: *ExecutableValidationContext,
        variables: ?[]const ast.VariableDefinitionNode,
    ) OperationValidationContext {
        return OperationValidationContext{
            .allocator = allocator,
            .executable = executable,
            .variables = variables,
            .validated_fragments = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *OperationValidationContext) void {
        self.validated_fragments.deinit();
    }

    pub fn schema(self: *const OperationValidationContext) ?*const Schema {
        return self.executable.schema();
    }

    /// Delegates to the parent ExecutableValidationContext so the map is shared
    /// across all operation contexts derived from the same executable context.
    pub fn implementersMap(self: *OperationValidationContext) !*const ImplementersMap {
        return self.executable.implementersMap();
    }
};
