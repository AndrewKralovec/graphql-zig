const std = @import("std");
const ast = @import("../../ast/ast.zig");
const Parser = @import("../parser.zig").Parser;
const TokenKind = @import("../../lexer/tokens.zig").TokenKind;

const parseName = @import("./name.zig").parseName;
const parseTypeReference = @import("./type.zig").parseTypeReference;
const parseConstValueLiteral = @import("./value.zig").parseConstValueLiteral;
const parseConstDirectives = @import("./directive.zig").parseConstDirectives;

pub fn parseVariableDefinitions(p: *Parser) !?[]ast.VariableDefinitionNode {
    if (!try p.expectOptionalToken(TokenKind.LParen)) {
        return null;
    }

    var nodes = std.ArrayList(ast.VariableDefinitionNode).init(p.allocator);
    errdefer nodes.deinit();
    while (true) {
        p.debug("parseVariableDefinitions");
        const var_def = try parseVariableDefinition(p);
        try nodes.append(var_def);

        if (try p.expectOptionalToken(TokenKind.RParen)) {
            break;
        }
    }
    return try nodes.toOwnedSlice();
}

pub fn parseVariableDefinition(p: *Parser) !ast.VariableDefinitionNode {
    p.debug("parseVariableDefinition");
    const variable = try parseVariable(p);
    _ = try p.expect(TokenKind.Colon);
    const type_node = try parseTypeReference(p);

    var default_value: ?ast.ValueNode = null;
    if (try p.expectOptionalToken(TokenKind.Eq)) {
        default_value = try parseConstValueLiteral(p);
    }

    const directives = try parseConstDirectives(p);

    return ast.VariableDefinitionNode{
        .variable = variable,
        .type = type_node,
        .default_value = default_value,
        .directives = directives,
    };
}

pub fn parseVariable(p: *Parser) !ast.VariableNode {
    p.debug("parseVariable");
    _ = try p.expect(TokenKind.Dollar);
    const name = try parseName(p);
    return ast.VariableNode{
        .name = name,
    };
}

//
// Test cases for variable
//

test "should parse a variable definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ query GetUser($id: ID!) {
        \\   user
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();

    const op = doc.definitions[0].ExecutableDefinition.OperationDefinition;
    const var_defs = op.variable_definitions.?;
    try std.testing.expect(var_defs.len == 1);

    try std.testing.expect(std.mem.eql(u8, var_defs[0].variable.name.value, "id"));

    const type_node = var_defs[0].type.*;
    try std.testing.expect(type_node == ast.TypeNode.NonNullType);
    const inner = type_node.NonNullType.type.*;
    try std.testing.expect(inner == ast.TypeNode.NamedType);
    try std.testing.expect(std.mem.eql(u8, inner.NamedType.name.value, "ID"));

    try std.testing.expect(var_defs[0].default_value == null);
}

test "should parse a variable definition with a default value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ query GetUsers($limit: Int = 10) {
        \\   users
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();

    const op = doc.definitions[0].ExecutableDefinition.OperationDefinition;
    const var_defs = op.variable_definitions.?;
    try std.testing.expect(var_defs.len == 1);

    try std.testing.expect(std.mem.eql(u8, var_defs[0].variable.name.value, "limit"));

    const type_node = var_defs[0].type.*;
    try std.testing.expect(type_node == ast.TypeNode.NamedType);
    try std.testing.expect(std.mem.eql(u8, type_node.NamedType.name.value, "Int"));

    try std.testing.expect(var_defs[0].default_value != null);
    const default_val = var_defs[0].default_value.?;
    try std.testing.expect(default_val == ast.ValueNode.Int);
    try std.testing.expect(std.mem.eql(u8, default_val.Int.value, "10"));
}
