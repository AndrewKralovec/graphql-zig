const std = @import("std");
const ast = @import("../../ast/ast.zig");
const Parser = @import("../parser.zig").Parser;
const TokenKind = @import("../../lexer/tokens.zig").TokenKind;

const parseDescription = @import("./description.zig").parseDescription;
const parseName = @import("./name.zig").parseName;
const parseConstDirectives = @import("./directive.zig").parseConstDirectives;

pub fn parseEnumTypeDefinition(p: *Parser) !ast.EnumTypeDefinitionNode {
    p.debug("parseEnumTypeDefinition");
    const description = try parseDescription(p);
    _ = try p.expectKeyword(ast.SyntaxKeyWord.Enum);
    const name = try parseName(p);
    const directives = try parseConstDirectives(p);
    const values = try parseEnumValuesDefinitions(p);

    return ast.EnumTypeDefinitionNode{
        .description = description,
        .name = name,
        .directives = directives,
        .values = values,
    };
}

pub fn parseEnumValuesDefinitions(p: *Parser) !?[]ast.EnumValueDefinitionNode {
    p.debug("parseEnumValuesDefinitions");
    if (!try p.expectOptionalToken(TokenKind.LCurly)) {
        return null;
    }

    var nodes = std.ArrayList(ast.EnumValueDefinitionNode).init(p.allocator);
    errdefer nodes.deinit();
    while (true) {
        const value = try parseEnumValueDefinition(p);
        try nodes.append(value);

        if (try p.expectOptionalToken(TokenKind.RCurly)) {
            break;
        }
    }
    return try nodes.toOwnedSlice();
}

pub fn parseEnumValueDefinition(p: *Parser) !ast.EnumValueDefinitionNode {
    p.debug("parseEnumValueDefinition");
    const description = try parseDescription(p);
    const name = try parseEnumValueName(p);
    const directives = try parseConstDirectives(p);

    return ast.EnumValueDefinitionNode{
        .description = description,
        .name = name,
        .directives = directives,
    };
}

pub fn parseEnumValueName(p: *Parser) !ast.NameNode {
    p.debug("parseEnumValueName");
    const token = try p.peek();
    if (std.mem.eql(u8, token.data, "true") or
        std.mem.eql(u8, token.data, "false") or
        std.mem.eql(u8, token.data, "null"))
    {
        return error.ReservedEnumValueName;
    }

    const name = try parseName(p);
    return name;
}

pub fn parseEnumTypeExtension(p: *Parser) !ast.EnumTypeExtensionNode {
    p.debug("parseEnumTypeExtension");
    _ = try p.expectKeyword(ast.SyntaxKeyWord.Extend);
    _ = try p.expectKeyword(ast.SyntaxKeyWord.Enum);
    const name = try parseName(p);
    const directives = try parseConstDirectives(p);
    const values = try parseEnumValuesDefinitions(p);

    const directives_empty = if (directives) |d| d.len == 0 else true;
    const values_empty = if (values) |v| v.len == 0 else true;
    if (directives_empty and values_empty) {
        return error.UnexpectedToken;
    }

    return ast.EnumTypeExtensionNode{
        .name = name,
        .directives = directives,
        .values = values,
    };
}

//
// Test cases for enum
//

test "should parse a enum type definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ enum UserType {
        \\   GUEST
        \\   REGISTERED
        \\   ADMIN
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
    try std.testing.expect(type_def == ast.TypeDefinitionNode.EnumTypeDefinition);

    const obj_def = type_def.EnumTypeDefinition;
    try std.testing.expect(obj_def.description == null);
    try std.testing.expect(std.mem.eql(u8, obj_def.name.value, "UserType"));

    try std.testing.expect(obj_def.values != null);
    try std.testing.expect(obj_def.values.?.len == 3);

    const values = obj_def.values.?;
    try std.testing.expect(std.mem.eql(u8, values[0].name.value, "GUEST"));
    try std.testing.expect(std.mem.eql(u8, values[1].name.value, "REGISTERED"));
    try std.testing.expect(std.mem.eql(u8, values[2].name.value, "ADMIN"));
}
