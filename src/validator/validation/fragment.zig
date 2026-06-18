const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const OperationValidationContext = @import("../validator.zig").OperationValidationContext;

const validateSelectionSet = @import("./selection.zig").validateSelectionSet;

/// Given a type definition, find all the type names that can be used for fragment spreading.
///
/// Spec: https://spec.graphql.org/October2021/#GetPossibleTypes()
fn getPossibleTypes(
    allocator: std.mem.Allocator,
) !std.StringHashMap(void) {
    _ = allocator;
    // TODO: add validation logic
}

pub fn validateFragmentSpreadType(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateInlineFragment(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    against_type: ?ast.NamedTypeNode,
    inline_fragment: ast.InlineFragmentNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    // TODO: validate directives on inline fragment at InlineFragment location
    // TODO: validate type condition exists in schema and is a composite type
    // TODO: validate type applicability,inline spread's type condition must

    const fragment_against_type: ?ast.NamedTypeNode = if (inline_fragment.type_condition) |type_cond|
        type_cond
    else
        against_type;

    try validateSelectionSet(diagnostics, exec_doc, fragment_against_type, inline_fragment.selection_set, context);
}

pub fn validateFragmentSpread(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    against_type: ?ast.NamedTypeNode,
    spread: ast.FragmentSpreadNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    // TODO: validate directives on fragment spread at FragmentSpread location
    // TODO: push UndefinedFragment error when fragment name not found
    // TODO: validate type applicability, spread's type condition must overlap
    _ = against_type;
    const frag_def = exec_doc.getFragment(spread.name.value) orelse return;
    const gop = try context.validated_fragments.getOrPut(spread.name.value);
    if (gop.found_existing) return;

    const fragment_against_type: ?ast.NamedTypeNode = frag_def.type_condition;
    try validateSelectionSet(diagnostics, exec_doc, fragment_against_type, frag_def.selection_set, context);
}

pub fn validateFragmentDefinition(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    against_type: ?ast.NamedTypeNode,
    fragment: ast.FragmentDefinitionNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    _ = against_type;
    // TODO: validate directives on fragment definition at FragmentDefinition location
    // TODO: validate type condition exists in schema and is a composite type

    const fragment_against_type: ?ast.NamedTypeNode = fragment.type_condition;
    try validateSelectionSet(diagnostics, exec_doc, fragment_against_type, fragment.selection_set, context);
}

fn validateFragmentCycles(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateFragmentTypeDefinitionCondition(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}

fn collectUsedFragments(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}

fn validateFragmentsUsed(
    ctx: *Validator,
) anyerror!void {
    _ = ctx;
    // TODO: add validation logic
}
