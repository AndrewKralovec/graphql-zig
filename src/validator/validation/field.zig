const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const OperationValidationContext = @import("../validator.zig").OperationValidationContext;
const Schema = @import("../validator.zig").Schema;

const validateSelectionSet = @import("./selection.zig").validateSelectionSet;

pub fn validateField(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    // May be None if a parent selection was invalid
    against_type: ?ast.NamedTypeNode,
    field: ast.FieldNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    var nested_against_type: ?ast.NamedTypeNode = null;

    if (against_type) |at| {
        if (context.schema()) |s| {
            if (s.typeField(at, field.name.value)) |field_def| {
                nested_against_type = field_def.type.innerNamedType();
            }
        }
    }

    if (field.selection_set) |sel_set| {
        try validateSelectionSet(diagnostics, exec_doc, nested_against_type, sel_set, context);
    }
}

pub fn validateFieldDefinition(
    ctx: *Validator,
    field_def: ast.FieldDefinitionNode,
) anyerror!void {
    _ = ctx;
    _ = field_def;
    // TODO: add validation logic
}

pub fn validateFieldDefinitions(
    ctx: *Validator,
    fields: []const ast.FieldDefinitionNode,
) anyerror!void {
    _ = ctx;
    _ = fields;
    // TODO: add validation logic
}

pub fn validateLeafFieldSelection(
    ctx: *Validator,
    parent_type: []const u8,
    field: ast.FieldNode,
) anyerror!void {
    _ = ctx;
    _ = parent_type;
    _ = field;
    // TODO: add validation logic
}
