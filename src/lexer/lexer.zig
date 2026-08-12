const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Token = @import("tokens.zig").Token;
pub const TokenKind = @import("tokens.zig").TokenKind;
pub const Cursor = @import("cursor.zig").Cursor;
pub const CursorError = @import("cursor.zig").CursorError;
const LimitTracker = @import("../util/limit_tracker.zig").LimitTracker;

/// The `Lexer` struct is responsible for walking over GraphQL text and producing a stream of tokens.
///
pub const Lexer = struct {
    finished: bool,
    limit_tracker: LimitTracker,
    cursor: Cursor,

    /// Configuration options for the `Lexer`.
    pub const Options = struct {
        /// Maximum number of tokens the lexer will scan before returning `LimitReached`.
        limit: usize = std.math.maxInt(usize),
    };

    /// Initializes a new `Lexer` from source text.
    pub fn init(source: []const u8, options: Options) Lexer {
        return Lexer{
            .finished = false,
            .cursor = Cursor.init(source),
            .limit_tracker = LimitTracker.init(options.limit),
        };
    }

    /// Return the next token in the stream, or null if we have reached EOF.
    /// This method is safe to call after EOF has been reached.
    /// If a limit was set and reached, `LimitReached` is returned.
    /// Token parsing errors are propagated immediately.
    pub fn next(self: *Lexer) LexerError!?Token {
        if (self.finished) return null;

        if (self.limit_tracker.checkAndIncrement()) {
            self.finished = true;
            return LexerError.LimitReached;
        }

        const token = try self.cursor.advance();
        if (token.kind == TokenKind.Eof) {
            self.finished = true;
        }
        return token;
    }

    /// Fully lex the input stream and return a struct containing all tokens and all errors encountered.
    /// Errors from the allocator are propagated immediately.
    /// The caller is responsible for freeing both slices.
    pub fn lex(self: *Lexer, allocator: Allocator) Allocator.Error!LexResult {
        var tokens = std.ArrayList(Token).init(allocator);
        var errors = std.ArrayList(LexerError).init(allocator);
        errdefer {
            tokens.deinit();
            errors.deinit();
        }

        while (true) {
            const result = self.next() catch |err| {
                try errors.append(err);
                switch (err) {
                    LexerError.LimitReached => break,
                    else => continue,
                }
            };
            if (result == null) {
                break;
            } else {
                const token = result.?;
                try tokens.append(token);
            }
        }

        return .{
            .tokens = try tokens.toOwnedSlice(),
            .errors = try errors.toOwnedSlice(),
        };
    }

    /// Tokenize the input stream and return all tokens.
    /// Returns the first error encountered during lexing.
    /// The caller is responsible for freeing the returned slice.
    pub fn tokenize(self: *Lexer, allocator: Allocator) (Allocator.Error || LexerError)![]Token {
        var tokens = std.ArrayList(Token).init(allocator);
        errdefer tokens.deinit();

        while (try self.next()) |token| {
            if (token.kind == TokenKind.Eof) {
                break;
            }
            try tokens.append(token);
        }

        return try tokens.toOwnedSlice();
    }
};

/// Errors produced during lexical analysis. This includes the `CursorError` error set.
pub const LexerError = CursorError || error{
    /// The token scan limit has been exceeded.
    LimitReached,
};

/// Result from lexing an entire input stream.
/// Contains all tokens and any errors encountered during lexing.
pub const LexResult = struct {
    tokens: []Token,
    errors: []LexerError,
};

/// Lex the given GraphQL source text into tokens, using the given allocator.
pub fn lex(allocator: Allocator, source: []const u8) Allocator.Error!LexResult {
    var lexer = Lexer.init(source, .{});
    return lexer.lex(allocator);
}

/// Lex the given GraphQL source text with a limit on the number of tokens that can be scanned.
/// This is useful for bounded lexing to prevent excessive memory usage or infinite loops.
pub fn lexWithLimit(allocator: Allocator, source: []const u8, limit: usize) Allocator.Error!LexResult {
    var lexer = Lexer.init(source, .{ .limit = limit });
    return lexer.lex(allocator);
}

/// Tokenize the given GraphQL source text into tokens, using the given allocator.
/// Returns the first error encountered during lexing.
pub fn tokenize(allocator: Allocator, source: []const u8) (Allocator.Error || LexerError)![]Token {
    var lexer = Lexer.init(source, .{});
    return lexer.tokenize(allocator);
}

/// Tokenize the given GraphQL source text with a limit on the number of tokens that can be scanned.
/// Returns the first error encountered during lexing.
pub fn tokenizeWithLimit(allocator: Allocator, source: []const u8, limit: usize) (Allocator.Error || LexerError)![]Token {
    var lexer = Lexer.init(source, .{ .limit = limit });
    return lexer.tokenize(allocator);
}

//
// Test cases for the Lexer
//

test "should parse all tokens from input" {
    const allocator = std.testing.allocator;
    const input = "{ user { id } }"; // 12 tokens including EOF.

    var lexer = Lexer.init(input, .{ .limit = 100 });
    const result = try lexer.lex(allocator);
    defer {
        allocator.free(result.tokens);
        allocator.free(result.errors);
    }

    try std.testing.expect(result.tokens.len == 12);
    try std.testing.expect(result.errors.len == 0);
}

test "should stream all tokens from input" {
    const input = "{ user { id } }"; // 12 tokens including EOF.

    var lexer = Lexer.init(input, .{ .limit = 100 });

    var count: usize = 0;
    while (try lexer.next()) |token| {
        count += 1;
        if (token.kind == TokenKind.Eof) {
            break; // Reached EOF
        }
    }
    try std.testing.expect(count == 12);
}

test "should parse string blocks as a single token" {
    const allocator = std.testing.allocator;
    const input =
        \\ """
        \\ The query type, represents all of the entry points into our object graph
        \\ """
        \\ type Query {
        \\   users(): User
        \\ }
    ;
    var lexer = Lexer.init(input, .{ .limit = 100 });

    const result = try lexer.lex(allocator);
    defer {
        allocator.free(result.tokens);
        allocator.free(result.errors);
    }
    try std.testing.expect(result.tokens.len == 18);
    try std.testing.expect(result.errors.len == 0);
}

test "should return error when limit is reached" {
    const allocator = std.testing.allocator;
    const input = "{ user { id } }"; // 12 tokens including EOF.

    var lexer = Lexer.init(input, .{ .limit = 10 });

    const result = try lexer.lex(allocator);
    defer {
        allocator.free(result.tokens);
        allocator.free(result.errors);
    }
    try std.testing.expect(result.tokens.len == 10);
    try std.testing.expect(result.errors.len == 1);
}

test "lex should tokenize input" {
    const allocator = std.testing.allocator;
    const input = "{ user { id } }"; // 12 tokens including EOF.

    const result = try lex(allocator, input);
    defer {
        allocator.free(result.tokens);
        allocator.free(result.errors);
    }

    try std.testing.expect(result.tokens.len == 12);
    try std.testing.expect(result.errors.len == 0);
}

test "lexWithLimit should return error when limit is reached" {
    const allocator = std.testing.allocator;
    const input = "{ user { id } }"; // 12 tokens including EOF.

    const result = try lexWithLimit(allocator, input, 10);
    defer {
        allocator.free(result.tokens);
        allocator.free(result.errors);
    }

    try std.testing.expect(result.tokens.len == 10);
    try std.testing.expect(result.errors.len == 1);
}

test "tokenize should return slice of tokens" {
    const allocator = std.testing.allocator;
    const input = "{ user { id } }";

    var lexer = Lexer.init(input, .{});
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len == 11);
    try std.testing.expect(tokens[0].kind == TokenKind.LCurly);
    try std.testing.expect(tokens[tokens.len - 1].kind == TokenKind.RCurly);
}

test "tokenize should return first error on limit reached" {
    const allocator = std.testing.allocator;
    const input = "{ user { id } }";

    var lexer = Lexer.init(input, .{ .limit = 5 });
    const result = lexer.tokenize(allocator);

    try std.testing.expectError(error.LimitReached, result);
}
