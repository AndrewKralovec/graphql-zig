const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const validateDirectives = @import("./directive.zig").validateDirectives;
const validateFieldDefinitions = @import("./field.zig").validateFieldDefinitions;
const validateImplementsInterfaces = @import("./interface.zig").validateImplementsInterfaces;
const validateImplementationFieldTypes = @import("./interface.zig").validateImplementationFieldTypes;
const validateImplementationFieldArguments = @import("./interface.zig").validateImplementationFieldArguments;
const BuiltInScalars = @import("../schema/validation.zig").BuiltInScalars;

pub fn validateObjectTypeDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    obj: ast.ObjectTypeDefinitionNode,
) !void {
    // Type name validation (__ reserved prefix) is performed by validateSchema
    // for all type definitions before dispatching to type-specific validators.

    try validateDirectives(
        allocator,
        diagnostics,
        schema,
        obj.directives,
        .Object,
        &[_]ast.VariableDefinitionNode{},
    );

    // Object Type field validations.
    try validateFieldDefinitions(allocator, diagnostics, schema, builtin_scalars, obj.fields);

    // An object type must define one or more fields
    // https://spec.graphql.org/draft/#sel-FAHZhCFDBAACDA4qe
    const fields = obj.fields orelse &[_]ast.FieldDefinitionNode{};
    if (fields.len == 0) {
        try diagnostics.push(.EmptyFieldSet);
    }

    // Implements Interfaces validation.
    try validateImplementsInterfaces(
        allocator,
        diagnostics,
        schema,
        obj.name.value,
        obj.interfaces,
    );
    // When defining an interface that implements another interface, the
    // implementing interface must define each field that is specified by
    // the implemented interface.
    //
    // Returns a Missing Field error.
    try validateMissingInterfaceFields(diagnostics, schema, obj);

    // Validate that fields in the implementing type have return types that are
    // proper subtypes of the interface fields.
    try validateImplementationFieldTypes(
        allocator,
        diagnostics,
        schema,
        obj.name.value,
        obj.fields,
        obj.interfaces,
    );

    // Validate that fields in the implementing type have matching arguments
    // per the IsValidImplementation rule.
    try validateImplementationFieldArguments(
        allocator,
        diagnostics,
        schema,
        obj.name.value,
        obj.fields,
        obj.interfaces,
    );
}

/// Checks that for every interface this object implements, each interface field has a
/// corresponding field on the object type.
fn validateMissingInterfaceFields(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    obj: ast.ObjectTypeDefinitionNode,
) !void {
    const interfaces = obj.interfaces orelse return;
    const obj_fields = obj.fields orelse &[_]ast.FieldDefinitionNode{};

    for (interfaces) |iface_ref| {
        const type_def = schema.type_definitions.get(iface_ref.name.value) orelse continue;
        const interface_def = switch (type_def) {
            .InterfaceTypeDefinition => |i| i,
            else => continue,
        };

        const interface_fields = interface_def.fields orelse continue;
        for (interface_fields) |interface_field| {
            const found = for (obj_fields) |obj_field| {
                if (std.mem.eql(u8, obj_field.name.value, interface_field.name.value)) break true;
            } else false;

            if (!found) {
                try diagnostics.push(.MissingInterfaceField);
            }
        }
    }
}
