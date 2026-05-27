const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const ExecutableValidationContext = @import("../validator.zig").ExecutableValidationContext;

const validateDirectives = @import("./directive.zig").validateDirectives;
const validateSelectionSet = @import("./selection.zig").validateSelectionSet;
const validateVariableDefinitions = @import("./variable.zig").validateVariableDefinitions;
const validateUnusedVariables = @import("./variable.zig").validateUnusedVariables;

fn walkSelections() void {
    // TODO: add validation logic
}

pub fn validateSubscription(
    ctx: *Validator,
) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateOperation(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    operation: ast.OperationDefinitionNode,
    context: *ExecutableValidationContext,
) !void {
    // const against_type = // TODO

    const dir_loc = operationTypeToDirectiveLocation(operation.operation);
    const operation_var_defs = operation.variable_definitions orelse &[_]ast.VariableDefinitionNode{};

    try validateDirectives(
        context.allocator,
        diagnostics,
        context.schema(),
        operation.directives,
        dir_loc,
        operation_var_defs,
    );
    if (operation.variable_definitions) |var_defs| {
        try validateVariableDefinitions(
            diagnostics,
            context.schema(),
            var_defs,
        );
    }
    try validateUnusedVariables(diagnostics, exec_doc, operation);
    if (operation.selection_set) |sel_set| {
        try validateSelectionSet(
            diagnostics,
            exec_doc,
            // against_type,
            sel_set,
            // &mut context.operation_context(&operation.variables),
        );
    }
}

pub fn validateOperationDefinitions(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    context: *ExecutableValidationContext,
) !void {
    if (exec_doc.operations.anonymous) |operation| {
        try validateOperation(diagnostics, exec_doc, operation, context);
    }

    for (exec_doc.operations.named.values()) |operation| {
        try validateOperation(diagnostics, exec_doc, operation, context);
    }
}

// TODO: implement operation.operation_type.into(),
// This is a placeholder.
fn operationTypeToDirectiveLocation(op_type: ast.OperationType) ast.DirectiveLocation {
    return switch (op_type) {
        .Query => .Query,
        .Mutation => .Mutation,
        .Subscription => .Subscription,
    };
}
