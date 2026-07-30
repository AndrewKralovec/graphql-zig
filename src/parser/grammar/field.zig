const std = @import("std");
const ast = @import("../../ast/ast.zig");
const Parser = @import("../parser.zig").Parser;
const TokenKind = @import("../../lexer/tokens.zig").TokenKind;

const parseDescription = @import("./description.zig").parseDescription;
const parseName = @import("./name.zig").parseName;
const parseArgumentDefs = @import("./argument.zig").parseArgumentDefs;
const parseTypeReference = @import("./type.zig").parseTypeReference;
const parseConstDirectives = @import("./directive.zig").parseConstDirectives;
const parseArguments = @import("./argument.zig").parseArguments;
const parseDirectives = @import("./directive.zig").parseDirectives;
const parseSelectionSet = @import("./selection.zig").parseSelectionSet;

pub fn parseFieldsDefinition(p: *Parser) !?[]ast.FieldDefinitionNode {
    p.debug("parseFieldsDefinition");
    if (!try p.expectOptionalToken(TokenKind.LCurly)) {
        return null;
    }

    var nodes = std.ArrayList(ast.FieldDefinitionNode).init(p.allocator);
    errdefer nodes.deinit();
    while (true) {
        const field = try parseFieldDefinition(p);
        try nodes.append(field);

        if (try p.expectOptionalToken(TokenKind.RCurly)) {
            break;
        }
    }
    return try nodes.toOwnedSlice();
}

pub fn parseFieldDefinition(p: *Parser) !ast.FieldDefinitionNode {
    p.debug("parseFieldDefinition");
    const description = try parseDescription(p);
    const name = try parseName(p);
    const args = try parseArgumentDefs(p);
    _ = try p.expect(TokenKind.Colon);
    const type_node = try parseTypeReference(p);
    const directives = try parseConstDirectives(p);

    return ast.FieldDefinitionNode{
        .name = name,
        .type = type_node,
        .arguments = args,
        .description = description,
        .directives = directives,
    };
}

pub fn parseField(p: *Parser) anyerror!ast.FieldNode {
    p.debug("parseField");
    const name_or_alias = try parseName(p);

    var name: ast.NameNode = undefined;
    var alias: ?ast.NameNode = null;

    if (try p.expectOptionalToken(TokenKind.Colon)) {
        alias = name_or_alias;
        name = try parseName(p);
    } else {
        name = name_or_alias;
    }

    const arguments = try parseArguments(p, false);
    const directives = try parseDirectives(p, false);
    var selection_set: ?ast.SelectionSetNode = null;
    if (try p.peekKind(TokenKind.LCurly)) {
        selection_set = try parseSelectionSet(p);
    }

    return ast.FieldNode{
        .kind = ast.SyntaxKind.Field,
        .name = name,
        .alias = alias,
        .arguments = arguments,
        .directives = directives,
        .selection_set = selection_set,
    };
}

//
// Test cases for field
//

test "should parse a simple field in a query" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ {
        \\   name
        \\   age
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
    try std.testing.expect(op.selection_set.?.selections.len == 2);

    const sel_one = op.selection_set.?.selections[0];
    try std.testing.expect(sel_one == ast.SelectionNode.Field);
    try std.testing.expect(std.mem.eql(u8, sel_one.Field.name.value, "name"));
    try std.testing.expect(sel_one.Field.alias == null);

    const sel_two = op.selection_set.?.selections[1];
    try std.testing.expect(sel_two == ast.SelectionNode.Field);
    try std.testing.expect(std.mem.eql(u8, sel_two.Field.name.value, "age"));
}

test "should parse a field with an alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ {
        \\   fullName: name
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();
    try std.testing.expect(doc.definitions.len == 1);

    const dn = doc.definitions[0];
    const def = dn.ExecutableDefinition;
    const op = def.OperationDefinition;
    try std.testing.expect(op.selection_set.?.selections.len == 1);

    const sel = op.selection_set.?.selections[0];
    try std.testing.expect(sel == ast.SelectionNode.Field);

    const field = sel.Field;
    try std.testing.expect(std.mem.eql(u8, field.name.value, "name"));
    try std.testing.expect(field.alias != null);
    try std.testing.expect(std.mem.eql(u8, field.alias.?.value, "fullName"));
}
