const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ValidationErrorKind = @import("../validator.zig").ValidationErrorKind;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const ExecutableValidationContext = @import("../validator.zig").ExecutableValidationContext;
const validateDirectives = @import("./directive.zig").validateDirectives;
const validateSelectionSet = @import("./selection.zig").validateSelectionSet;
const validateVariableDefinitions = @import("./variable.zig").validateVariableDefinitions;
const validateUnusedVariables = @import("./variable.zig").validateUnusedVariables;

const walk_depth_limit: u32 = 500;

/// Iterate all selections in the selection set.
///
/// This includes fields, fragment spreads, and inline fragments. For fragments, both the spread
/// and the fragment's nested selections are reported.
///
/// Does not recurse into nested fields.
fn walkSelections(
    comptime Context: type,
    comptime recurse_fields: bool,
    comptime recurse_fragments: bool,
    exec_doc: *const ExecutableDocument,
    selections: []const ast.SelectionNode,
    seen_fragments: *std.StringHashMap(void),
    depth: u32,
    ctx: *Context,
    comptime visitor: fn (*Context, ast.SelectionNode) anyerror!void,
) anyerror!void {
    if (depth > walk_depth_limit) return error.RecursionLimitExceeded;
    for (selections) |sel| {
        try visitor(ctx, sel);
        switch (sel) {
            .Field => |field| {
                if (recurse_fields) {
                    if (field.selection_set) |sub| {
                        try walkSelections(Context, recurse_fields, recurse_fragments, exec_doc, sub.selections, seen_fragments, depth + 1, ctx, visitor);
                    }
                }
            },
            .FragmentSpread => |spread| {
                if (recurse_fragments) {
                    const gop = try seen_fragments.getOrPut(spread.name.value);
                    if (!gop.found_existing) {
                        if (exec_doc.getFragment(spread.name.value)) |frag| {
                            try walkSelections(Context, recurse_fields, recurse_fragments, exec_doc, frag.selection_set.selections, seen_fragments, depth + 1, ctx, visitor);
                        }
                    }
                }
            },
            .InlineFragment => |il| {
                try walkSelections(Context, recurse_fields, recurse_fragments, exec_doc, il.selection_set.selections, seen_fragments, depth + 1, ctx, visitor);
            },
        }
    }
}

const SubscriptionWalkCtx = struct {
    diagnostics: *DiagnosticList,
    field_count: u32 = 0,
};

fn visitSubscriptionRoot(ctx: *SubscriptionWalkCtx, sel: ast.SelectionNode) anyerror!void {
    const dirs_opt: ?[]const ast.DirectiveNode = switch (sel) {
        .Field => |f| f.directives,
        .FragmentSpread => |fs| fs.directives,
        .InlineFragment => |il| il.directives,
    };
    if (dirs_opt) |dirs| {
        for (dirs) |dir| {
            const n = dir.name.value;
            if (std.mem.eql(u8, n, "skip") or std.mem.eql(u8, n, "include")) {
                try ctx.diagnostics.push(.SubscriptionUsesConditionalSelection);
                break;
            }
        }
    }

    const field = switch (sel) {
        .Field => |f| f,
        .FragmentSpread, .InlineFragment => return,
    };
    ctx.field_count += 1;
    const name = field.name.value;
    if (std.mem.eql(u8, name, "__type") or
        std.mem.eql(u8, name, "__schema") or
        std.mem.eql(u8, name, "__typename"))
    {
        try ctx.diagnostics.push(.SubscriptionUsesIntrospection);
    }
}

pub fn validateSubscription(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    operation: ast.OperationDefinitionNode,
) !void {
    if (operation.operation != .Subscription) return;
    const sel_set = operation.selection_set orelse return;

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var walk_ctx = SubscriptionWalkCtx{ .diagnostics = diagnostics };
    walkSelections(SubscriptionWalkCtx, false, true, exec_doc, sel_set.selections, &seen, 0, &walk_ctx, visitSubscriptionRoot) catch |err| switch (err) {
        error.RecursionLimitExceeded => {
            try diagnostics.push(.RecursionError);
            return;
        },
        else => return err,
    };

    if (walk_ctx.field_count > 1) try diagnostics.push(.SubscriptionUsesMultipleFields);
}

const DeferLabelCtx = struct {
    diagnostics: *DiagnosticList,
    seen_labels: *std.StringHashMap(void),
};

fn visitCheckDeferLabel(ctx: *DeferLabelCtx, sel: ast.SelectionNode) anyerror!void {
    const dirs: ?[]const ast.DirectiveNode = switch (sel) {
        .Field => |f| f.directives,
        .FragmentSpread => |fs| fs.directives,
        .InlineFragment => |il| il.directives,
    };
    const ds = dirs orelse return;
    for (ds) |dir| {
        if (!std.mem.eql(u8, dir.name.value, "defer")) continue;
        const args = dir.arguments orelse continue;
        for (args) |arg| {
            if (!std.mem.eql(u8, arg.name.value, "label")) continue;
            switch (arg.value) {
                .Variable => try ctx.diagnostics.push(.DeferLabelVariable),
                .String => |s| {
                    const gop = try ctx.seen_labels.getOrPut(s.value);
                    if (gop.found_existing) try ctx.diagnostics.push(.UniqueDefer);
                },
                else => {},
            }
        }
    }
}

fn validateDeferLabels(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
) !void {
    var seen_labels = std.StringHashMap(void).init(allocator);
    defer seen_labels.deinit();
    var label_ctx = DeferLabelCtx{ .diagnostics = diagnostics, .seen_labels = &seen_labels };

    if (exec_doc.operations.anonymous) |op| {
        if (op.selection_set) |sel_set| {
            var seen = std.StringHashMap(void).init(allocator);
            defer seen.deinit();
            walkSelections(DeferLabelCtx, true, false, exec_doc, sel_set.selections, &seen, 0, &label_ctx, visitCheckDeferLabel) catch |err| switch (err) {
                error.RecursionLimitExceeded => return,
                else => return err,
            };
        }
    }
    for (exec_doc.operations.named.values()) |op| {
        if (op.selection_set) |sel_set| {
            var seen = std.StringHashMap(void).init(allocator);
            defer seen.deinit();
            walkSelections(DeferLabelCtx, true, false, exec_doc, sel_set.selections, &seen, 0, &label_ctx, visitCheckDeferLabel) catch |err| switch (err) {
                error.RecursionLimitExceeded => return,
                else => return err,
            };
        }
    }
    for (exec_doc.fragments.values()) |frag| {
        var seen = std.StringHashMap(void).init(allocator);
        defer seen.deinit();
        walkSelections(DeferLabelCtx, true, false, exec_doc, frag.selection_set.selections, &seen, 0, &label_ctx, visitCheckDeferLabel) catch |err| switch (err) {
            error.RecursionLimitExceeded => return,
            else => return err,
        };
    }
}

const ForbidRootDeferCtx = struct {
    diagnostics: *DiagnosticList,
    error_kind: ValidationErrorKind,
};

fn visitForbidRootDefer(ctx: *ForbidRootDeferCtx, sel: ast.SelectionNode) anyerror!void {
    const dirs: ?[]const ast.DirectiveNode = switch (sel) {
        .Field => return,
        .FragmentSpread => |fs| fs.directives,
        .InlineFragment => |il| il.directives,
    };
    const ds = dirs orelse return;
    for (ds) |dir| {
        if (std.mem.eql(u8, dir.name.value, "defer")) {
            try ctx.diagnostics.push(ctx.error_kind);
        }
    }
}

fn forbidDeferOnRoot(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    op: ast.OperationDefinitionNode,
    error_kind: ValidationErrorKind,
) !void {
    const sel_set = op.selection_set orelse return;
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();
    var ctx = ForbidRootDeferCtx{ .diagnostics = diagnostics, .error_kind = error_kind };
    walkSelections(ForbidRootDeferCtx, false, true, exec_doc, sel_set.selections, &seen, 0, &ctx, visitForbidRootDefer) catch |err| switch (err) {
        error.RecursionLimitExceeded => return,
        else => return err,
    };
}

fn ifArgValue(dir: ast.DirectiveNode) ?ast.ValueNode {
    const args = dir.arguments orelse return null;
    for (args) |arg| {
        if (std.mem.eql(u8, arg.name.value, "if")) return arg.value;
    }
    return null;
}

fn selectionIsStaticallyExcluded(sel: ast.SelectionNode) bool {
    const dirs: ?[]const ast.DirectiveNode = switch (sel) {
        .Field => |f| f.directives,
        .FragmentSpread => |fs| fs.directives,
        .InlineFragment => |il| il.directives,
    };
    const ds = dirs orelse return false;
    for (ds) |dir| {
        if (std.mem.eql(u8, dir.name.value, "skip")) {
            const if_val = ifArgValue(dir) orelse return true;
            if (if_val == .Boolean and !if_val.Boolean.value) continue;
            return true;
        }
        if (std.mem.eql(u8, dir.name.value, "include")) {
            const if_val = ifArgValue(dir) orelse return true;
            if (if_val == .Boolean and if_val.Boolean.value) continue;
            return true;
        }
    }
    return false;
}

fn deferCanBeDisabled(dir: ast.DirectiveNode) bool {
    const args = dir.arguments orelse return false;
    for (args) |arg| {
        if (!std.mem.eql(u8, arg.name.value, "if")) continue;
        if (arg.value == .Variable) return true;
        if (arg.value == .Boolean and !arg.value.Boolean.value) return true;
    }
    return false;
}

fn forbidUnconditionalDeferInner(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    selections: []const ast.SelectionNode,
    seen_fragments: *std.StringHashMap(void),
    depth: u32,
) !void {
    if (depth > walk_depth_limit) return error.RecursionLimitExceeded;
    for (selections) |sel| {
        if (selectionIsStaticallyExcluded(sel)) continue;

        const dirs: ?[]const ast.DirectiveNode = switch (sel) {
            .Field => |f| f.directives,
            .FragmentSpread => |fs| fs.directives,
            .InlineFragment => |il| il.directives,
        };
        if (dirs) |ds| {
            for (ds) |dir| {
                if (!std.mem.eql(u8, dir.name.value, "defer")) continue;
                if (!deferCanBeDisabled(dir)) {
                    try diagnostics.push(.SubscriptionDeferConditional);
                }
            }
        }

        switch (sel) {
            .Field => |f| {
                if (f.selection_set) |sub| {
                    try forbidUnconditionalDeferInner(allocator, diagnostics, exec_doc, sub.selections, seen_fragments, depth + 1);
                }
            },
            .InlineFragment => |il| {
                try forbidUnconditionalDeferInner(allocator, diagnostics, exec_doc, il.selection_set.selections, seen_fragments, depth + 1);
            },
            .FragmentSpread => |spread| {
                const gop = try seen_fragments.getOrPut(spread.name.value);
                if (gop.found_existing) continue;
                if (exec_doc.getFragment(spread.name.value)) |frag| {
                    try forbidUnconditionalDeferInner(allocator, diagnostics, exec_doc, frag.selection_set.selections, seen_fragments, depth + 1);
                }
            },
        }
    }
}

fn forbidUnconditionalDefer(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    op: ast.OperationDefinitionNode,
) !void {
    const sel_set = op.selection_set orelse return;
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();
    forbidUnconditionalDeferInner(allocator, diagnostics, exec_doc, sel_set.selections, &seen, 0) catch |err| switch (err) {
        error.RecursionLimitExceeded => return,
        else => return err,
    };
}

/// Validate `@defer` directive usage per the GraphQL Defer & Stream spec
/// (PR <https://github.com/graphql/graphql-spec/pull/1110>):
///
/// 1. `@defer(label:)` values must be unique across the document, and the
///    `label` argument must not be a variable.
/// 2. `@defer` is not allowed on root selections of `mutation` or
///    `subscription` operations (recursing through fragment spreads/inline
///    fragments at the root level).
/// 3. In a `subscription` operation, every `@defer` directive that is not
///    statically skipped via `@skip`/`@include` must be disabled via an
///    `if` argument set to `false` or to a variable.
pub fn validateDefer(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
) !void {
    try validateDeferLabels(allocator, diagnostics, exec_doc);

    if (exec_doc.operations.anonymous) |op| {
        switch (op.operation) {
            .Mutation => try forbidDeferOnRoot(allocator, diagnostics, exec_doc, op, .DeferOnRootMutation),
            .Subscription => {
                try forbidDeferOnRoot(allocator, diagnostics, exec_doc, op, .DeferOnRootSubscription);
                try forbidUnconditionalDefer(allocator, diagnostics, exec_doc, op);
            },
            .Query => {},
        }
    }
    for (exec_doc.operations.named.values()) |op| {
        switch (op.operation) {
            .Mutation => try forbidDeferOnRoot(allocator, diagnostics, exec_doc, op, .DeferOnRootMutation),
            .Subscription => {
                try forbidDeferOnRoot(allocator, diagnostics, exec_doc, op, .DeferOnRootSubscription);
                try forbidUnconditionalDefer(allocator, diagnostics, exec_doc, op);
            },
            .Query => {},
        }
    }
}

pub fn validateOperation(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    operation: ast.OperationDefinitionNode,
    context: *ExecutableValidationContext,
) !void {
    const against_type: ?ast.NamedTypeNode = if (context.schema()) |s|
        s.rootOperation(operation.operation)
    else
        null;

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
            context.allocator,
            diagnostics,
            context.schema(),
            var_defs,
        );
    }
    try validateUnusedVariables(
        context.allocator,
        diagnostics,
        exec_doc,
        operation,
    );
    if (operation.selection_set) |sel_set| {
        var op_context = context.operationContext(operation.variable_definitions);
        defer op_context.deinit();

        try validateSelectionSet(
            diagnostics,
            exec_doc,
            against_type,
            sel_set,
            &op_context,
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

fn operationTypeToDirectiveLocation(op_type: ast.OperationType) ast.DirectiveLocation {
    return switch (op_type) {
        .Query => .Query,
        .Mutation => .Mutation,
        .Subscription => .Subscription,
    };
}

const test_helpers = @import("../test_helpers.zig");

test "subscription with __type is rejected" {
    try test_helpers.expectErrors(
        \\ subscription { __type(name: "Foo") { kind } }
    , 1);
}

test "subscription with __schema is rejected" {
    try test_helpers.expectErrors(
        \\ subscription { __schema { types { name } } }
    , 1);
}

test "subscription with __typename is rejected" {
    try test_helpers.expectErrors(
        \\ subscription { __typename }
    , 1);
}

test "subscription with user-defined __-prefixed field is not flagged as introspection" {
    try test_helpers.expectValid(
        \\ subscription { __customField }
    );
}

test "defer label in fragment spread is not double-counted" {
    try test_helpers.expectErrors(
        \\ query { ...F }
        \\ fragment F on Query { field @defer(label: "x") { sub } }
    , 1);
}

test "two fragments with the same defer label are rejected" {
    try test_helpers.expectErrors(
        \\ query { ...F ...G }
        \\ fragment F on Query { field @defer(label: "dup") { sub } }
        \\ fragment G on Query { other @defer(label: "dup") { sub } }
    , 3);
}

test "two operations each spreading the same labelled fragment is valid" {
    try test_helpers.expectErrors(
        \\ query A { ...F }
        \\ query B { ...F }
        \\ fragment F on Query { field @defer(label: "once") { sub } }
    , 2);
}

test "defer inside skip(if:true) inline fragment in subscription is not a false positive" {
    try test_helpers.expectErrors(
        \\ subscription { ... on Sub @skip(if: true) { field @defer { sub } } }
    , 3);
}

test "defer inside include(if:false) inline fragment in subscription is not a false positive" {
    try test_helpers.expectErrors(
        \\ subscription { ... on Sub @include(if: false) { field @defer { sub } } }
    , 3);
}

test "unconditional defer outside excluded block in subscription is still rejected" {
    try test_helpers.expectErrors(
        \\ subscription { ... on Sub @skip(if: false) { field @defer { sub } } }
    , 4);
}
