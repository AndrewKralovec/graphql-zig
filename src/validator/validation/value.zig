const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;

// TODO: remove or wire up.
fn unsupported_type(
    diagnostics: *DiagnosticList,
    value: *ast.ValueNode,
    declared_type: *ast.TypeNode,
) !void {
    _ = value;
    _ = declared_type;
    try diagnostics.push(.UnsupportedValueType);
}

pub fn validateValues(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    ty: *ast.TypeNode,
    argument: ast.ArgumentNode,
    var_defs: []const ast.VariableDefinitionNode,
) !void {
    try valueOfCorrectType(diagnostics, schema, ty, argument.value, var_defs);
}

pub fn valueOfCorrectType(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    ty: *ast.TypeNode,
    arg_value: ast.ValueNode,
    var_defs: []const ast.VariableDefinitionNode,
) !void {
    const type_def = schema.type_definitions.get(ty.innerNamedType().name.value) orelse return;

    switch (arg_value) {
        // When expected as an input type, only integer input values are
        // accepted. All other input values, including strings with numeric
        // content, must raise a request error indicating an incorrect
        // type. If the integer input value represents a value less than
        // -2^31 or greater than or equal to 2^31, a request error should be
        // raised.
        // When expected as an input type, any string (such as "4") or
        // integer (such as 4 or -4) input value should be coerced to ID
        .Int => |int_val| {
            switch (type_def) {
                .ScalarTypeDefinition => |scalar_def| {
                    if (!isBuiltInScalar(scalar_def.name.value)) return;
                    const name = scalar_def.name.value;
                    if (std.mem.eql(u8, name, "ID")) return;
                    if (std.mem.eql(u8, name, "Int")) {
                        _ = std.fmt.parseInt(i32, int_val.value, 10) catch {
                            try diagnostics.push(.IntCoercionError);
                            return;
                        };
                        return;
                    }
                    if (std.mem.eql(u8, name, "Float")) {
                        _ = std.fmt.parseFloat(f64, int_val.value) catch {
                            try diagnostics.push(.FloatCoercionError);
                            return;
                        };
                        return;
                    }
                    try diagnostics.push(.UnsupportedValueType);
                },
                else => try diagnostics.push(.UnsupportedValueType),
            }
        },
        // When expected as an input type, both integer and float input
        // values are accepted. All other input values, including strings
        // with numeric content, must raise a request error indicating an
        // incorrect type.
        .Float => |float_val| {
            switch (type_def) {
                .ScalarTypeDefinition => |scalar_def| {
                    // Any value is valid for a custom scalar.
                    if (!isBuiltInScalar(scalar_def.name.value)) return;
                    if (std.mem.eql(u8, scalar_def.name.value, "Float")) {
                        _ = std.fmt.parseFloat(f64, float_val.value) catch {
                            try diagnostics.push(.FloatCoercionError);
                            return;
                        };
                        return;
                    }
                    try diagnostics.push(.UnsupportedValueType);
                },
                else => try diagnostics.push(.UnsupportedValueType),
            }
        },
        // When expected as an input type, only valid Unicode string input
        // values are accepted. All other input values must raise a request
        // error indicating an incorrect type.
        // When expected as an input type, any string (such as "4") or
        // integer (such as 4 or -4) input value should be coerced to ID
        .String => {
            switch (type_def) {
                .ScalarTypeDefinition => |scalar_def| {
                    // specifically return diagnostics for ints, floats, and
                    // booleans.
                    // string, ids and custom scalars are ok, and
                    // don't need a diagnostic.
                    if (!isBuiltInScalar(scalar_def.name.value)) return;
                    const name = scalar_def.name.value;
                    if (std.mem.eql(u8, name, "String") or std.mem.eql(u8, name, "ID")) return;
                    try diagnostics.push(.UnsupportedValueType);
                },
                else => try diagnostics.push(.UnsupportedValueType),
            }
        },
        // When expected as an input type, only boolean input values are
        // accepted. All other input values must raise a request error
        // indicating an incorrect type.
        .Boolean => {
            switch (type_def) {
                .ScalarTypeDefinition => |scalar_def| {
                    if (!isBuiltInScalar(scalar_def.name.value)) return;
                    if (std.mem.eql(u8, scalar_def.name.value, "Boolean")) return;
                    try diagnostics.push(.UnsupportedValueType);
                },
                else => try diagnostics.push(.UnsupportedValueType),
            }
        },
        .Null => {
            if (ty.isNonNull()) {
                try diagnostics.push(.UnsupportedValueType);
            }
        },
        .Variable => |variable| {
            const var_name = variable.name.value;
            const type_name = ty.innerNamedType().name.value;
            const var_def = for (var_defs) |def| {
                if (std.mem.eql(u8, def.variable.name.value, var_name)) break def;
            } else {
                try diagnostics.push(.UndefinedVariable);
                return;
            };
            switch (type_def) {
                .ScalarTypeDefinition, .EnumTypeDefinition, .InputObjectTypeDefinition => {
                    // we don't have the actual variable values here, so just
                    // compare if two Types are the same
                    // TODO: This should use the is_assignable_to check
                    if (!std.mem.eql(u8, var_def.type.innerNamedType().name.value, type_name)) {
                        try diagnostics.push(.UnsupportedValueType);
                    }
                },
                else => try diagnostics.push(.UnsupportedValueType),
            }
        },
        .Enum => |enum_val| {
            switch (type_def) {
                .ScalarTypeDefinition => |scalar_def| {
                    if (!isBuiltInScalar(scalar_def.name.value)) return;
                    try diagnostics.push(.UnsupportedValueType);
                },
                .EnumTypeDefinition => |enum_def| {
                    const values = enum_def.values orelse {
                        try diagnostics.push(.UndefinedEnumValue);
                        return;
                    };
                    for (values) |v| {
                        if (std.mem.eql(u8, v.name.value, enum_val.value)) return;
                    }
                    try diagnostics.push(.UndefinedEnumValue);
                },
                else => try diagnostics.push(.UnsupportedValueType),
            }
        },
        // When expected as an input, list values are accepted only when
        // each item in the list can be accepted by the list’s item type.
        //
        // If the value passed as an input to a list type is not a list and
        // not the null value, then the result of input coercion is a list
        // of size one, where the single item value is the result of input
        // coercion for the list’s item type on the provided value (note
        // this may apply recursively for nested lists).
        .List => |list_val| {
            const nullable_ty = ty.nullable();
            switch (nullable_ty.*) {
                .ListType => |list_type| {
                    if (type_def.isInputType()) {
                        for (list_val.values) |item| {
                            try valueOfCorrectType(diagnostics, schema, list_type.type, item, var_defs);
                        }
                    } else {
                        try diagnostics.push(.UnsupportedValueType);
                    }
                },
                .NamedType => {
                    switch (type_def) {
                        .ScalarTypeDefinition => |scalar_def| {
                            if (isBuiltInScalar(scalar_def.name.value)) {
                                try diagnostics.push(.UnsupportedValueType);
                            } else {
                                for (list_val.values) |item| {
                                    try valueOfCorrectType(diagnostics, schema, ty, item, var_defs);
                                }
                            }
                        },
                        else => try diagnostics.push(.UnsupportedValueType),
                    }
                },
                .NonNullType => {
                    try diagnostics.push(.UnsupportedValueType);
                },
            }
        },
        .Object => |obj_val| {
            switch (type_def) {
                .ScalarTypeDefinition => |scalar_def| {
                    if (!isBuiltInScalar(scalar_def.name.value)) return;
                    try diagnostics.push(.UnsupportedValueType);
                },
                .InputObjectTypeDefinition => |input_def| {
                    const input_fields = input_def.fields orelse &[_]ast.InputValueDefinitionNode{};

                    // Add a diagnostic if a value does not exist on the input
                    // object type
                    for (obj_val.fields) |provided_field| {
                        if (findInputField(input_fields, provided_field.name.value) == null) {
                            try diagnostics.push(.UndefinedInputValue);
                            break;
                        }
                    }

                    for (input_fields) |field_def| {
                        const field_name = field_def.name.value;
                        const is_missing = !isFieldProvided(obj_val.fields, field_name);
                        const is_null = isFieldNull(obj_val.fields, field_name);

                        // If the input object field type is non_null, and no
                        // default value is provided, or if the value provided
                        // is null or missing entirely, an error should be
                        // raised.
                        if (field_def.type.isNonNull() and field_def.default_value == null and (is_missing or is_null)) {
                            try diagnostics.push(.RequiredField);
                        }

                        if (findProvidedValue(obj_val.fields, field_name)) |val| {
                            try valueOfCorrectType(diagnostics, schema, field_def.type, val, var_defs);
                        }
                    }
                },
                else => try diagnostics.push(.UnsupportedValueType),
            }
        },
    }
}

fn isBuiltInScalar(name: []const u8) bool {
    return std.mem.eql(u8, name, "String") or
        std.mem.eql(u8, name, "Int") or
        std.mem.eql(u8, name, "Float") or
        std.mem.eql(u8, name, "Boolean") or
        std.mem.eql(u8, name, "ID");
}

fn findInputField(fields: []const ast.InputValueDefinitionNode, name: []const u8) ?ast.InputValueDefinitionNode {
    for (fields) |f| {
        if (std.mem.eql(u8, f.name.value, name)) return f;
    }
    return null;
}

fn isFieldProvided(fields: []const ast.ObjectFieldNode, name: []const u8) bool {
    for (fields) |f| {
        if (std.mem.eql(u8, f.name.value, name)) return true;
    }
    return false;
}

fn isFieldNull(fields: []const ast.ObjectFieldNode, name: []const u8) bool {
    for (fields) |f| {
        if (std.mem.eql(u8, f.name.value, name)) return f.value == .Null;
    }
    return false;
}

fn findProvidedValue(fields: []const ast.ObjectFieldNode, name: []const u8) ?ast.ValueNode {
    for (fields) |f| {
        if (std.mem.eql(u8, f.name.value, name)) return f.value;
    }
    return null;
}
