const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const OperationValidationContext = @import("../validator.zig").OperationValidationContext;
const Schema = @import("../validator.zig").Schema;

const validateSelectionSet = @import("./selection.zig").validateSelectionSet;
const validateDirectives = @import("./directive.zig").validateDirectives;

// TODO: cache this in ExecutableValidationContext as an implementers_map
/// Given a type definition, find all the type names that can be used for fragment spreading.
///
/// Spec: https://spec.graphql.org/October2021/#GetPossibleTypes()
fn getPossibleTypes(
    allocator: std.mem.Allocator,
    schema: *const Schema,
    type_def: ast.TypeDefinitionNode,
) !std.StringHashMap(void) {
    var set = std.StringHashMap(void).init(allocator);

    switch (type_def) {
        // 1. If `type` is an object type, return a set containing `type`.
        .ObjectTypeDefinition => |obj| {
            try set.put(obj.name.value, {});
        },
        // 2. If `type` is an interface type, return the set of object types implementing `type`.
        .InterfaceTypeDefinition => |iface| {
            for (schema.type_definitions.values()) |td| {
                switch (td) {
                    .ObjectTypeDefinition => |obj| {
                        if (obj.interfaces) |ifaces| {
                            for (ifaces) |implemented| {
                                if (std.mem.eql(u8, implemented.name.value, iface.name.value)) {
                                    try set.put(obj.name.value, {});
                                    break;
                                }
                            }
                        }
                    },
                    else => {},
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
// TODO: apollo-rs uses context.implementers_map() which is a
// lazily computed cached map. We recompute possible types on every call instead
fn validateFragmentSpreadType(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    against_type: ast.NamedTypeNode,
    type_condition: ast.NamedTypeNode,
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

    // TODO: implementers_map

    var parent_types = try getPossibleTypes(allocator, schema, against_def);
    defer parent_types.deinit();

    var condition_types = try getPossibleTypes(allocator, schema, condition_def);
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
                        context.allocator,
                        diagnostics,
                        s,
                        parent,
                        type_cond,
                    );
                }
            }
        }

        const fragment_against_type: ?ast.NamedTypeNode = if (inline_fragment.type_condition) |type_cond|
            type_cond
        else
            against_type;

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
                context.allocator,
                diagnostics,
                s,
                parent,
                frag_def.type_condition,
            );
        }
    }

    const gop = try context.validated_fragments.getOrPut(spread.name.value);
    if (gop.found_existing) return;

    try validateFragmentDefinition(diagnostics, exec_doc, against_type, frag_def, context);
}

pub fn validateFragmentDefinition(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    against_type: ?ast.NamedTypeNode,
    fragment: ast.FragmentDefinitionNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    _ = against_type;

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
        try validateFragmentTypeCondition(diagnostics, s, fragment.type_condition);
    }
    const has_type_error = diagnostics.len() > previous;

    // TODO: when validateFragmentCycles is implemented, gate selection set
    // validation on both !has_type_error and !has_cycles
    validateFragmentCycles();

    if (!has_type_error) {
        const fragment_against_type: ?ast.NamedTypeNode = fragment.type_condition;
        try validateSelectionSet(diagnostics, exec_doc, fragment_against_type, fragment.selection_set, context);
    }
}

// TODO: implement fragment cycle detection
// Should accept (diagnostics, exec_doc, fragment) and detect when a fragment
// directly or transitively spreads itself. Push RecursiveFragmentDefinition error.
// See: https://spec.graphql.org/draft/#sec-Fragment-spreads-must-not-form-cycles
fn validateFragmentCycles() void {}

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

// TODO: implement used-fragment collection for validateFragmentsUsed
fn collectUsedFragments() void {}

// TODO: implement unused fragment detection
fn validateFragmentsUsed() void {}
