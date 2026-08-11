const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const OperationValidationContext = @import("../validator.zig").OperationValidationContext;
const Schema = @import("../validator.zig").Schema;
const ImplementersMap = @import("../context/validation_context.zig").ImplementersMap;

const validateSelectionSet = @import("./selection.zig").validateSelectionSet;
const validateDirectives = @import("./directive.zig").validateDirectives;

/// Given a type definition, find all the type names that can be used for fragment spreading.
///
/// Spec: https://spec.graphql.org/October2021/#GetPossibleTypes()
fn getPossibleTypes(
    allocator: std.mem.Allocator,
    type_def: ast.TypeDefinitionNode,
    implementers_map: *const ImplementersMap,
) !std.StringHashMap(void) {
    var set = std.StringHashMap(void).init(allocator);

    switch (type_def) {
        // 1. If `type` is an object type, return a set containing `type`.
        .ObjectTypeDefinition => |obj| {
            try set.put(obj.name.value, {});
        },
        // 2. If `type` is an interface type, return the set of object types implementing `type`.
        // Uses the pre-built implementers_map instead of scanning all schema types.
        .InterfaceTypeDefinition => |iface| {
            if (implementers_map.get(iface.name.value)) |implementers| {
                var it = implementers.objects.keyIterator();
                while (it.next()) |key| {
                    try set.put(key.*, {});
                }
            }
        },
        // 3. If `type` is a union type, return the set of possible types of `type`.
        .UnionTypeDefinition => |union_def| {
            if (union_def.types) |members| {
                for (members) |member| {
                    try set.put(member.name.value, {});
                }
            }
        },
        else => {},
    }

    return set;
}

// NOTE: apollo-rs also passes document and selection here to produce richer diagnostics
// (fragment name, source location, inline vs named spread distinction)
// that is why it is omitted for now.
fn validateFragmentSpreadType(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    against_type: ast.NamedTypeNode,
    type_condition: ast.NamedTypeNode,
    context: *OperationValidationContext,
) !void {
    // Treat a spread that's just literally on the parent type as always valid:
    // by spec text, it shouldn't be, but graphql-{js,java,go} and others all do this.
    // See https://github.com/graphql/graphql-spec/issues/1109
    if (std.mem.eql(u8, type_condition.name.value, against_type.name.value)) {
        return;
    }

    // Another diagnostic will be raised if the type condition was wrong.
    // We reduce noise by silencing other issues with the fragment.
    const condition_def = schema.type_definitions.get(type_condition.name.value) orelse return;
    // We cannot check anything if the parent type is unknown.
    const against_def = schema.type_definitions.get(against_type.name.value) orelse return;

    const implementers_map = try context.implementersMap();

    var parent_types = try getPossibleTypes(context.allocator, against_def, implementers_map);
    defer parent_types.deinit();

    var condition_types = try getPossibleTypes(context.allocator, condition_def, implementers_map);
    defer condition_types.deinit();

    var has_intersection = false;
    var it = condition_types.keyIterator();
    while (it.next()) |key| {
        if (parent_types.contains(key.*)) {
            has_intersection = true;
            break;
        }
    }

    if (!has_intersection) {
        try diagnostics.push(.InvalidFragmentSpread);
    }
}

pub fn validateInlineFragment(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    against_type: ?ast.NamedTypeNode,
    inline_fragment: ast.InlineFragmentNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    const schema = context.schema();
    const variables = context.variables orelse &[_]ast.VariableDefinitionNode{};
    try validateDirectives(
        context.allocator,
        diagnostics,
        schema,
        inline_fragment.directives,
        .InlineFragment,
        variables,
    );

    const previous = diagnostics.len();
    if (schema) |s| {
        if (inline_fragment.type_condition) |type_cond| {
            try validateFragmentTypeCondition(diagnostics, s, type_cond);
        }
    }
    const has_type_error = diagnostics.len() > previous;

    // If there was an error with the type condition, it makes no sense to validate the selection,
    // as every field would be an error.
    if (!has_type_error) {
        if (schema) |s| {
            if (against_type) |parent| {
                if (inline_fragment.type_condition) |type_cond| {
                    try validateFragmentSpreadType(
                        diagnostics,
                        s,
                        parent,
                        type_cond,
                        context,
                    );
                }
            }
        }

        const fragment_against_type: ?ast.NamedTypeNode = blk: {
            if (context.schema() != null) {
                if (inline_fragment.type_condition) |tc| break :blk tc;
            }
            break :blk against_type;
        };

        try validateSelectionSet(
            diagnostics,
            exec_doc,
            fragment_against_type,
            inline_fragment.selection_set,
            context,
        );
    }
}

pub fn validateFragmentSpread(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    against_type: ?ast.NamedTypeNode,
    spread: ast.FragmentSpreadNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    const schema = context.schema();
    const variables = context.variables orelse &[_]ast.VariableDefinitionNode{};
    try validateDirectives(
        context.allocator,
        diagnostics,
        schema,
        spread.directives,
        .FragmentSpread,
        variables,
    );

    const frag_def = exec_doc.getFragment(spread.name.value) orelse {
        try diagnostics.push(.UndefinedFragment);
        return;
    };

    if (schema) |s| {
        if (against_type) |parent| {
            try validateFragmentSpreadType(
                diagnostics,
                s,
                parent,
                frag_def.type_condition,
                context,
            );
        }
    }

    const gop = try context.validated_fragments.getOrPut(spread.name.value);
    if (gop.found_existing) return;

    try validateFragmentDefinition(diagnostics, exec_doc, frag_def, context);
}

pub fn validateFragmentDefinition(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    fragment: ast.FragmentDefinitionNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    const schema = context.schema();
    const variables = context.variables orelse &[_]ast.VariableDefinitionNode{};
    try validateDirectives(
        context.allocator,
        diagnostics,
        schema,
        fragment.directives,
        .FragmentDefinition,
        variables,
    );

    const previous = diagnostics.len();
    if (schema) |s| {
        try validateFragmentTypeCondition(
            diagnostics,
            s,
            fragment.type_condition,
        );
    }
    const has_type_error = diagnostics.len() > previous;

    const previous_cycles = diagnostics.len();
    try validateFragmentCycles(context.allocator, diagnostics, exec_doc, fragment);
    const has_cycles = diagnostics.len() > previous_cycles;

    if (!has_type_error and !has_cycles) {
        // Only pass the type condition to selection validation if the type actually exists
        // in the schema; if not, it has already raised an error or we have no schema.
        const fragment_against_type: ?ast.NamedTypeNode = blk: {
            const s = context.schema() orelse break :blk null;
            if (s.type_definitions.contains(fragment.type_condition.name.value))
                break :blk fragment.type_condition;
            break :blk null;
        };
        try validateSelectionSet(
            diagnostics,
            exec_doc,
            fragment_against_type,
            fragment.selection_set,
            context,
        );
    }
}

const max_fragment_cycle_depth = 100;

const CycleDetectError = error{ CycleDetected, RecursionLimitExceeded } || std.mem.Allocator.Error;
/// If a fragment spread is recursive, returns a vec containing the spread that refers back to
/// the original fragment, and a trace of each fragment spread back to the original fragment.
fn detectFragmentCycles(
    exec_doc: *const ExecutableDocument,
    selection_set: ast.SelectionSetNode,
    path: *std.ArrayList([]const u8),
    seen: *std.StringHashMap(void),
) CycleDetectError!void {
    for (selection_set.selections) |selection| {
        switch (selection) {
            .FragmentSpread => |spread| {
                const spread_name = spread.name.value;

                // Check if this spread's target is already in the current path.
                const in_path = for (path.items) |name| {
                    if (std.mem.eql(u8, name, spread_name)) break true;
                } else false;

                if (in_path) {
                    // Only the cycle back to the ROOT fragment is reported here cycles involving other fragments are reported when those
                    // fragments are validated as root.
                    if (std.mem.eql(u8, path.items[0], spread_name))
                        return error.CycleDetected;
                    continue;
                }

                // Already traversed this subtree for the current root — safe.
                const gop = try seen.getOrPut(spread_name);
                if (gop.found_existing) continue;

                const frag_def = exec_doc.getFragment(spread_name) orelse continue;

                if (path.items.len > max_fragment_cycle_depth)
                    return error.RecursionLimitExceeded;

                try path.append(spread_name);
                defer _ = path.pop();
                try detectFragmentCycles(exec_doc, frag_def.selection_set, path, seen);
            },
            .InlineFragment => |inline_frag| {
                try detectFragmentCycles(exec_doc, inline_frag.selection_set, path, seen);
            },
            .Field => |field| {
                const sel_set = field.selection_set orelse continue;
                try detectFragmentCycles(exec_doc, sel_set, path, seen);
            },
        }
    }
}

fn validateFragmentCycles(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    fragment: ast.FragmentDefinitionNode,
) std.mem.Allocator.Error!void {
    var path = std.ArrayList([]const u8).init(allocator);
    defer path.deinit();
    try path.append(fragment.name.value);

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    detectFragmentCycles(exec_doc, fragment.selection_set, &path, &seen) catch |err| switch (err) {
        error.CycleDetected => try diagnostics.push(.RecursiveFragmentDefinition),
        error.RecursionLimitExceeded => try diagnostics.push(.DeeplyNestedType),
        error.OutOfMemory => return error.OutOfMemory,
    };
}

fn validateFragmentTypeCondition(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    type_condition: ast.NamedTypeNode,
) !void {
    const type_def = schema.type_definitions.get(type_condition.name.value) orelse {
        try diagnostics.push(.InvalidFragmentTarget);
        return;
    };

    if (!type_def.isCompositeType()) {
        try diagnostics.push(.InvalidFragmentTarget);
    }
}

const max_walk_depth = 500;

const CollectWalkError = error{RecursionLimitExceeded} || std.mem.Allocator.Error;

fn walkCollectFragments(
    exec_doc: *const ExecutableDocument,
    selection_set: ast.SelectionSetNode,
    names: *std.StringHashMap(void),
    seen: *std.StringHashMap(void),
    depth: usize,
) CollectWalkError!void {
    if (depth >= max_walk_depth) return error.RecursionLimitExceeded;

    for (selection_set.selections) |selection| {
        switch (selection) {
            .FragmentSpread => |spread| {
                try names.put(spread.name.value, {});
                const gop = try seen.getOrPut(spread.name.value);
                if (gop.found_existing) continue;
                const frag_def = exec_doc.getFragment(spread.name.value) orelse continue;
                try walkCollectFragments(exec_doc, frag_def.selection_set, names, seen, depth + 1);
            },
            .InlineFragment => |inline_frag| {
                try walkCollectFragments(exec_doc, inline_frag.selection_set, names, seen, depth + 1);
            },
            .Field => |field| {
                const sel_set = field.selection_set orelse continue;
                try walkCollectFragments(exec_doc, sel_set, names, seen, depth + 1);
            },
        }
    }
}

fn collectUsedFragments(
    allocator: std.mem.Allocator,
    exec_doc: *const ExecutableDocument,
) CollectWalkError!std.StringHashMap(void) {
    var names = std.StringHashMap(void).init(allocator);
    errdefer names.deinit();

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    if (exec_doc.operations.anonymous) |op| {
        if (op.selection_set) |sel_set| {
            try walkCollectFragments(exec_doc, sel_set, &names, &seen, 0);
        }
    }
    for (exec_doc.operations.named.values()) |op| {
        if (op.selection_set) |sel_set| {
            try walkCollectFragments(exec_doc, sel_set, &names, &seen, 0);
        }
    }

    return names;
}

pub fn validateFragmentsUsed(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
) !void {
    var used_fragments = collectUsedFragments(allocator, exec_doc) catch |err| switch (err) {
        error.RecursionLimitExceeded => {
            try diagnostics.push(.RecursionError);
            return;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer used_fragments.deinit();

    for (exec_doc.fragments.values()) |fragment| {
        if (!used_fragments.contains(fragment.name.value)) {
            try diagnostics.push(.UnusedFragment);
        }
    }
}
