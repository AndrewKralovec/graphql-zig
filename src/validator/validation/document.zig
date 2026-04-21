const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateDocument(ctx: *Validator, doc: ast.DocumentNode) !void {
    // TODO: graphql-js does the walk in a single pass, using visitors. optimize later.
    // the visitor per rule pattern is very readable, but the implementation isnt very ziggy (and might not be efficient in zig).
    // going to follow the graphql-rs example instead, which is broken down into their grammar parts/syntax, instead of being broken down by individual grammar rules.

    var known_operation_names = std.StringHashMap(void).init(ctx.allocator);
    defer known_operation_names.deinit();

    for (doc.definitions) |def| {
        switch (def) {
            .ExecutableDefinition => |ex| switch (ex) {
                .OperationDefinition => |op| {
                    if (op.name) |name| {
                        if (known_operation_names.contains(name.value)) {
                            try ctx.addError(.UniqueOperationName);
                        } else {
                            try known_operation_names.put(name.value, {});
                        }
                    }
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

const test_helpers = @import("../test_helpers.zig");

test "should validate ExecutableDefinitionsRule" {
    try test_helpers.expectErrors(
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
    , 2);
}

// UniqueOperationNames

test "should allow no operations for unique operation names" {
    try test_helpers.expectValid(
        \\ fragment fragA on Type {
        \\   field
        \\ }
    );
}

test "should allow anonymous operation" {
    try test_helpers.expectValid(
        \\ {
        \\  field
        \\ }
    );
}

test "should allow one operation for unique operation names" {
    try test_helpers.expectValid(
        \\ query Foo {
        \\   field
        \\ }
    );
}

test "should allow multiple operations" {
    try test_helpers.expectValid(
        \\ query Foo {
        \\   field
        \\ }
        \\ query Bar {
        \\   field
        \\ }
    );
}

test "should allow multiple operations with different types" {
    try test_helpers.expectValid(
        \\ query Foo {
        \\   field
        \\ }
        \\ mutation Bar {
        \\   field
        \\ }
        \\ subscription Baz {
        \\   field
        \\ }
    );
}

test "should allow fragment and operation named the same" {
    try test_helpers.expectValid(
        \\ query Foo {
        \\   ...Foo
        \\ }
        \\ fragment Foo on Type {
        \\   field
        \\ }
    );
}

test "should return errors when operations have the same name" {
    try test_helpers.expectErrors(
        \\ query Foo {
        \\   fieldA
        \\ }
        \\ query Foo {
        \\   fieldB
        \\ }
    , 1);
}

test "should return errors when operations ops of same name and different types (mutation)" {
    try test_helpers.expectErrors(
        \\ query Foo {
        \\   fieldA
        \\ }
        \\ mutation Foo {
        \\   fieldB
        \\ }
    , 1);
}

test "should return errors when operations ops of same name and different types (subscription)" {
    try test_helpers.expectErrors(
        \\ query Foo {
        \\   fieldA
        \\ }
        \\ subscription Foo {
        \\   fieldB
        \\ }
    , 1);
}
