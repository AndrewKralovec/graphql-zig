const std = @import("std");
const ast = @import("../graphql.zig").ast;
pub const Schema = @import("./schema/schema.zig").Schema;
pub const ValidationError = @import("./errors.zig").ValidationError;
pub const ValidationErrorKind = @import("./errors.zig").ValidationErrorKind;
pub const validateDocument = @import("validation/document.zig").validateDocument;

pub const Validator = struct {
    allocator: std.mem.Allocator,
    schema: *const Schema,
    errors: std.ArrayList(ValidationError),

    pub fn init(
        allocator: std.mem.Allocator,
        schema: *const Schema,
    ) Validator {
        return Validator{
            .allocator = allocator,
            .schema = schema,
            .errors = std.ArrayList(ValidationError).init(allocator),
        };
    }

    pub fn deinit(self: *Validator) void {
        self.errors.deinit();
    }

    pub fn addError(self: *Validator, kind: ValidationErrorKind) !void {
        const err = ValidationError.init(kind);
        try self.errors.append(err);
    }

    pub fn validateExecutableDocument(self: *Validator, document: ast.DocumentNode) ![]ValidationError {
        try validateDocument(self, document);
        return self.errors.toOwnedSlice();
    }

    pub fn validateSchema(self: *Validator, document: ast.DocumentNode) ![]ValidationError {
        _ = document;
        return try self.allocator.alloc(ValidationError, 0); // TODO: add validation logic.
    }
};

pub fn validateExecutableDocument(allocator: std.mem.Allocator, schema: *const Schema, document: ast.DocumentNode) ![]ValidationError {
    var validator = Validator.init(allocator, schema);
    defer validator.deinit();
    return try validator.validateExecutableDocument(document);
}

pub fn validateSchema(allocator: std.mem.Allocator, schema: *const Schema, document: ast.DocumentNode) ![]ValidationError {
    var validator = Validator.init(allocator, schema);
    defer validator.deinit();
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

    const errors = try validateExecutableDocument(allocator, &schema, query_doc);
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

    const errors = try validateExecutableDocument(allocator, &schema, query_doc);
    defer {
        for (errors) |*err| {
            err.deinit();
        }
        allocator.free(errors);
    }
}
