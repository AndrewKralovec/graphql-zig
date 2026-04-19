const std = @import("std");
const ast = @import("../graphql.zig").ast;
pub const Schema = @import("./schema/schema.zig").Schema;
pub const ValidationError = @import("./errors.zig").ValidationError;

pub const Validator = struct {
    allocator: std.mem.Allocator,
    schema: *const Schema,

    pub fn init(
        allocator: std.mem.Allocator,
        schema: *const Schema,
    ) Validator {
        return Validator{
            .allocator = allocator,
            .schema = schema,
        };
    }

    pub fn validateQuery(self: *Validator, document: ast.DocumentNode) ![]ValidationError {
        _ = document;
        return try self.allocator.alloc(ValidationError, 0); // TODO: add validation logic.
    }

    pub fn validateSchema(self: *Validator, document: ast.DocumentNode) ![]ValidationError {
        _ = document;
        return try self.allocator.alloc(ValidationError, 0); // TODO: add validation logic.
    }
};

pub fn validateQuery(allocator: std.mem.Allocator, schema: *const Schema, document: ast.DocumentNode) ![]ValidationError {
    var validator = Validator.init(allocator, schema);
    return try validator.validateQuery(document);
}

pub fn validateSchema(allocator: std.mem.Allocator, schema: *const Schema, document: ast.DocumentNode) ![]ValidationError {
    var validator = Validator.init(allocator, schema);
    return try validator.validateSchema(document);
}

//
// Test cases for the Validator
//

const parse = @import("../graphql.zig").parser.parse;

test "should validate query" {
    const allocator = std.testing.allocator;
    var schema = Schema.init(allocator);
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

    const errors = try validateQuery(allocator, &schema, query_doc);
    defer {
        for (errors) |*err| {
            err.deinit();
        }
        allocator.free(errors);
    }
}

test "should validate schema" {
    const allocator = std.testing.allocator;
    var schema = Schema.init(allocator);
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

    const errors = try validateQuery(allocator, &schema, query_doc);
    defer {
        for (errors) |*err| {
            err.deinit();
        }
        allocator.free(errors);
    }
}
