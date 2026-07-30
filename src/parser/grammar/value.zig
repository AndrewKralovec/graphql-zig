const std = @import("std");
const ast = @import("../../ast/ast.zig");
const Parser = @import("../parser.zig").Parser;
const TokenKind = @import("../../lexer/tokens.zig").TokenKind;

const parseName = @import("./name.zig").parseName;
const parseVariable = @import("./variable.zig").parseVariable;

pub fn parseValueLiteral(p: *Parser, is_const: bool) anyerror!ast.ValueNode {
    p.debug("parseValueLiteral");
    const token = try p.peek();

    switch (token.kind) {
        TokenKind.LBracket => {
            const list = try parseList(p, is_const);
            return ast.ValueNode{
                .List = list,
            };
        },
        TokenKind.LCurly => {
            const obj = try parseObject(p, is_const);
            return ast.ValueNode{
                .Object = obj,
            };
        },
        TokenKind.Int => {
            _ = try p.pop();
            return ast.ValueNode{
                .Int = ast.IntValueNode{
                    .value = token.data,
                },
            };
        },
        TokenKind.Float => {
            _ = try p.pop();
            return ast.ValueNode{
                .Float = ast.FloatValueNode{
                    .value = token.data,
                },
            };
        },
        TokenKind.StringValue => {
            const str = try parseStringLiteral(p);
            return ast.ValueNode{ .String = str };
        },
        TokenKind.Name => {
            _ = try p.pop();

            if (std.mem.eql(u8, token.data, "true")) {
                return ast.ValueNode{
                    .Boolean = ast.BooleanValueNode{ .value = true },
                };
            } else if (std.mem.eql(u8, token.data, "false")) {
                return ast.ValueNode{
                    .Boolean = ast.BooleanValueNode{ .value = false },
                };
            } else if (std.mem.eql(u8, token.data, "null")) {
                return ast.ValueNode{
                    .Null = ast.NullValueNode{},
                };
            } else {
                return ast.ValueNode{
                    .Enum = ast.EnumValueNode{
                        .value = token.data,
                    },
                };
            }
        },
        TokenKind.Dollar => {
            if (is_const) {
                _ = try p.expect(TokenKind.Dollar);

                if (try p.peekKind(TokenKind.Name)) {
                    return error.UnexpectedVariable;
                } else {
                    return error.UnexpectedToken;
                }
            }

            const variable = try parseVariable(p);
            return ast.ValueNode{ .Variable = variable };
        },
        else => {
            return error.UnexpectedToken;
        },
    }
    return error.UnexpectedToken;
}

pub fn parseConstValueLiteral(p: *Parser) !ast.ValueNode {
    p.debug("parseConstValueLiteral");
    return parseValueLiteral(p, true);
}

pub fn parseList(p: *Parser, is_const: bool) !ast.ListValueNode {
    p.debug("parseList");
    _ = try p.expect(TokenKind.LBracket);

    var nodes = std.ArrayList(ast.ValueNode).init(p.allocator);
    errdefer nodes.deinit();
    while (!try p.expectOptionalToken(TokenKind.RBracket)) {
        const value = try parseValueLiteral(p, is_const);
        try nodes.append(value);
    }

    return ast.ListValueNode{
        .values = try nodes.toOwnedSlice(),
    };
}

pub fn parseObject(p: *Parser, is_const: bool) !ast.ObjectValueNode {
    p.debug("parseObject");
    _ = try p.expect(TokenKind.LCurly);

    var nodes = std.ArrayList(ast.ObjectFieldNode).init(p.allocator);
    errdefer nodes.deinit();
    while (!try p.expectOptionalToken(TokenKind.RCurly)) {
        const field = try parseObjectField(p, is_const);
        try nodes.append(field);
    }

    return ast.ObjectValueNode{
        .fields = try nodes.toOwnedSlice(),
    };
}

pub fn parseObjectField(p: *Parser, is_const: bool) !ast.ObjectFieldNode {
    p.debug("parseObjectField");
    const name = try parseName(p);
    _ = try p.expect(TokenKind.Colon);
    const value = try parseValueLiteral(p, is_const);
    return ast.ObjectFieldNode{
        .name = name,
        .value = value,
    };
}

pub fn parseStringLiteral(p: *Parser) !ast.StringValueNode {
    p.debug("parseStringLiteral");
    const token = try p.pop();
    return ast.StringValueNode{
        .value = token.data,
    };
}

//
// Test cases for value
//

test "should parse int and string argument values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ {
        \\   user(id: 42, name: "Alice")
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();

    const op = doc.definitions[0].ExecutableDefinition.OperationDefinition;
    const field = op.selection_set.?.selections[0].Field;
    const args = field.arguments.?;
    try std.testing.expect(args.len == 2);

    try std.testing.expect(std.mem.eql(u8, args[0].name.value, "id"));
    try std.testing.expect(args[0].value == ast.ValueNode.Int);
    try std.testing.expect(std.mem.eql(u8, args[0].value.Int.value, "42"));

    try std.testing.expect(std.mem.eql(u8, args[1].name.value, "name"));
    try std.testing.expect(args[1].value == ast.ValueNode.String);
    try std.testing.expect(std.mem.eql(u8, args[1].value.String.value, "\"Alice\""));
}

test "should parse boolean, null, and enum values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const source =
        \\ {
        \\   user(active: true, deleted: false, middle: null, role: ADMIN)
        \\ }
    ;
    var p = Parser.init(allocator, source, .{});
    const doc = try p.parse();

    const op = doc.definitions[0].ExecutableDefinition.OperationDefinition;
    const field = op.selection_set.?.selections[0].Field;
    const args = field.arguments.?;
    try std.testing.expect(args.len == 4);

    try std.testing.expect(args[0].value == ast.ValueNode.Boolean);
    try std.testing.expect(args[0].value.Boolean.value == true);

    try std.testing.expect(args[1].value == ast.ValueNode.Boolean);
    try std.testing.expect(args[1].value.Boolean.value == false);

    try std.testing.expect(args[2].value == ast.ValueNode.Null);

    try std.testing.expect(args[3].value == ast.ValueNode.Enum);
    try std.testing.expect(std.mem.eql(u8, args[3].value.Enum.value, "ADMIN"));
}
