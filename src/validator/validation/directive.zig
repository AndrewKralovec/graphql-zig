const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const RecursionStack = @import("../validator.zig").RecursionStack;
const BuiltInScalars = @import("../schema/validation.zig").BuiltInScalars;

const validateArguments = @import("./argument.zig").validateArguments;
const validateArgumentDefinitions = @import("./input.zig").validateArgumentDefinitions;
const validateVariableUsage = @import("./variable.zig").validateVariableUsage;
const validateValues = @import("./value.zig").validateValues;
const validateTypeSystemName = @import("../schema/validation.zig").validateTypeSystemName;

pub fn validateDirectiveDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    def: ast.DirectiveDefinitionNode,
) !void {
    try validateTypeSystemName(diagnostics, def.name, "a directive definition");
    try validateArgumentDefinitions(
        allocator,
        diagnostics,
        schema,
        builtin_scalars,
        def.arguments,
        .ArgumentDefinition,
    );

    // A directive definition must not contain the use of a directive which
    // references itself directly.
    //
    // Returns Recursive Definition error.
    FindRecursiveDirective.check(schema, def) catch |err| switch (err) {
        error.RecursiveDirectiveDefinition => try diagnostics.push(.RecursiveDirectiveDefinition),
        error.DeeplyNestedType => try diagnostics.push(.DeeplyNestedType),
        else => return err,
    };
}

pub fn validateDirectiveDefinitions(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
) !void {
    for (schema.directive_definitions.values()) |def| {
        try validateDirectiveDefinition(allocator, diagnostics, schema, builtin_scalars, def);
    }
}

// TODO(rs): This is a big function
pub fn validateDirectives(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: ?*const Schema,
    directives: ?[]const ast.DirectiveNode,
    dir_loc: ast.DirectiveLocation,
    var_defs: []const ast.VariableDefinitionNode,
) !void {
    const dirs = directives orelse return;

    var seen_directives = std.StringHashMap(void).init(allocator);
    defer seen_directives.deinit();

    for (dirs) |dir| {
        try validateArguments(
            allocator,
            diagnostics,
            dir.arguments,
        );

        const name = dir.name.value;
        const directive_definition: ?ast.DirectiveDefinitionNode = if (schema) |s|
            s.directive_definitions.get(name)
        else
            null;

        // uniqueness. nonrepeatable directives must not appear more than once at the same location.
        const seen_entry = try seen_directives.getOrPut(name);
        if (seen_entry.found_existing) {
            const is_repeatable = if (directive_definition) |def|
                def.repeatable
            else
                // Assume unknown directives are repeatable to avoid confusing diagnostics.
                true;

            if (!is_repeatable) {
                try diagnostics.push(.UniqueDirective);
            }
        }

        const s = schema orelse return;
        if (directive_definition) |def| {
            if (!isLocationAllowed(def.locations, dir_loc)) {
                try diagnostics.push(.UnsupportedLocation);
            }

            if (dir.arguments) |args| {
                for (args) |arg| {
                    const arg_def = findArgumentDefinition(def.arguments, arg.name.value);
                    if (arg_def) |input_value| {
                        if (try validateVariableUsage(diagnostics, input_value, var_defs, arg)) {
                            try validateValues(diagnostics, s, input_value.type, arg, var_defs);
                        }
                    } else {
                        try diagnostics.push(.UndefinedArgument);
                    }
                }
            }

            if (def.arguments) |arg_defs| {
                for (arg_defs) |arg_def| {
                    if (arg_def.isRequiredArgument()) {
                        if (!isArgumentProvided(dir.arguments, arg_def.name.value)) {
                            try diagnostics.push(.RequiredArgument);
                        }
                    }
                }
            }
        } else {
            try diagnostics.push(.UndefinedDirective);
        }
    }
}

fn isLocationAllowed(def_locations: []const ast.NameNode, dir_loc: ast.DirectiveLocation) bool {
    for (def_locations) |loc_node| {
        const parsed = ast.directiveLocationFromString(loc_node.value);
        if (parsed) |loc| {
            if (loc == dir_loc) return true;
        }
    }
    return false;
}

// TODO: move/share
fn isBuiltInType(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "__")) return true;
    return std.mem.eql(u8, name, "String") or
        std.mem.eql(u8, name, "Int") or
        std.mem.eql(u8, name, "Float") or
        std.mem.eql(u8, name, "Boolean") or
        std.mem.eql(u8, name, "ID");
}

// TODO: move
pub fn findArgumentDefinition(
    arg_defs: ?[]const ast.InputValueDefinitionNode,
    name: []const u8,
) ?ast.InputValueDefinitionNode {
    const defs = arg_defs orelse return null;
    for (defs) |def| {
        if (std.mem.eql(u8, def.name.value, name)) {
            return def;
        }
    }
    return null;
}

// TODO: move
pub fn isArgumentProvided(arguments: ?[]const ast.ArgumentNode, name: []const u8) bool {
    const args = arguments orelse return false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg.name.value, name)) {
            return arg.value != .Null;
        }
    }
    return false;
}

/// This struct just groups functions that are used to find self-referential directives.
/// The way to use it is to call `FindRecursiveDirective::check`.
const FindRecursiveDirective = struct {
    schema: *const Schema,

    fn typeDefinition(
        self: FindRecursiveDirective,
        dir_stack: *RecursionStack,
        type_stack: *RecursionStack,
        type_def: ast.TypeDefinitionNode,
    ) !void {
        switch (type_def) {
            .ScalarTypeDefinition => |s| {
                if (s.directives) |dirs| try self.directives(dir_stack, type_stack, dirs);
            },
            .ObjectTypeDefinition => |o| {
                if (o.directives) |dirs| try self.directives(dir_stack, type_stack, dirs);
            },
            .InterfaceTypeDefinition => |i| {
                if (i.directives) |dirs| try self.directives(dir_stack, type_stack, dirs);
            },
            .UnionTypeDefinition => |u| {
                if (u.directives) |dirs| try self.directives(dir_stack, type_stack, dirs);
            },
            .EnumTypeDefinition => |e| {
                if (e.directives) |dirs| try self.directives(dir_stack, type_stack, dirs);
                if (e.values) |values| {
                    for (values) |enum_val| try self.enumValue(dir_stack, type_stack, enum_val);
                }
            },
            .InputObjectTypeDefinition => |io| {
                if (io.directives) |dirs| try self.directives(dir_stack, type_stack, dirs);
                if (io.fields) |fields| {
                    for (fields) |field| try self.inputValue(dir_stack, type_stack, field);
                }
            },
        }
    }

    fn directives(
        self: FindRecursiveDirective,
        dir_stack: *RecursionStack,
        type_stack: *RecursionStack,
        dirs: []const ast.DirectiveNode,
    ) !void {
        for (dirs) |d| try self.directive(dir_stack, type_stack, d);
    }

    fn enumValue(
        self: FindRecursiveDirective,
        dir_stack: *RecursionStack,
        type_stack: *RecursionStack,
        enum_val: ast.EnumValueDefinitionNode,
    ) !void {
        if (enum_val.directives) |dirs| try self.directives(dir_stack, type_stack, dirs);
    }

    fn inputValue(
        self: FindRecursiveDirective,
        dir_stack: *RecursionStack,
        type_stack: *RecursionStack,
        input_value: ast.InputValueDefinitionNode,
    ) !void {
        if (input_value.directives) |dirs| try self.directives(dir_stack, type_stack, dirs);

        const type_name = input_value.type.innerNamedType().name.value;
        if (self.schema.type_definitions.get(type_name)) |type_def| {
            if (type_stack.contains(type_name)) return; // input type was already processed

            if (!isBuiltInType(type_name)) {
                try type_stack.push(type_name);
                defer type_stack.pop();
                try self.typeDefinition(dir_stack, type_stack, type_def);
            } else {
                // builtin types don't count toward the nesting limit so traverse without pushing
                try self.typeDefinition(dir_stack, type_stack, type_def);
            }
        }
    }

    fn directive(
        self: FindRecursiveDirective,
        dir_stack: *RecursionStack,
        type_stack: *RecursionStack,
        d: ast.DirectiveNode,
    ) !void {
        const name = d.name.value;
        if (!dir_stack.contains(name)) {
            if (self.schema.directive_definitions.get(name)) |def| {
                try dir_stack.push(name);
                defer dir_stack.pop();
                try self.directiveDefinitionBody(dir_stack, type_stack, def);
            }
        } else if (std.mem.eql(u8, dir_stack.first() orelse "", name)) {
            return error.RecursiveDirectiveDefinition;
        }
        // Already visited but not the root — belongs to another directive's cycle, ignore.
    }

    fn directiveDefinitionBody(
        self: FindRecursiveDirective,
        dir_stack: *RecursionStack,
        type_stack: *RecursionStack,
        def: ast.DirectiveDefinitionNode,
    ) !void {
        const args = def.arguments orelse return;
        for (args) |input_value| try self.inputValue(dir_stack, type_stack, input_value);
    }

    fn check(schema: *const Schema, def: ast.DirectiveDefinitionNode) !void {
        var dir_stack = try RecursionStack.withRoot(schema.allocator, def.name.value);
        defer dir_stack.deinit();
        var type_stack = RecursionStack.init(schema.allocator);
        defer type_stack.deinit();
        const finder = FindRecursiveDirective{ .schema = schema };
        try finder.directiveDefinitionBody(&dir_stack, &type_stack, def);
    }
};
