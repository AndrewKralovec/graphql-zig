const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;

const max_walk_depth = 500; // TODO: This should be configurable

pub fn validateVariableDefinitions(
    ctx: *DiagnosticList,
    schema: ?*const Schema,
    variable_definitions: []const ast.VariableDefinitionNode,
) !void {
    _ = ctx;
    _ = schema;
    _ = variable_definitions;
    // TODO: add validation logic
}

const WalkError = error{RecursionLimitExceeded} || std.mem.Allocator.Error;

/// Call a function for every selection that is reachable from the given selection set.
fn walkSelectionsWithDedupedFragments(
    exec_doc: *const ExecutableDocument,
    selection_set: ast.SelectionSetNode,
    used: *std.StringHashMap(void),
    seen_fragments: *std.StringHashMap(void),
    depth: usize,
) WalkError!void {
    if (depth >= max_walk_depth) return error.RecursionLimitExceeded;

    for (selection_set.selections) |selection| {
        switch (selection) {
            .Field => |field| {
                variablesInDirectives(field.directives, used);
                variablesInArguments(field.arguments, used);
                if (field.selection_set) |nested_sel_set| {
                    try walkSelectionsWithDedupedFragments(exec_doc, nested_sel_set, used, seen_fragments, depth + 1);
                }
            },
            .FragmentSpread => |spread| {
                variablesInDirectives(spread.directives, used);
                const frag_def = exec_doc.getFragment(spread.name.value) orelse continue;
                const gop = try seen_fragments.getOrPut(spread.name.value);
                if (gop.found_existing) continue;
                variablesInDirectives(frag_def.directives, used);
                try walkSelectionsWithDedupedFragments(exec_doc, frag_def.selection_set, used, seen_fragments, depth + 1);
            },
            .InlineFragment => |inline_frag| {
                variablesInDirectives(inline_frag.directives, used);
                try walkSelectionsWithDedupedFragments(exec_doc, inline_frag.selection_set, used, seen_fragments, depth + 1);
            },
        }
    }
}

fn variablesInValue(value: ast.ValueNode, unused_vars: *std.StringHashMap(void)) void {
    switch (value) {
        .Variable => |v| {
            _ = unused_vars.remove(v.name.value);
        },
        .List => |list| {
            for (list.values) |item| {
                variablesInValue(item, unused_vars);
            }
        },
        .Object => |obj| {
            for (obj.fields) |field| {
                variablesInValue(field.value, unused_vars);
            }
        },
        else => {},
    }
}

fn variablesInArguments(arguments: ?[]const ast.ArgumentNode, unused_vars: *std.StringHashMap(void)) void {
    const args = arguments orelse return;
    for (args) |arg| {
        variablesInValue(arg.value, unused_vars);
    }
}

fn variablesInDirectives(directives: ?[]const ast.DirectiveNode, unused_vars: *std.StringHashMap(void)) void {
    const dirs = directives orelse return;
    for (dirs) |dir| {
        variablesInArguments(dir.arguments, unused_vars);
    }
}

pub fn validateUnusedVariables(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    operation: ast.OperationDefinitionNode,
) !void {
    const var_defs = operation.variable_definitions orelse return;
    if (var_defs.len == 0) return;

    // Start off by considering all variables unused: names are removed from this as we find them.
    var unused_vars = std.StringHashMap(void).init(diagnostics.allocator);
    defer unused_vars.deinit();

    for (var_defs) |var_def| {
        try unused_vars.put(var_def.variable.name.value, {});
    }

    // You're allowed to do `query($var: Int!) @dir(arg: $var) {}`
    variablesInDirectives(operation.directives, &unused_vars);

    if (operation.selection_set) |sel_set| {
        var seen_fragments = std.StringHashMap(void).init(diagnostics.allocator);
        defer seen_fragments.deinit();

        walkSelectionsWithDedupedFragments(
            exec_doc,
            sel_set,
            &unused_vars,
            &seen_fragments,
            0,
        ) catch |err| switch (err) {
            error.RecursionLimitExceeded => {
                try diagnostics.push(.RecursionError);
                return;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    var it = unused_vars.iterator();
    while (it.next()) |_| {
        try diagnostics.push(.UnusedVariable);
    }
}

pub fn validateVariableUsage(
    diagnostics: *DiagnosticList,
    var_usage: ast.InputValueDefinitionNode,
    var_defs: []const ast.VariableDefinitionNode,
    argument: ast.ArgumentNode,
) !void {
    _ = diagnostics;
    _ = var_usage;
    _ = var_defs;
    _ = argument;
    // TODO: check if argument value is a Variable
    // TODO: find the matching VariableDefinition by name
    // TODO: call isVariableUsageAllowed and push DisallowedVariableUsage diagnostic if not
}

fn isVariableUsageAllowed(
    variable_def: ast.VariableDefinitionNode,
    variable_usage: ast.InputValueDefinitionNode,
) bool {
    _ = variable_def;
    _ = variable_usage;
    // TODO: implement spec rule — https://spec.graphql.org/draft/#sec-All-Variable-Usages-Are-Allowed
    return true;
}
