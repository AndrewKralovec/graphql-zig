const std = @import("std");
const Schema = @import("../schema/schema.zig").Schema;
const ast = @import("../../graphql.zig").ast;

/// Shared context with things that may be used throughout executable validation.
pub const ExecutableValidationContext = struct {
    allocator: std.mem.Allocator,
    /// When null, rules that require a schema to validate are disabled.
    inner_schema: ?*const Schema,
    // TODO: Cache implementers_map for reuse across operations,

    pub fn init(
        allocator: std.mem.Allocator,
        s: ?*const Schema,
    ) ExecutableValidationContext {
        return ExecutableValidationContext{
            .allocator = allocator,
            .inner_schema = s,
        };
    }

    pub fn deinit(self: *ExecutableValidationContext) void {
        _ = self; // TODO: decide later
    }

    /// Returns the schema to validate against, if any.
    pub fn schema(self: *const ExecutableValidationContext) ?*const Schema {
        return self.inner_schema;
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
    /// Parent context. Using a reference so the `OnceLock` is shared between all operation
    /// contexts.
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
};
