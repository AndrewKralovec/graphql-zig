//! A GraphQL parser library for Zig
//!
//! This library provides comprehensive lexical analysis and parsing capabilities
//! for GraphQL documents, supporting both executable documents (queries, mutations,
//! subscriptions) and type system definitions (schemas, types, directives).
const std = @import("std");
pub const ast = @import("ast/ast.zig");
pub const lexer = @import("lexer/lexer.zig");
pub const parser = @import("parser/parser.zig");
pub const validator = @import("validator/validator.zig");

//
// Test cases for the graphql module
//

test {
    std.testing.refAllDecls(@This());

    _ = @import("ast/ast.zig");
    _ = @import("lexer/lexer.zig");
    _ = @import("parser/parser.zig");
    _ = @import("validator/validator.zig");
}
