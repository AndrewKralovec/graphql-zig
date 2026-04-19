const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateField(
    ctx: *Validator,
    // TODO: document: &ExecutableDocument, what should we do with this?
    // May be None if a parent selection was invalid
    against_type: ?[]const u8, // TODO: what type should this be?
    field: ast.FieldNode,
    // TODO: context: &mut OperationValidationContext<'_>, what should we do with this?
) anyerror!void {
    _ = ctx;
    _ = field;
    _ = against_type;
    // TODO: add validation logic
}

pub fn validateFieldDefinition(
    ctx: *Validator,
    // TODO: built_in_scalars: &mut BuiltInScalars, what should we do with this?
    field_def: ast.FieldDefinitionNode,
) anyerror!void {
    _ = ctx;
    _ = field_def;
    // TODO: add validation logic
}

pub fn validateFieldDefinitions(
    ctx: *Validator,
    // TODO: built_in_scalars: &mut BuiltInScalars, what should we do with this?
    fields: []const ast.FieldDefinitionNode,
) anyerror!void {
    _ = ctx;
    _ = fields;
    // TODO: add validation logic
}

pub fn validateLeafFieldSelection(
    ctx: *Validator,
    parent_type: []const u8, // TODO: what type should this be?
    field: ast.FieldNode,
    // field_type: &ast::Type, what should we do with this?
) anyerror!void {
    _ = ctx;
    _ = parent_type;
    _ = field;
    // TODO: add validation logic
}
