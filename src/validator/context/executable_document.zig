const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;

/// A processed executable document with indexed operations and fragments.
pub const ExecutableDocument = struct {
    allocator: std.mem.Allocator,
    operations: OperationMap,
    fragments: std.StringArrayHashMap(ast.FragmentDefinitionNode),

    pub fn fromDocument(
        allocator: std.mem.Allocator,
        diagnostics: *DiagnosticList,
        document: ast.DocumentNode,
    ) !ExecutableDocument {
        var operations = OperationMap.init(allocator);
        errdefer operations.deinit();
        var fragments = std.StringArrayHashMap(ast.FragmentDefinitionNode).init(allocator);
        errdefer fragments.deinit();

        for (document.definitions) |def| {
            switch (def) {
                .ExecutableDefinition => |ex| switch (ex) {
                    .OperationDefinition => |op| {
                        if (op.name) |name| {
                            const result = try operations.named.getOrPut(name.value);
                            if (!result.found_existing) {
                                result.value_ptr.* = op;
                            } else {
                                try diagnostics.push(.UniqueOperation);
                            }
                        } else {
                            if (operations.anonymous == null) {
                                operations.anonymous = op;
                            } else {
                                try diagnostics.push(.LoneAnonymousOperation);
                            }
                        }
                    },
                    .FragmentDefinition => |frag| {
                        const result = try fragments.getOrPut(frag.name.value);
                        if (!result.found_existing) {
                            result.value_ptr.* = frag;
                        }
                    },
                },
                .TypeSystemDefinition, .TypeSystemExtension => {},
            }
        }

        return ExecutableDocument{
            .allocator = allocator,
            .operations = operations,
            .fragments = fragments,
        };
    }

    pub fn getFragment(self: *const ExecutableDocument, name: []const u8) ?ast.FragmentDefinitionNode {
        return self.fragments.get(name);
    }

    pub fn deinit(self: *ExecutableDocument) void {
        self.operations.deinit();
        self.fragments.deinit();
    }
};

/// Indexed collection of operation definitions.
/// Separates anonymous operations from named ones
pub const OperationMap = struct {
    anonymous: ?ast.OperationDefinitionNode,
    named: std.StringArrayHashMap(ast.OperationDefinitionNode),

    pub fn init(allocator: std.mem.Allocator) OperationMap {
        return OperationMap{
            .anonymous = null,
            .named = std.StringArrayHashMap(ast.OperationDefinitionNode).init(allocator),
        };
    }

    pub fn deinit(self: *OperationMap) void {
        self.named.deinit();
    }
};
