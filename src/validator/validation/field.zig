const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const OperationValidationContext = @import("../validator.zig").OperationValidationContext;
const Schema = @import("../validator.zig").Schema;

const validateSelectionSet = @import("./selection.zig").validateSelectionSet;
const validateDirectives = @import("./directive.zig").validateDirectives;
const validateArguments = @import("./argument.zig").validateArguments;
const validateVariableUsage = @import("./variable.zig").validateVariableUsage;
const validateValues = @import("./value.zig").validateValues;
const validateArgumentDefinitions = @import("./input.zig").validateArgumentDefinitions;
const validateTypeSystemName = @import("../schema/validation.zig").validateTypeSystemName;
const BuiltInScalars = @import("../schema/validation.zig").BuiltInScalars;
const findArgumentDefinition = @import("./directive.zig").findArgumentDefinition;
const isArgumentProvided = @import("./directive.zig").isArgumentProvided;

pub fn validateField(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    // May be None if a parent selection was invalid
    against_type: ?ast.NamedTypeNode,
    field: ast.FieldNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    const var_defs = context.variables orelse &[_]ast.VariableDefinitionNode{};
    const schema = context.schema();

    // First do all the validation that we can without knowing the type of the field.
    try validateDirectives(
        context.allocator,
        diagnostics,
        schema,
        field.directives,
        .Field,
        var_defs,
    );

    try validateArguments(
        context.allocator,
        diagnostics,
        field.arguments,
    );

    // If we don't know the parent type (no schema, or invalid parent), we cannot
    // perform type-aware checks for this field. However, we still traverse into
    // the nested selection set so that validations that do not require a schema
    // (like missing fragment detection) can run.
    const at = against_type orelse {
        if (field.selection_set) |sel_set| {
            try validateSelectionSet(diagnostics, exec_doc, null, sel_set, context);
        }
        return;
    };

    const s = schema orelse {
        if (field.selection_set) |sel_set| {
            try validateSelectionSet(diagnostics, exec_doc, null, sel_set, context);
        }
        return;
    };

    // TODO: push UndefinedField error when field doesn't exist on the type
    // need to add UndefinedField to ValidationErrorKind
    // and also handle __typename, __type, __schema introspection fields which are always valid
    const field_definition = s.typeField(at, field.name.value) orelse return;

    // For each provided argument, validate against the field definition.
    if (field.arguments) |args| {
        for (args) |arg| {
            const arg_definition = findArgumentDefinition(field_definition.arguments, arg.name.value);
            if (arg_definition) |input_value| {
                if (try validateVariableUsage(
                    diagnostics,
                    input_value,
                    var_defs,
                    arg,
                )) {
                    try validateValues(
                        diagnostics,
                        s,
                        input_value.type,
                        arg,
                        var_defs,
                    );
                }
            } else {
                try diagnostics.push(.UndefinedArgument);
            }
        }
    }

    // Every non-null argument without a default must be provided.
    if (field_definition.arguments) |arg_defs| {
        for (arg_defs) |arg_def| {
            if (arg_def.isRequiredArgument()) {
                if (!isArgumentProvided(field.arguments, arg_def.name.value)) {
                    try diagnostics.push(.RequiredArgument);
                }
            }
        }
    }

    if (try validateLeafFieldSelection(
        diagnostics,
        s,
        field,
        field_definition,
    )) {
        if (field.selection_set) |sel_set| {
            const nested_against_type = field_definition.type.innerNamedType();
            try validateSelectionSet(
                diagnostics,
                exec_doc,
                nested_against_type,
                sel_set,
                context,
            );
        }
    }
}

fn validateLeafFieldSelection(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    field: ast.FieldNode,
    field_def: ast.FieldDefinitionNode,
) std.mem.Allocator.Error!bool {
    const is_leaf = field.selection_set == null;
    const type_name = field_def.type.innerNamedType();
    const type_def = schema.type_definitions.get(type_name.name.value) orelse {
        return true; // if we don't have the type we can't check if it requires a subselection.
    };

    if (is_leaf and type_def.isCompositeType()) {
        try diagnostics.push(.MissingSubselection);
        return false;
    }

    if (!is_leaf and !type_def.isCompositeType()) {
        try diagnostics.push(.SelectionOnLeafField);
        return false;
    }

    return true;
}

pub fn validateFieldDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    field_def: ast.FieldDefinitionNode,
) !void {
    try validateTypeSystemName(diagnostics, field_def.name, "a field");

    try validateDirectives(
        allocator,
        diagnostics,
        schema,
        field_def.directives,
        .FieldDefinition,
        &[_]ast.VariableDefinitionNode{},
    );

    try validateArgumentDefinitions(
        allocator,
        diagnostics,
        schema,
        builtin_scalars,
        field_def.arguments,
        .ArgumentDefinition,
    );
}

pub fn validateFieldDefinitions(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    fields: ?[]const ast.FieldDefinitionNode,
) !void {
    const field_list = fields orelse return;
    for (field_list) |field_def| {
        try validateFieldDefinition(allocator, diagnostics, schema, builtin_scalars, field_def);

        // Field types in Object Types must be of output type
        const named_type = field_def.type.innerNamedType();
        const is_built_in = builtin_scalars.recordTypeRef(schema, named_type.name.value);

        if (schema.type_definitions.get(named_type.name.value)) |type_def| {
            if (!type_def.isOutputType()) {
                // Output types are unreachable
                try diagnostics.push(.OutputType);
            }
        } else if (is_built_in) {
            // `validate_schema()` will insert the missing definition
        } else {
            try diagnostics.push(.UndefinedDefinition);
        }
    }
}
