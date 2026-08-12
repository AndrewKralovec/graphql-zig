const std = @import("std");
const ast = @import("../ast/ast.zig");
const config = @import("build_config.zig");
const document = @import("./grammar/document.zig");
const Lexer = @import("../lexer/lexer.zig").Lexer;
const LexerError = @import("../lexer/lexer.zig").LexerError;
const Token = @import("../lexer/tokens.zig").Token;
const TokenKind = @import("../lexer/tokens.zig").TokenKind;

// Debugging functions to print the parser state.
// Configurable through build options.
// Might be removed in the future. This is a beta feature.
fn noopDebug(_: *Parser, _: []const u8) void {}
fn printDebug(p: *Parser, tag: []const u8) void {
    std.debug.print("{s}\n", .{tag});
    const t = p.peek() catch |err| {
        std.debug.print("error = {any}\n", .{err});
        return;
    };
    std.debug.print(
        \\peek
        \\{{
        \\  .kind = {?}
        \\  .data = {s}
        \\  .index = {d}
        \\}}
        \\
    ,
        .{ t.kind, t.data, t.index },
    );
}

/// The `Parser` struct handles converting GraphQL text into an
/// abstract syntax tree. It uses a `Lexer` to tokenize the input,
/// and provides methods for navigating and consuming tokens during parsing.
///
/// This struct is passed into grammar specific parsing functions
/// which walk the token stream, from the `Lexer`, and returns the top level `DocumentNode`.
pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer,
    current_token: ?Token,

    /// Configuration options for the `Parser`.
    pub const Options = struct {
        /// Maximum number of tokens the parser will scan before returning `LimitReached`.
        limit: usize = std.math.maxInt(usize),
    };

    /// Debug function to print the parser state.
    pub const debug = if (config.debug) printDebug else noopDebug;

    /// Initializes a new `Parser` from source text.
    pub fn init(allocator: std.mem.Allocator, source: []const u8, options: Options) Parser {
        return Parser{
            .allocator = allocator,
            .lexer = Lexer.init(source, .{ .limit = options.limit }),
            .current_token = null,
        };
    }

    /// Next non-ignorable token from the `Lexer`.
    pub fn nextToken(self: *Parser) ParserError!Token {
        return nextNonIgnorableToken(&self.lexer);
    }

    /// Lookahead at the next non-ignorable token without advancing the `Lexer`.
    /// This is done by cloning the `Lexer` and scanning ahead.
    pub fn lookahead(self: *Parser) ParserError!Token {
        // TODO: Inefficient, refactor the lexer/cursor to allow lookahead without cloning.
        var lexer = self.lexer;
        return nextNonIgnorableToken(&lexer);
    }

    /// Peek the next token from the `Lexer`.
    /// This will load the next token until it is popped.
    pub fn peek(self: *Parser) ParserError!Token {
        if (self.current_token == null) {
            self.current_token = try self.nextToken();
        }
        return self.current_token.?;
    }

    /// Peek and check if the next token is of a given kind.
    pub fn peekKind(self: *Parser, kind: TokenKind) ParserError!bool {
        const token = try self.peek();
        return (token.kind == kind);
    }

    /// Pop the current token and reset the peeked state.
    pub fn pop(self: *Parser) ParserError!Token {
        const token = try self.peek();
        self.current_token = null;
        return token;
    }

    /// If the next token is a given keyword and matches the expected keyword,
    /// pop it and return true. Otherwise, return false and no-op.
    pub fn expectOptionalKeyword(self: *Parser, keyword: ast.SyntaxKeyWord) ParserError!bool {
        const token = try self.peek();
        const tkw = ast.stringToKeyword(token.data) orelse return false;
        if (token.kind == TokenKind.Name and tkw == keyword) {
            _ = try self.pop();
            return true;
        }
        return false;
    }

    /// Expect the next token is a given keyword. If it's not there, throw an error.
    pub fn expectKeyword(self: *Parser, keyword: ast.SyntaxKeyWord) ParserError!void {
        if (!try self.expectOptionalKeyword(keyword)) {
            return ParserError.UnexpectedKeyword;
        }
    }

    /// If the next token is of the expected kind, pop it and return true.
    /// Otherwise, return false and no-op.
    pub fn expectOptionalToken(self: *Parser, kind: TokenKind) ParserError!bool {
        const token = try self.peek();
        if (token.kind == kind) {
            _ = try self.pop();
            return true;
        }
        return false;
    }

    /// Expect the next token is a given kind. If it's not, throw an error.
    pub fn expect(self: *Parser, kind: TokenKind) ParserError!Token {
        const token = try self.peek();
        if (token.kind != kind) {
            return ParserError.UnexpectedToken;
        }
        _ = try self.pop();
        return token;
    }

    /// Parse the entire document and return the top level `DocumentNode`.
    /// This is the main entry point for parsing GraphQL text.
    pub fn parse(self: *Parser) !ast.DocumentNode {
        const doc = try document.parseDocument(self);
        return doc;
    }

    fn nextNonIgnorableToken(lexer: *Lexer) ParserError!Token {
        while (try lexer.next()) |token| {
            switch (token.kind) {
                TokenKind.Comment, TokenKind.Whitespace, TokenKind.Comma => continue,
                else => return token,
            }
        }
        return ParserError.ReadAfterFinished;
    }
};

/// Errors produced during parsing. This includes the `LexerError` error set.
pub const ParserError = LexerError || error{
    /// The parser encountered a token of a different kind than expected.
    UnexpectedToken,
    /// The parser expected a specific keyword but found something else.
    UnexpectedKeyword,
    /// Token stream was accessed after the lexer has already finished processing all input.
    ReadAfterFinished,
};

/// Parse the given GraphQL source text into an AST representation, using the given allocator.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !ast.DocumentNode {
    var parser = Parser.init(allocator, source, .{});
    return parser.parse();
}

/// Parse the given GraphQL source text with a limit on the number of tokens that can be scanned.
/// This is useful for bounded parsing to prevent excessive memory usage or infinite loops.
pub fn parseWithLimit(allocator: std.mem.Allocator, source: []const u8, limit: usize) !ast.DocumentNode {
    var parser = Parser.init(allocator, source, .{ .limit = limit });
    return parser.parse();
}

//
// Test cases for the Parser
//

test "should parse simple query with public parse function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "{ user { id } }";
    const doc = try parse(arena.allocator(), source);

    try std.testing.expect(doc.definitions.len == 1);
}

test "should return error when limit is reached" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "{ user { id } }";
    var bounded = Parser.init(arena.allocator(), source, .{ .limit = 11 });

    const result = bounded.parse();
    try std.testing.expectError(error.LimitReached, result);
}

test "should parse with limit using public parse function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "{ user { id } }";
    const doc = try parseWithLimit(arena.allocator(), source, 12);

    try std.testing.expect(doc.definitions.len == 1);
}

test "should return error when limit is reached using public parse function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "{ user { id } }";
    const result = parseWithLimit(arena.allocator(), source, 11);

    try std.testing.expectError(error.LimitReached, result);
}
