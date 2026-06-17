const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;

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
    schema: ?*const Schema,
    ty: *ast.TypeNode,
    argument: ast.ArgumentNode,
    var_defs: []const ast.VariableDefinitionNode,
) !void {
    try valueOfCorrectType(diagnostics, schema, ty, argument.value, var_defs);
}

pub fn valueOfCorrectType(
    diagnostics: *DiagnosticList,
    schema: ?*const Schema,
    ty: *ast.TypeNode,
    arg_value: ast.ValueNode,
    var_defs: []const ast.VariableDefinitionNode,
) !void {
    const s = schema orelse return;
    const type_def = s.type_definitions.get(ty.innerNamedType().name.value) orelse return;

    switch (arg_value) {
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
        .Float => |float_val| {
            switch (type_def) {
                .ScalarTypeDefinition => |scalar_def| {
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
        .String => {
            switch (type_def) {
                .ScalarTypeDefinition => |scalar_def| {
                    if (!isBuiltInScalar(scalar_def.name.value)) return;
                    const name = scalar_def.name.value;
                    if (std.mem.eql(u8, name, "String") or std.mem.eql(u8, name, "ID")) return;
                    try diagnostics.push(.UnsupportedValueType);
                },
                else => try diagnostics.push(.UnsupportedValueType),
            }
        },
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
                            if (!isBuiltInScalar(scalar_def.name.value)) return;
                            try diagnostics.push(.UnsupportedValueType);
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
