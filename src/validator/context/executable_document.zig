const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;

/// A processed executable document with indexed operations and fragments.
pub const ExecutableDocument = struct {
    operations: OperationMap,
    fragments: std.StringArrayHashMap(ast.FragmentDefinitionNode),

    pub fn init(allocator: std.mem.Allocator) ExecutableDocument {
        return .{
            .operations = OperationMap.init(allocator),
            .fragments = std.StringArrayHashMap(ast.FragmentDefinitionNode).init(allocator),
        };
    }

    pub fn deinit(self: *ExecutableDocument) void {
        self.operations.deinit();
        self.fragments.deinit();
    }

    pub fn fromDocument(
        allocator: std.mem.Allocator,
        diagnostics: *DiagnosticList,
        document: ast.DocumentNode,
    ) !ExecutableDocument {
        var exec_doc = ExecutableDocument.init(allocator);

        for (document.definitions) |def| {
            switch (def) {
                .ExecutableDefinition => |ex| switch (ex) {
                    .OperationDefinition => |op| {
                        if (op.name) |name| {
                            const result = try exec_doc.operations.named.getOrPut(name.value);
                            if (!result.found_existing) {
                                result.value_ptr.* = op;
                            } else {
                                try diagnostics.push(.UniqueOperation);
                            }
                        } else {
                            if (exec_doc.operations.anonymous == null) {
                                exec_doc.operations.anonymous = op;
                            } else {
                                try diagnostics.push(.LoneAnonymousOperation);
                            }
                            // TODO: also push LoneAnonymousOperation when anonymous op
                            // coexists with named ops
                        }
                    },
                    .FragmentDefinition => |frag| {
                        const result = try exec_doc.fragments.getOrPut(frag.name.value);
                        if (!result.found_existing) {
                            result.value_ptr.* = frag;
                        }
                        // TODO: push UniqueFragment error on duplicates
                    },
                },
                // TODO: push NonExecutableDefinition error for type system definitions
                .TypeSystemDefinition, .TypeSystemExtension => {},
            }
        }

        return exec_doc;
    }

    pub fn getFragment(self: *const ExecutableDocument, name: []const u8) ?ast.FragmentDefinitionNode {
        return self.fragments.get(name);
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
