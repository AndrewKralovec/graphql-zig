const std = @import("std");
const ast = @import("../../ast/ast.zig");
const Parser = @import("../parser.zig").Parser;
const TokenKind = @import("../../lexer/tokens.zig").TokenKind;

const parseDescription = @import("./description.zig").parseDescription;
const parseName = @import("./name.zig").parseName;
const parseArguments = @import("./argument.zig").parseArguments;
const parseArgumentDefs = @import("./argument.zig").parseArgumentDefs;

pub fn parseDirectiveDefinition(p: *Parser) !ast.DirectiveDefinitionNode {
    p.debug("parseDirectiveDefinition");
    const description = try parseDescription(p);
    _ = try p.expectKeyword(ast.SyntaxKeyWord.Directive);
    _ = try p.expect(TokenKind.At);

    const name = try parseName(p);
    const args = try parseArgumentDefs(p);
    const repeatable = try p.expectOptionalKeyword(ast.SyntaxKeyWord.Repeatable);
    _ = try p.expectKeyword(ast.SyntaxKeyWord.On);

    const locations = try parseDirectiveLocations(p);
    return ast.DirectiveDefinitionNode{
        .description = description,
        .name = name,
        .arguments = args,
        .repeatable = repeatable,
        .locations = locations,
    };
}

pub fn parseDirectiveLocations(p: *Parser) ![]ast.NameNode {
    p.debug("parseDirectiveLocations");
    _ = try p.expectOptionalToken(TokenKind.Pipe);

    var nodes = std.ArrayList(ast.NameNode).init(p.allocator);
    errdefer nodes.deinit();
    while (true) {
        const name = try parseDirectiveLocation(p);
        try nodes.append(name);

        if (!try p.expectOptionalToken(TokenKind.Pipe)) {
            break;
        }
    }
    return try nodes.toOwnedSlice();
}

pub fn parseDirectiveLocation(p: *Parser) !ast.NameNode {
    p.debug("parseDirectiveLocation");
    const token = try p.peek();
    if (!ast.is_directive_location(token.data)) {
        return error.UnknownDirectiveLocation;
    }

    const name = try parseName(p);
    return name;
}

pub fn parseConstDirectives(p: *Parser) !?[]ast.DirectiveNode {
    p.debug("parseConstDirectives");
    return parseDirectives(p, true);
}

pub fn parseDirectives(p: *Parser, is_const: bool) !?[]ast.DirectiveNode {
    p.debug("parseDirectives");
    if (!try p.peekKind(TokenKind.At)) {
        return null;
    }

    var nodes = std.ArrayList(ast.DirectiveNode).init(p.allocator);
    errdefer nodes.deinit();
    while (try p.peekKind(TokenKind.At)) {
        const dir = try parseDirective(p, is_const);
        try nodes.append(dir);
    }

    return try nodes.toOwnedSlice();
}

pub fn parseDirective(p: *Parser, is_const: bool) !ast.DirectiveNode {
    p.debug("parseDirective");
    _ = try p.expect(TokenKind.At);
    const name = try parseName(p);
    const arguments = try parseArguments(p, is_const);
    return ast.DirectiveNode{
        .name = name,
        .arguments = arguments,
    };
}

//
// Test cases for directive
//

test "should parse a directive definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ directive @auth on FIELD_DEFINITION
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();
    try std.testing.expect(doc.definitions.len == 1);

    const dn = doc.definitions[0];
    try std.testing.expect(dn == ast.DefinitionNode.TypeSystemDefinition);

    const def = dn.TypeSystemDefinition;
    try std.testing.expect(def == ast.TypeSystemDefinitionNode.DirectiveDefinition);

    const dir_def = def.DirectiveDefinition;
    try std.testing.expect(dir_def.description == null);
    try std.testing.expect(std.mem.eql(u8, dir_def.name.value, "auth"));
}

test "should parse a directive definition with arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ directive @deprecated(
        \\   reason: String = "No longer supported"
        \\   removeDate: String
        \\ ) on FIELD_DEFINITION | ENUM_VALUE
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();
    try std.testing.expect(doc.definitions.len == 1);

    const dn = doc.definitions[0];
    try std.testing.expect(dn == ast.DefinitionNode.TypeSystemDefinition);

    const def = dn.TypeSystemDefinition;
    try std.testing.expect(def == ast.TypeSystemDefinitionNode.DirectiveDefinition);

    const dir_def = def.DirectiveDefinition;
    try std.testing.expect(dir_def.description == null);
    try std.testing.expect(std.mem.eql(u8, dir_def.name.value, "deprecated"));

    // Verify arguments are parsed correctly
    try std.testing.expect(dir_def.arguments != null);
    try std.testing.expect(dir_def.arguments.?.len == 2);

    const args = dir_def.arguments.?;
    try std.testing.expect(std.mem.eql(u8, args[0].name.value, "reason"));
    try std.testing.expect(args[0].type.* == ast.TypeNode.NamedType);
    try std.testing.expect(std.mem.eql(u8, args[0].type.*.NamedType.name.value, "String"));
    try std.testing.expect(args[0].default_value != null);

    try std.testing.expect(std.mem.eql(u8, args[1].name.value, "removeDate"));
    try std.testing.expect(args[1].type.* == ast.TypeNode.NamedType);
    try std.testing.expect(std.mem.eql(u8, args[1].type.*.NamedType.name.value, "String"));
    try std.testing.expect(args[1].default_value == null);

    // Verify repeatable is false
    try std.testing.expect(dir_def.repeatable == false);

    // Verify locations
    try std.testing.expect(dir_def.locations.len == 2);
    try std.testing.expect(std.mem.eql(u8, dir_def.locations[0].value, "FIELD_DEFINITION"));
    try std.testing.expect(std.mem.eql(u8, dir_def.locations[1].value, "ENUM_VALUE"));
}

test "should parse a field with a single directive without arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ query {
        \\   user @deprecated {
        \\     id
        \\   }
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();

    try std.testing.expect(doc.definitions.len == 1);
    const op = doc.definitions[0].ExecutableDefinition.OperationDefinition;
    const field = op.selection_set.?.selections[0].Field;

    try std.testing.expect(std.mem.eql(u8, field.name.value, "user"));
    try std.testing.expect(field.directives != null);
    try std.testing.expect(field.directives.?.len == 1);

    const directive = field.directives.?[0];
    try std.testing.expect(std.mem.eql(u8, directive.name.value, "deprecated"));
    try std.testing.expect(directive.arguments == null);
}

test "should parse a field with a directive with arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ query {
        \\   user @deprecated(reason: "Use newUser instead") {
        \\     id
        \\   }
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();

    const op = doc.definitions[0].ExecutableDefinition.OperationDefinition;
    const field = op.selection_set.?.selections[0].Field;

    try std.testing.expect(field.directives != null);
    try std.testing.expect(field.directives.?.len == 1);

    const directive = field.directives.?[0];
    try std.testing.expect(std.mem.eql(u8, directive.name.value, "deprecated"));
    try std.testing.expect(directive.arguments != null);
    try std.testing.expect(directive.arguments.?.len == 1);

    const arg = directive.arguments.?[0];
    try std.testing.expect(std.mem.eql(u8, arg.name.value, "reason"));
    try std.testing.expect(arg.value == ast.ValueNode.String);
    try std.testing.expect(std.mem.eql(u8, arg.value.String.value, "\"Use newUser instead\""));
}
