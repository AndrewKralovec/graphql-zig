const std = @import("std");
const ast = @import("../../ast/ast.zig");
const Parser = @import("../parser.zig").Parser;
const TokenKind = @import("../../lexer/tokens.zig").TokenKind;

const parseField = @import("./field.zig").parseField;
const parseFragmentName = @import("./fragment.zig").parseFragmentName;
const parseDirectives = @import("./directive.zig").parseDirectives;
const parseNamedType = @import("./type.zig").parseNamedType;

pub fn parseSelectionSet(p: *Parser) anyerror!ast.SelectionSetNode {
    p.debug("parseSelectionSet");
    const selections = try parseSelections(p);
    const node = ast.SelectionSetNode{
        .selections = selections,
    };
    return node;
}

pub fn parseSelections(p: *Parser) ![]ast.SelectionNode {
    p.debug("parseSelections");
    var nodes = std.ArrayList(ast.SelectionNode).init(p.allocator);
    errdefer nodes.deinit();

    _ = try p.expect(TokenKind.LCurly);
    while (true) {
        const sel = try parseSelection(p);
        try nodes.append(sel);

        if (try p.expectOptionalToken(TokenKind.RCurly)) {
            break;
        }
    }
    return nodes.toOwnedSlice();
}

pub fn parseSelection(p: *Parser) !ast.SelectionNode {
    p.debug("parseSelection");
    const token = try p.peek();
    // Field.
    if (token.kind != TokenKind.Spread) {
        const field = try parseField(p);
        return ast.SelectionNode{ .Field = field };
    }

    // Fragment spread.
    _ = try p.expect(TokenKind.Spread);
    const has_type_condition = try p.expectOptionalKeyword(ast.SyntaxKeyWord.On);
    if (!has_type_condition and try p.peekKind(TokenKind.Name)) {
        const name = try parseFragmentName(p);
        const directives = try parseDirectives(p, false);
        return ast.SelectionNode{
            .FragmentSpread = ast.FragmentSpreadNode{
                .name = name,
                .directives = directives,
            },
        };
    }

    // Inline Fragment.
    var type_condition: ?ast.NamedTypeNode = null;
    if (has_type_condition) {
        type_condition = try parseNamedType(p);
    }

    const directives = try parseDirectives(p, false);
    const selection_set = try parseSelectionSet(p);

    return ast.SelectionNode{
        .InlineFragment = ast.InlineFragmentNode{
            .type_condition = type_condition,
            .directives = directives,
            .selection_set = selection_set,
        },
    };
}

//
// Test cases for selection
//

test "should parse a selection set with multiple fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ {
        \\   id
        \\   name
        \\   email
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();

    const op = doc.definitions[0].ExecutableDefinition.OperationDefinition;
    const selections = op.selection_set.?.selections;
    try std.testing.expect(selections.len == 3);

    try std.testing.expect(selections[0] == ast.SelectionNode.Field);
    try std.testing.expect(std.mem.eql(u8, selections[0].Field.name.value, "id"));

    try std.testing.expect(selections[1] == ast.SelectionNode.Field);
    try std.testing.expect(std.mem.eql(u8, selections[1].Field.name.value, "name"));

    try std.testing.expect(selections[2] == ast.SelectionNode.Field);
    try std.testing.expect(std.mem.eql(u8, selections[2].Field.name.value, "email"));
}

test "should parse a fragment spread in a selection set" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ {
        \\   id
        \\   ...UserFields
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();

    const op = doc.definitions[0].ExecutableDefinition.OperationDefinition;
    const selections = op.selection_set.?.selections;
    try std.testing.expect(selections.len == 2);

    try std.testing.expect(selections[0] == ast.SelectionNode.Field);
    try std.testing.expect(std.mem.eql(u8, selections[0].Field.name.value, "id"));

    try std.testing.expect(selections[1] == ast.SelectionNode.FragmentSpread);
    try std.testing.expect(std.mem.eql(u8, selections[1].FragmentSpread.name.value, "UserFields"));
}
