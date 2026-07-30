const std = @import("std");
const ast = @import("../../ast/ast.zig");
const Parser = @import("../parser.zig").Parser;
const TokenKind = @import("../../lexer/tokens.zig").TokenKind;

const parseDescription = @import("./description.zig").parseDescription;
const parseName = @import("./name.zig").parseName;
const parseConstDirectives = @import("./directive.zig").parseConstDirectives;
const parseNamedType = @import("./type.zig").parseNamedType;

pub fn parseUnionTypeDefinition(p: *Parser) !ast.UnionTypeDefinitionNode {
    p.debug("parseUnionTypeDefinition");
    const description = try parseDescription(p);
    _ = try p.expectKeyword(ast.SyntaxKeyWord.Union);
    const name = try parseName(p);
    const directives = try parseConstDirectives(p);
    const types = try parseUnionMemberTypes(p);

    return ast.UnionTypeDefinitionNode{
        .description = description,
        .name = name,
        .directives = directives,
        .types = types,
    };
}

pub fn parseUnionMemberTypes(p: *Parser) !?[]ast.NamedTypeNode {
    p.debug("parseUnionMemberTypes");
    if (!try p.expectOptionalToken(TokenKind.Eq)) {
        return null;
    }

    _ = try p.expectOptionalToken(TokenKind.Pipe);
    var nodes = std.ArrayList(ast.NamedTypeNode).init(p.allocator);
    errdefer nodes.deinit();
    while (true) {
        const name = try parseNamedType(p);
        try nodes.append(name);

        if (!try p.expectOptionalToken(TokenKind.Pipe)) {
            break;
        }
    }
    return try nodes.toOwnedSlice();
}

pub fn parseUnionTypeExtension(p: *Parser) !ast.UnionTypeExtensionNode {
    p.debug("parseUnionTypeExtension");
    _ = try p.expectKeyword(ast.SyntaxKeyWord.Extend);
    _ = try p.expectKeyword(ast.SyntaxKeyWord.Union);
    const name = try parseName(p);
    const directives = try parseConstDirectives(p);
    const types = try parseUnionMemberTypes(p);

    const directives_empty = if (directives) |d| d.len == 0 else true;
    const types_empty = if (types) |f| f.len == 0 else true;
    if (directives_empty and types_empty) {
        return error.UnexpectedToken;
    }

    return ast.UnionTypeExtensionNode{
        .name = name,
        .directives = directives,
        .types = types,
    };
}

//
// Test cases for union
//

test "should parse a union type definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ union SearchResult = User | Post | Comment
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();
    try std.testing.expect(doc.definitions.len == 1);

    const dn = doc.definitions[0];
    try std.testing.expect(dn == ast.DefinitionNode.TypeSystemDefinition);

    const def = dn.TypeSystemDefinition;
    try std.testing.expect(def == ast.TypeSystemDefinitionNode.TypeDefinition);

    const type_def = def.TypeDefinition;
    try std.testing.expect(type_def == ast.TypeDefinitionNode.UnionTypeDefinition);

    const obj_def = type_def.UnionTypeDefinition;
    try std.testing.expect(obj_def.description == null);
    try std.testing.expect(std.mem.eql(u8, obj_def.name.value, "SearchResult"));
}
