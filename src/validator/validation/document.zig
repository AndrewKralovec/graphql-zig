const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateDocument(ctx: *Validator, doc: ast.DocumentNode) !void {
    // TODO: graphql-js does the walk in a single pass. optimize later.
    // the visitor per rule pattern is very readable, but the implementation isnt very ziggy.

    // validation pass
    for (doc.definitions) |def| {
        switch (def) {
            .ExecutableDefinition => |ex| switch (ex) {
                .OperationDefinition => |op| {
                    _ = op;
                    // try validateOperation(ctx, op);
                },
                .FragmentDefinition => |frag| {
                    _ = frag;
                    // try validateFragmentDefinition(ctx, frag);
                },
            },
            .TypeSystemDefinition, .TypeSystemExtension => {
                try ctx.addError(.NonExecutableDefinition);
            },
        }
    }

    // TODO: add validation logic
}

pub fn validateTypeSystemName(ctx: *Validator, name: []const u8) !void {
    _ = ctx;
    _ = name;
    // TODO: add validation logic
}

//
// Test cases for the document validation
//

const parse = @import("../../graphql.zig").parser.parse;
const validator = @import("../../graphql.zig").validator;

test "should validate ExecutableDefinitionsRule" {
    const allocator = std.testing.allocator;
    var schema = validator.Schema.init(allocator);
    defer schema.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const query_allocator = arena.allocator(); // i dont want to manually free the query nodes
    const query_source =
        \\ query Foo {
        \\   user {
        \\     name
        \\   }
        \\ }
        \\ type User {
        \\   name: String
        \\ }
        \\ extend type Guest {
        \\   role: String
        \\ }
    ;
    const query_doc = try parse(query_allocator, query_source);

    const errors = try validator.validateQuery(allocator, &schema, query_doc);
    defer {
        for (errors) |*err| {
            err.deinit();
        }
        allocator.free(errors);
    }

    try std.testing.expectEqual(@as(usize, 2), errors.len);
}
