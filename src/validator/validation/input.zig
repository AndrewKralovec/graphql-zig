const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const BuiltInScalars = @import("../schema/validation.zig").BuiltInScalars;
const RecursionStack = @import("../validator.zig").RecursionStack;
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

    FindRecursiveInputValue.check(schema, input_obj) catch |err| switch (err) {
        error.RecursiveInputObjectDefinition => try diagnostics.push(.RecursiveInputObjectDefinition),
        error.DeeplyNestedType => try diagnostics.push(.DeeplyNestedType),
        else => return err,
    };

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

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();
    for (args) |arg| {
        const name = arg.name.value;
        const entry = try seen.getOrPut(name);
        if (entry.found_existing) {
            try diagnostics.push(.UniqueInputValue);
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

// Implements [Circular References](https://spec.graphql.org/October2021/#sec-Input-Objects.Circular-References)
// part of the input object validation spec.
const FindRecursiveInputValue = struct {
    schema: *const Schema,

    fn inputObject(
        self: FindRecursiveInputValue,
        stack: *RecursionStack,
        input_obj: ast.InputObjectTypeDefinitionNode,
    ) !void {
        const fields = input_obj.fields orelse return;
        for (fields) |field| try self.inputValue(stack, field);
    }

    fn inputValue(
        self: FindRecursiveInputValue,
        stack: *RecursionStack,
        field: ast.InputValueDefinitionNode,
    ) !void {
        switch (field.type.*) {
            .NonNullType => |non_null| switch (non_null.type.*) {
                .NamedType => |named| {
                    const name = named.name.value;
                    if (stack.contains(name)) {
                        // Cycle back to the root we started from — report it.
                        // Cycles not rooted here are caught when that type is validated.
                        if (std.mem.eql(u8, stack.first() orelse "", name)) {
                            return error.RecursiveInputObjectDefinition;
                        }
                        return;
                    }
                    if (self.schema.type_definitions.get(name)) |type_def| {
                        switch (type_def) {
                            .InputObjectTypeDefinition => |inner| {
                                try stack.push(name); // returns error.DeeplyNestedType at depth >= 32
                                defer stack.pop();
                                try self.inputObject(stack, inner);
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            },
            else => {},
        }
    }

    fn check(schema: *const Schema, input_obj: ast.InputObjectTypeDefinitionNode) !void {
        var stack = try RecursionStack.withRoot(schema.allocator, input_obj.name.value);
        defer stack.deinit();
        const finder = FindRecursiveInputValue{ .schema = schema };
        try finder.inputObject(&stack, input_obj);
    }
};
