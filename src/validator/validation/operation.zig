const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const ExecutableValidationContext = @import("../validator.zig").ExecutableValidationContext;

const validateDirectives = @import("./directive.zig").validateDirectives;

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
    _ = exec_doc;

    if (context.schema()) |s| {
        const dir_loc = operationTypeToDirectiveLocation(operation.operation);
        const operation_var_defs = operation.variable_definitions orelse &[_]ast.VariableDefinitionNode{};

        try validateDirectives(
            diagnostics,
            s,
            operation.directives,
            dir_loc,
            operation_var_defs,
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
