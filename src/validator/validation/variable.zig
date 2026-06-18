const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;

const validateDirectives = @import("./directive.zig").validateDirectives;
const valueOfCorrectType = @import("./value.zig").valueOfCorrectType;

// This has a much higher limit than comparable recursive walks, like the one in
// `validate_fragment_cycles`, despite doing similar work. This is because this limit
// was introduced later and should not break (reasonable) existing queries that are
// under that pre-existing limit. Luckily the existing limit was very conservative.
const max_walk_depth = 500; // TODO: This should be configurable

pub fn validateVariableDefinitions(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: ?*const Schema,
    variable_definitions: []const ast.VariableDefinitionNode,
) !void {
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    for (variable_definitions) |variable| {
        try validateDirectives(
            allocator,
            diagnostics,
            schema,
            variable.directives,
            .VariableDefinition,
            // let's assume that variable definitions cannot reference other
            // variables and provide them as arguments to directives
            &[_]ast.VariableDefinitionNode{},
        );

        if (schema) |s| {
            const ty = variable.type;
            const type_def = s.type_definitions.get(ty.innerNamedType().name.value);

            if (type_def) |td| {
                if (td.isInputType()) {
                    if (variable.default_value) |default| {
                        // Default values are "const", not allowed to refer to other variables:
                        const var_defs_in_scope = [_]ast.VariableDefinitionNode{};
                        try valueOfCorrectType(diagnostics, s, ty, default, &var_defs_in_scope);
                    }
                } else {
                    try diagnostics.push(.VariableInputType);
                }
            } else {
                try diagnostics.push(.UndefinedDefinition);
            }
        }

        const original = try seen.getOrPut(variable.variable.name.value);
        if (original.found_existing) {
            try diagnostics.push(.UniqueVariable);
        }
    }
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
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    operation: ast.OperationDefinitionNode,
) !void {
    const var_defs = operation.variable_definitions orelse return;
    if (var_defs.len == 0) return;

    // Start off by considering all variables unused: names are removed from this as we find them.
    var unused_vars = std.StringHashMap(void).init(allocator);
    defer unused_vars.deinit();

    for (var_defs) |var_def| {
        try unused_vars.put(var_def.variable.name.value, {});
    }

    // You're allowed to do `query($var: Int!) @dir(arg: $var) {}`
    variablesInDirectives(operation.directives, &unused_vars);

    if (operation.selection_set) |sel_set| {
        var seen_fragments = std.StringHashMap(void).init(allocator);
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
) !bool {
    const var_name = switch (argument.value) {
        .Variable => |v| v.name.value,
        else => return true,
    };

    // Let var_def be the VariableDefinition named
    // variable_name defined within operation.
    const var_def = for (var_defs) |def| {
        if (std.mem.eql(u8, def.variable.name.value, var_name)) break def;
    } else return true; // If the variable is not defined, we raise an error in `value.zig`

    if (!isVariableUsageAllowed(var_def, var_usage)) {
        try diagnostics.push(.DisallowedVariableUsage);
        return false;
    }
    return true;
}

// https://spec.graphql.org/draft/#sec-All-Variable-Usages-Are-Allowed
fn isVariableUsageAllowed(
    variable_def: ast.VariableDefinitionNode,
    variable_usage: ast.InputValueDefinitionNode,
) bool {
    // 1. Let variable_ty be the expected type of variable_def.
    const variable_ty = variable_def.type;
    // 2. Let location_ty be the expected type of the Argument,
    // ObjectField, or ListValue entry where variableUsage is
    // located.
    const location_ty = variable_usage.type;
    // 3. if location_ty is a non-null type AND variable_ty is
    // NOT a non-null type:
    if (location_ty.isNonNull() and !variable_ty.isNonNull()) {
        // 3.a. let hasNonNullVariableDefaultValue be true
        // if a default value exists for variableDefinition
        // and is not the value null.
        const has_non_null_variable_default = variable_def.default_value != null;
        // 3.b. Let hasLocationDefaultValue be true if a default
        // value exists for the Argument or ObjectField where
        // variableUsage is located.
        const has_location_default = variable_usage.default_value != null;
        // 3.c. If hasNonNullVariableDefaultValue is NOT true
        // AND hasLocationDefaultValue is NOT true, return
        // false.
        if (!has_non_null_variable_default and !has_location_default) {
            return false;
        }

        // 3.d. Let nullable_location_ty be the unwrapped
        // nullable type of location_ty.
        return variable_ty.isAssignableTo(location_ty.nullable());
    }

    return variable_ty.isAssignableTo(location_ty);
}
