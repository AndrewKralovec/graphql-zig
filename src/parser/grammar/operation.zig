const std = @import("std");
const ast = @import("../../ast/ast.zig");
const Parser = @import("../parser.zig").Parser;
const TokenKind = @import("../../lexer/tokens.zig").TokenKind;

const parseNamedType = @import("./type.zig").parseNamedType;
const parseSelectionSet = @import("./selection.zig").parseSelectionSet;
const parseName = @import("./name.zig").parseName;
const parseVariableDefinitions = @import("./variable.zig").parseVariableDefinitions;
const parseDirectives = @import("./directive.zig").parseDirectives;

pub fn parseOperationDefinition(p: *Parser) !ast.OperationDefinitionNode {
    p.debug("parseOperationDefinition");
    const token = try p.peek();
    if (token.kind == TokenKind.LCurly) {
        const selection_set = try parseSelectionSet(p);
        return ast.OperationDefinitionNode{
            .operation = ast.OperationType.Query,
            .name = null,
            .variable_definitions = null,
            .directives = null,
            .selection_set = selection_set,
        };
    }

    const operation = try parseOperationType(p);
    var name: ?ast.NameNode = null;
    if (try p.peekKind(TokenKind.Name)) {
        name = try parseName(p);
    }

    const var_defs = try parseVariableDefinitions(p);
    const dirs = try parseDirectives(p, false);
    const sel_set = try parseSelectionSet(p);

    return ast.OperationDefinitionNode{
        .operation = operation,
        .name = name,
        .variable_definitions = var_defs,
        .directives = dirs,
        .selection_set = sel_set,
    };
}

pub fn parseOperationTypeDefinitions(p: *Parser) ![]ast.OperationTypeDefinitionNode {
    p.debug("parseOperationTypeDefinitions");
    _ = try p.expect(TokenKind.LCurly);

    var nodes = std.ArrayList(ast.OperationTypeDefinitionNode).init(p.allocator);
    errdefer nodes.deinit();
    while (true) {
        const otd = try parseOperationTypeDefinition(p);
        try nodes.append(otd);

        if (try p.expectOptionalToken(TokenKind.RCurly)) {
            break;
        }
    }
    return try nodes.toOwnedSlice();
}

pub fn parseOptionalOperationTypeDefinitions(p: *Parser) !?[]ast.OperationTypeDefinitionNode {
    p.debug("parseOptionalOperationTypeDefinitions");
    if (!try p.expectOptionalToken(TokenKind.LCurly)) {
        return null;
    }

    var nodes = std.ArrayList(ast.OperationTypeDefinitionNode).init(p.allocator);
    errdefer nodes.deinit();
    while (true) {
        const otd = try parseOperationTypeDefinition(p);
        try nodes.append(otd);

        if (try p.expectOptionalToken(TokenKind.RCurly)) {
            break;
        }
    }
    return try nodes.toOwnedSlice();
}

pub fn parseOperationTypeDefinition(p: *Parser) !ast.OperationTypeDefinitionNode {
    p.debug("parseOperationTypeDefinition");
    const operation = try parseOperationType(p);
    _ = try p.expect(TokenKind.Colon);
    const type_node = try parseNamedType(p);
    return ast.OperationTypeDefinitionNode{
        .operation = operation,
        .type = type_node,
    };
}

pub fn parseOperationType(p: *Parser) !ast.OperationType {
    p.debug("parseOperationType");
    const token = try p.expect(TokenKind.Name);
    const keyword = ast.stringToKeyword(token.data) orelse {
        return error.UnknownDefinition;
    };

    switch (keyword) {
        ast.SyntaxKeyWord.Query => {
            return ast.OperationType.Query;
        },
        ast.SyntaxKeyWord.Mutation => {
            return ast.OperationType.Mutation;
        },
        ast.SyntaxKeyWord.Subscription => {
            return ast.OperationType.Subscription;
        },
        else => {
            // "expected a query, mutation or subscription"
            return error.UnexpectedToken;
        },
    }
    return error.UnexpectedToken;
}

//
// Test cases for operation
//

test "should parse a operation definition with a single field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source = "{ user { id } }";
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();

    try std.testing.expect(doc.definitions.len == 1);
    const dn = doc.definitions[0];

    try std.testing.expect(dn == ast.DefinitionNode.ExecutableDefinition);
    const def = dn.ExecutableDefinition;

    try std.testing.expect(def == ast.ExecutableDefinitionNode.OperationDefinition);
    const op = def.OperationDefinition;

    try std.testing.expect(op.selection_set != null);
    try std.testing.expect(op.selection_set.?.selections.len == 1);
    const sel = op.selection_set.?.selections[0];

    try std.testing.expect(sel == ast.SelectionNode.Field);
    const f = sel.Field;
    try std.testing.expect(std.mem.eql(u8, f.name.value, "user"));
    try std.testing.expect(f.alias == null);
    try std.testing.expect(f.arguments == null);
    try std.testing.expect(f.selection_set != null);
    try std.testing.expect(f.selection_set.?.selections.len == 1);

    const sub_sel = f.selection_set.?.selections[0];
    try std.testing.expect(sub_sel == ast.SelectionNode.Field);
    const sub_f = sub_sel.Field;
    try std.testing.expect(std.mem.eql(u8, sub_f.name.value, "id"));
    try std.testing.expect(sub_f.alias == null);
    try std.testing.expect(sub_f.arguments == null);
    try std.testing.expect(sub_f.selection_set == null);
}

test "should parse a query operation with a single field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ query {
        \\  users(id: 1) {
        \\   id
        \\  }
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

    try std.testing.expect(op.selection_set != null);
    try std.testing.expect(op.selection_set.?.selections.len == 1);
    const sel = op.selection_set.?.selections[0];

    try std.testing.expect(sel == ast.SelectionNode.Field);
    const f = sel.Field;
    try std.testing.expect(std.mem.eql(u8, f.name.value, "users"));
    try std.testing.expect(f.alias == null);
    try std.testing.expect(f.arguments != null);
    try std.testing.expect(f.arguments.?.len == 1);
    try std.testing.expect(f.selection_set != null);
    try std.testing.expect(f.selection_set.?.selections.len == 1);

    const sub_sel = f.selection_set.?.selections[0];
    try std.testing.expect(sub_sel == ast.SelectionNode.Field);
    const sub_f = sub_sel.Field;
    try std.testing.expect(std.mem.eql(u8, sub_f.name.value, "id"));
    try std.testing.expect(sub_f.alias == null);
    try std.testing.expect(sub_f.arguments == null);
    try std.testing.expect(sub_f.selection_set == null);
}

test "should parse a query operation with fields and arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ query UserAndFriends($createdTime: DateTime) {
        \\   users(createdTime: $createdTime) {
        \\     id
        \\     friends {
        \\       id
        \\     }
        \\   }
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

    try std.testing.expect(op.selection_set != null);
    try std.testing.expect(op.selection_set.?.selections.len == 1);
    const sel = op.selection_set.?.selections[0];

    try std.testing.expect(sel == ast.SelectionNode.Field);
    const f = sel.Field;
    try std.testing.expect(std.mem.eql(u8, f.name.value, "users"));
    try std.testing.expect(f.alias == null);

    try std.testing.expect(f.arguments != null);
    try std.testing.expect(f.arguments.?.len == 1);
    const args = f.arguments.?;
    const arg = args[0];
    try std.testing.expect(std.mem.eql(u8, arg.name.value, "createdTime"));

    try std.testing.expect(arg.value == ast.ValueNode.Variable);
    const var_node = arg.value.Variable;
    try std.testing.expect(std.mem.eql(u8, var_node.name.value, "createdTime"));

    try std.testing.expect(f.selection_set != null);
    try std.testing.expect(f.selection_set.?.selections.len == 2);

    const sub_sel_one = f.selection_set.?.selections[0];
    try std.testing.expect(sub_sel_one == ast.SelectionNode.Field);
    const sub_f_one = sub_sel_one.Field;
    try std.testing.expect(std.mem.eql(u8, sub_f_one.name.value, "id"));
    try std.testing.expect(sub_f_one.alias == null);
    try std.testing.expect(sub_f_one.arguments == null);
    try std.testing.expect(sub_f_one.selection_set == null);

    const sub_sel_two = f.selection_set.?.selections[1];
    try std.testing.expect(sub_sel_two == ast.SelectionNode.Field);

    const sub_f_two = sub_sel_two.Field;
    try std.testing.expect(std.mem.eql(u8, sub_f_two.name.value, "friends"));
    try std.testing.expect(sub_f_two.alias == null);
    try std.testing.expect(sub_f_two.arguments == null);
    try std.testing.expect(sub_f_two.selection_set != null);
    try std.testing.expect(sub_f_two.selection_set.?.selections.len == 1);
}
