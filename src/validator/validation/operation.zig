const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const ExecutableValidationContext = @import("../validator.zig").ExecutableValidationContext;

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
    _ = diagnostics;
    _ = exec_doc;
    _ = operation;
    _ = context;
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
