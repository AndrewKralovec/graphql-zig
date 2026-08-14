// TODO: Find out the ziggy way to have test helpers.
const std = @import("std");
const ast = @import("../graphql.zig").ast;
const parse = @import("../graphql.zig").parser.parse;
pub const Schema = @import("./schema/schema.zig").Schema;
pub const ValidationError = @import("./errors/errors.zig").ValidationError;
pub const ValidationErrorKind = @import("./errors/errors.zig").ValidationErrorKind;
pub const validateExecutableDocument = @import("../graphql.zig").validator.validateExecutableDocument;

// Test helpers

pub fn expectValid(
    query_source: []const u8,
) !void {
    try expectErrors(query_source, 0);
}

pub fn expectErrors(
    query_source: []const u8,
    expected_error_count: usize,
) !void {
    const allocator = std.testing.allocator;
    var schema = Schema.init(allocator);
    defer schema.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const query_doc = try parse(arena.allocator(), query_source);

    const errors = try validateExecutableDocument(allocator, &schema, query_doc);
    defer {
        for (errors) |*err| {
            err.deinit();
        }
        allocator.free(errors);
    }

    std.testing.expectEqual(expected_error_count, errors.len) catch |err| {
        std.debug.print("\nerrors={any}\n", .{errors});
        return err;
    };
}

// fn expectErrorCount(
//     query_source: []const u8,
//     expected_error_count: usize,
//     expected_error: ValidationErrorKind,
// ) !void {
//     const allocator = std.testing.allocator;
//     var schema = Schema.init(allocator);
//     defer schema.deinit();

//     var arena = std.heap.ArenaAllocator.init(allocator);
//     defer arena.deinit();

//     const query_doc = try parse(arena.allocator(), query_source);

//     var ctx = Validator.init(allocator, &schema);
//     defer ctx.deinit();

//     try ctx.validateExecutableDocument(query_doc);

//     var err_count: u32 = 0;
//     for (ctx.errors.items) |err| {
//         if (err.kind == expected_error) {
//             err_count = err_count + 1;
//         }
//     }

//     std.testing.expectEqual(expected_error_count, err_count) catch |err| {
//         std.debug.print("\nerrors={any}\n", .{ctx.errors.items});
//         return err;
//     };
// }
