const std = @import("std");
const ast = @import("../graphql.zig").ast;
pub const Schema = @import("./schema/schema.zig").Schema;
pub const ValidationError = @import("./errors.zig").ValidationError;

pub const Validator = struct {
    allocator: std.mem.Allocator,
    schema: Schema,

    pub fn init(
        allocator: std.mem.Allocator,
        schema: Schema,
    ) Validator {
        return Validator{
            .allocator = allocator,
            .schema = schema,
        };
    }

    pub fn validateQuery(self: *Validator, document: ast.DocumentNode) ![]ValidationError {
        _ = document;
        return try std.ArrayList(ValidationError).init(self.allocator).toOwnedSlice();
    }

    pub fn validateSchema(self: *Validator, document: ast.DocumentNode) ![]ValidationError {
        _ = document;
        return try std.ArrayList(ValidationError).init(self.allocator).toOwnedSlice();
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
