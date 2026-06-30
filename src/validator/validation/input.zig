const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const BuiltInScalars = @import("../schema/validation.zig").BuiltInScalars;
const validateDirectives = @import("./directive.zig").validateDirectives;
const validateTypeSystemName = @import("../schema/validation.zig").validateTypeSystemName;

pub fn validateInputObjectDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    input_obj: ast.InputObjectTypeDefinitionNode,
) !void {
    try validateDirectives(
        allocator,
        diagnostics,
        schema,
        input_obj.directives,
        .InputObject,
        &[_]ast.VariableDefinitionNode{},
    );

    try checkRecursiveInputValue(allocator, diagnostics, schema, input_obj);

    // Fields in an Input Object Definition must be unique
    //
    // Returns Unique Definition error.
    const fields = input_obj.fields orelse &[_]ast.InputValueDefinitionNode{};
    try validateInputValueDefinitions(
        allocator,
        diagnostics,
        schema,
        builtin_scalars,
        fields,
        .InputFieldDefinition,
        "an input object field",
    );

    // validate there is at least one input value on the input object type
    // https://spec.graphql.org/draft/#sel-HAHhBXDBABAB5BvgD
    if (fields.len == 0) {
        try diagnostics.push(.EmptyInputValueSet);
    }
}

pub fn validateArgumentDefinitions(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    arguments: ?[]const ast.InputValueDefinitionNode,
    dir_loc: ast.DirectiveLocation,
) !void {
    const args = arguments orelse return;

    try validateInputValueDefinitions(
        allocator,
        diagnostics,
        schema,
        builtin_scalars,
        args,
        dir_loc,
        "an argument",
    );

    var seen = std.StringHashMap(bool).init(allocator);
    defer seen.deinit();
    for (args) |arg| {
        const name = arg.name.value;
        if (seen.get(name) != null) {
            try diagnostics.push(.UniqueInputValue);
        } else {
            try seen.put(name, true);
        }
    }
}

fn validateInputValueDefinitions(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    input_values: []const ast.InputValueDefinitionNode,
    dir_loc: ast.DirectiveLocation,
    describe: []const u8,
) !void {
    for (input_values) |input_val| {
        try validateTypeSystemName(diagnostics, input_val.name, describe);
        try validateDirectives(
            allocator,
            diagnostics,
            schema,
            input_val.directives,
            dir_loc,
            &[_]ast.VariableDefinitionNode{},
        );

        const named = input_val.type.innerNamedType();
        const is_builtin = builtin_scalars.recordTypeRef(schema, named.name.value);
        if (schema.type_definitions.get(named.name.value)) |type_def| {
            if (!type_def.isInputType()) {
                try diagnostics.push(.InputType);
            }
            // TODO: Validate default values once value-of-correct-type is wired for type-system context
            // (mirrors apollo-rs issue #928)
        } else if (!is_builtin) {
            try diagnostics.push(.UndefinedDefinition);
        }
    }
}

// Detects forbidden circular references in input object field types.
// Only NonNull named types can form cycles. nullable and list references are allowed.
fn checkRecursiveInputValue(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    input_obj: ast.InputObjectTypeDefinitionNode,
) !void {
    var stack = std.ArrayList([]const u8).init(allocator);
    defer stack.deinit();
    try stack.append(input_obj.name.value);
    try checkInputObject(diagnostics, schema, &stack, input_obj);
}

fn checkInputObject(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    stack: *std.ArrayList([]const u8),
    input_obj: ast.InputObjectTypeDefinitionNode,
) !void {
    const fields = input_obj.fields orelse return;
    for (fields) |field| {
        try checkInputValue(diagnostics, schema, stack, field);
    }
}

fn checkInputValue(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    stack: *std.ArrayList([]const u8),
    field: ast.InputValueDefinitionNode,
) !void {
    // Only NonNull wrapping a Named type is forbidden by the spec.
    // Nullable references and list types are allowed to be self-referential.
    switch (field.type.*) {
        .NonNullType => |non_null| switch (non_null.type.*) {
            .NamedType => |named| {
                const name = named.name.value;

                for (stack.items) |seen| {
                    if (std.mem.eql(u8, seen, name)) {
                        // Cycle back to the root we started from — report it.
                        // Cycles not rooted here are caught when that type is validated.
                        if (std.mem.eql(u8, stack.items[0], name)) {
                            try diagnostics.push(.RecursiveInputObjectDefinition);
                        }
                        return;
                    }
                }

                if (stack.items.len >= 32) {
                    try diagnostics.push(.DeeplyNestedType);
                    return;
                }

                if (schema.type_definitions.get(name)) |type_def| {
                    switch (type_def) {
                        .InputObjectTypeDefinition => |inner| {
                            try stack.append(name);
                            try checkInputObject(diagnostics, schema, stack, inner);
                            _ = stack.pop();
                        },
                        else => {},
                    }
                }
            },
            // NonNull(List) or NonNull(NonNull) — not a simple named reference, skip
            else => {},
        },
        // Nullable type — allowed to be self-referential per spec
        else => {},
    }
}
