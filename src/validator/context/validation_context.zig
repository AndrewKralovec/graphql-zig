const std = @import("std");
const schema_mod = @import("../schema/schema.zig");
const Schema = schema_mod.Schema;
const ast = @import("../../graphql.zig").ast;

pub const Implementers = schema_mod.Implementers;
pub const ImplementersMap = schema_mod.ImplementersMap;

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
                self.cached_implementers_map = try s.implementersMap(self.allocator);
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
