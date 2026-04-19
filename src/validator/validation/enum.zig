const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateEnumDefinition(ctx: *Validator, enum_def: ast.EnumTypeDefinitionNode) anyerror!void {
    _ = ctx;
    _ = enum_def;
    // TODO: add validation logic
}

fn validateEnumValue(ctx: *Validator, enum_val: ast.EnumValueDefinitionNode) anyerror!void {
    _ = ctx;
    _ = enum_val;
    // TODO: add validation logic
}

pub fn validateEnumExtension(ctx: *Validator, enum_ext: ast.EnumTypeExtensionNode) anyerror!void {
    _ = ctx;
    _ = enum_ext;
    // TODO: add validation logic
}
