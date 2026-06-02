const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const OperationValidationContext = @import("../validator.zig").OperationValidationContext;
const validateField = @import("./field.zig").validateField;
const validateFragmentSpread = @import("./fragment.zig").validateFragmentSpread;
const validateInlineFragment = @import("./fragment.zig").validateInlineFragment;

pub fn validateSelectionSet(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    against_type: ?ast.NamedTypeNode,
    selection_set: ast.SelectionSetNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    for (selection_set.selections) |selection| {
        switch (selection) {
            .Field => |field| try validateField(diagnostics, exec_doc, against_type, field, context),
            .FragmentSpread => |spread| try validateFragmentSpread(diagnostics, exec_doc, against_type, spread, context),
            .InlineFragment => |inline_frag| try validateInlineFragment(diagnostics, exec_doc, against_type, inline_frag, context),
        }
    }
}
