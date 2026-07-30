const std = @import("std");
const ast = @import("../../ast/ast.zig");
const Parser = @import("../parser.zig").Parser;
const TokenKind = @import("../../lexer/tokens.zig").TokenKind;

const parseDescription = @import("./description.zig").parseDescription;
const parseName = @import("./name.zig").parseName;
const parseConstDirectives = @import("./directive.zig").parseConstDirectives;
const parseConstValueLiteral = @import("./value.zig").parseConstValueLiteral;
const parseTypeReference = @import("./type.zig").parseTypeReference;

pub fn parseInputObjectTypeDefinition(p: *Parser) !ast.InputObjectTypeDefinitionNode {
    p.debug("parseInputObjectTypeDefinition");
    const description = try parseDescription(p);
    _ = try p.expectKeyword(ast.SyntaxKeyWord.Input);
    const name = try parseName(p);
    const directives = try parseConstDirectives(p);
    const fields = try parseInputFieldsDefinition(p);

    return ast.InputObjectTypeDefinitionNode{
        .description = description,
        .name = name,
        .directives = directives,
        .fields = fields,
    };
}

pub fn parseInputFieldsDefinition(p: *Parser) !?[]ast.InputValueDefinitionNode {
    p.debug("parseInputFieldsDefinition");
    if (!try p.expectOptionalToken(TokenKind.LCurly)) {
        return null;
    }

    var nodes = std.ArrayList(ast.InputValueDefinitionNode).init(p.allocator);
    errdefer nodes.deinit();
    while (true) {
        const field = try parseInputValueDef(p);
        try nodes.append(field);

        if (try p.expectOptionalToken(TokenKind.RCurly)) {
            break;
        }
    }
    return try nodes.toOwnedSlice();
}

pub fn parseInputValueDef(p: *Parser) !ast.InputValueDefinitionNode {
    p.debug("parseInputValueDef");
    const name = try parseName(p);
    _ = try p.expect(TokenKind.Colon);
    const type_node = try parseTypeReference(p);
    var default_value: ?ast.ValueNode = null;
    if (try p.expectOptionalToken(TokenKind.Eq)) {
        default_value = try parseConstValueLiteral(p);
    }
    const directives = try parseConstDirectives(p);

    return ast.InputValueDefinitionNode{
        .name = name,
        .type = type_node,
        .default_value = default_value,
        .directives = directives,
    };
}

pub fn parseInputObjectTypeExtension(p: *Parser) !ast.InputObjectTypeExtensionNode {
    p.debug("parseInputObjectTypeExtension");
    _ = try p.expectKeyword(ast.SyntaxKeyWord.Extend);
    _ = try p.expectKeyword(ast.SyntaxKeyWord.Input);
    const name = try parseName(p);
    const directives = try parseConstDirectives(p);
    const fields = try parseInputFieldsDefinition(p);

    const directives_empty = if (directives) |d| d.len == 0 else true;
    const fields_empty = if (fields) |f| f.len == 0 else true;
    if (directives_empty and fields_empty) {
        return error.UnexpectedToken;
    }

    return ast.InputObjectTypeExtensionNode{
        .name = name,
        .directives = directives,
        .fields = fields,
    };
}

//
// Test cases for input
//

test "should parse a input type definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ input UserInput {
        \\   id: ID
        \\   name: String
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();
    try std.testing.expect(doc.definitions.len == 1);

    const dn = doc.definitions[0];
    try std.testing.expect(dn == ast.DefinitionNode.TypeSystemDefinition);

    const def = dn.TypeSystemDefinition;
    try std.testing.expect(def == ast.TypeSystemDefinitionNode.TypeDefinition);

    const type_def = def.TypeDefinition;
    try std.testing.expect(type_def == ast.TypeDefinitionNode.InputObjectTypeDefinition);

    const obj_def = type_def.InputObjectTypeDefinition;
    try std.testing.expect(obj_def.description == null);
    try std.testing.expect(std.mem.eql(u8, obj_def.name.value, "UserInput"));

    try std.testing.expect(obj_def.directives == null);
    try std.testing.expect(obj_def.fields != null);
    try std.testing.expect(obj_def.fields.?.len == 2);

    const fields = obj_def.fields.?;
    try std.testing.expect(std.mem.eql(u8, fields[0].name.value, "id"));
    try std.testing.expect(std.mem.eql(u8, fields[1].name.value, "name"));
}
