const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateDocument(ctx: *Validator, doc: ast.DocumentNode) !void {
    // TODO: graphql-js does the walk in a single pass. optimize later.
    // the visitor per rule pattern is very readable, but the implementation isnt very ziggy.

    _ = ctx;
    _ = doc;
    // TODO: add validation logic
}

pub fn validateTypeSystemName(ctx: *Validator, name: []const u8) !void {
    _ = ctx;
    _ = name;
    // TODO: add validation logic
}
