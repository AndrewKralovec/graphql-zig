const std = @import("std");
const ast = @import("../../ast/ast.zig");
const Parser = @import("../parser.zig").Parser;
const TokenKind = @import("../../lexer/tokens.zig").TokenKind;

const parseName = @import("./name.zig").parseName;
const parseValueLiteral = @import("./value.zig").parseValueLiteral;
const parseInputValueDef = @import("./input.zig").parseInputValueDef;

pub fn parseArguments(p: *Parser, is_const: bool) !?[]ast.ArgumentNode {
    p.debug("parseArguments");
    if (!try p.expectOptionalToken(TokenKind.LParen)) {
        return null;
    }

    var nodes = std.ArrayList(ast.ArgumentNode).init(p.allocator);
    errdefer nodes.deinit();
    while (true) {
        const arg = try parseArgument(p, is_const);
        try nodes.append(arg);

        if (try p.expectOptionalToken(TokenKind.RParen)) {
            break;
        }
    }
    return try nodes.toOwnedSlice();
}

pub fn parseArgument(p: *Parser, is_const: bool) !ast.ArgumentNode {
    p.debug("parseArgument");
    const name = try parseName(p);
    _ = try p.expect(TokenKind.Colon);

    const value = try parseValueLiteral(p, is_const);
    return ast.ArgumentNode{
        .name = name,
        .value = value,
    };
}

pub fn parseArgumentDefs(p: *Parser) !?[]ast.InputValueDefinitionNode {
    p.debug("parseArgumentDefs");
    if (!try p.expectOptionalToken(TokenKind.LParen)) {
        return null;
    }

    var nodes = std.ArrayList(ast.InputValueDefinitionNode).init(p.allocator);
    errdefer nodes.deinit();
    while (true) {
        const arg = try parseInputValueDef(p);
        try nodes.append(arg);

        if (try p.expectOptionalToken(TokenKind.RParen)) {
            break;
        }
    }
    return try nodes.toOwnedSlice();
}

//
// Test cases for argument
//

test "should parse a field with a single argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ {
        \\   user(id: 42)
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();
    try std.testing.expect(doc.definitions.len == 1);

    const dn = doc.definitions[0];
    try std.testing.expect(dn == ast.DefinitionNode.ExecutableDefinition);

    const def = dn.ExecutableDefinition;
    try std.testing.expect(def == ast.ExecutableDefinitionNode.OperationDefinition);

    const op = def.OperationDefinition;
    const sel = op.selection_set.?.selections[0];
    try std.testing.expect(sel == ast.SelectionNode.Field);

    const field = sel.Field;
    try std.testing.expect(std.mem.eql(u8, field.name.value, "user"));
    try std.testing.expect(field.arguments != null);
    try std.testing.expect(field.arguments.?.len == 1);

    const arg = field.arguments.?[0];
    try std.testing.expect(std.mem.eql(u8, arg.name.value, "id"));
    try std.testing.expect(arg.value == ast.ValueNode.Int);
}

test "should parse a field with multiple arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ {
        \\   users(limit: 10, active: true)
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();

    const op = doc.definitions[0].ExecutableDefinition.OperationDefinition;
    const field = op.selection_set.?.selections[0].Field;
    try std.testing.expect(std.mem.eql(u8, field.name.value, "users"));
    try std.testing.expect(field.arguments.?.len == 2);

    const arg_one = field.arguments.?[0];
    try std.testing.expect(std.mem.eql(u8, arg_one.name.value, "limit"));
    try std.testing.expect(arg_one.value == ast.ValueNode.Int);

    const arg_two = field.arguments.?[1];
    try std.testing.expect(std.mem.eql(u8, arg_two.name.value, "active"));
    try std.testing.expect(arg_two.value == ast.ValueNode.Boolean);
}
