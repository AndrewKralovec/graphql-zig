const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const OperationValidationContext = @import("../validator.zig").OperationValidationContext;

pub fn validateSelectionSet(
    ctx: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    selection_set: ast.SelectionSetNode,
    context: *OperationValidationContext,
) !void {
    _ = ctx;
    _ = exec_doc;
    _ = selection_set;
    _ = context;
    // TODO: add validation logic
}
