const std = @import("std");
const ast = @import("../graphql.zig").ast;
const FieldsInSetCanMerge = @import("validation/selection.zig").FieldsInSetCanMerge;
pub const Schema = @import("./schema/schema.zig").Schema;
pub const ValidationError = @import("./errors/errors.zig").ValidationError;
pub const ValidationErrorKind = @import("./errors/errors.zig").ValidationErrorKind;
pub const DiagnosticList = @import("./errors/errors.zig").DiagnosticList;
pub const ExecutableDocument = @import("./context/executable_document.zig").ExecutableDocument;
pub const ExecutableValidationContext = @import("./context/validation_context.zig").ExecutableValidationContext;
pub const OperationValidationContext = @import("./context/validation_context.zig").OperationValidationContext;
pub const validateOperationDefinitions = @import("validation/operation.zig").validateOperationDefinitions;
pub const buildSchema = @import("schema/builder.zig").buildSchema;
pub const validateSchema = @import("schema/validation.zig").validateSchema;

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

    pub fn deinit(self: *Validator) void {
        _ = self; // TODO: decide later
    }

    pub fn validateExecutableDocument(self: *Validator, document: ast.DocumentNode) ![]ValidationError {
        var diagnostics = DiagnosticList.init(self.allocator);
        defer diagnostics.deinit();

        var context = ExecutableValidationContext.init(self.allocator, self.schema);
        defer context.deinit();

        var exec_doc = try ExecutableDocument.fromDocument(self.allocator, &diagnostics, document);
        defer exec_doc.deinit();

        try validateOperationDefinitions(&diagnostics, &exec_doc, &context);
        try validateWithSchema(self.allocator, &diagnostics, self.schema, &exec_doc);

        // TODO: validateFragmentCycles
        // TODO: validateFragmentsUsed

        return diagnostics.toOwnedSlice();
    }

    fn validateWithSchema(
        allocator: std.mem.Allocator,
        diagnostics: *DiagnosticList,
        schema: *const Schema,
        exec_doc: *const ExecutableDocument,
    ) !void {
        // one arena and one FieldsInSetCanMerge for the whole document so the
        // internal cache persists across operations, avoiding redundant
        // re-validation of identical field sets.
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        var validator = FieldsInSetCanMerge.init(arena_alloc, schema, exec_doc);

        if (exec_doc.operations.anonymous) |op| {
            if (op.selection_set) |sel_set| {
                const against_type = schema.rootOperation(op.operation);
                try validator.validateOperation(diagnostics, arena_alloc, sel_set, against_type);
            }
        }
        for (exec_doc.operations.named.values()) |op| {
            if (op.selection_set) |sel_set| {
                const against_type = schema.rootOperation(op.operation);
                try validator.validateOperation(diagnostics, arena_alloc, sel_set, against_type);
            }
        }
    }
};

pub fn validateExecutableDocument(allocator: std.mem.Allocator, schema: *const Schema, document: ast.DocumentNode) ![]ValidationError {
    var validator = Validator.init(allocator, schema);
    defer validator.deinit();
    return try validator.validateExecutableDocument(document);
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
