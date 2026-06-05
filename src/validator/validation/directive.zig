const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;

const validateArguments = @import("./argument.zig").validateArguments;

pub fn validateDirectiveDefinition(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    def: ast.DirectiveDefinitionNode,
) !void {
    _ = diagnostics;
    _ = schema;
    _ = def;
    // TODO: validate type system name: validateTypeSystemName(diagnostics, def.name, "a directive definition")
    // TODO: validate argument definitions: validateArgumentDefinitions(diagnostics, schema, def.arguments, DirectiveLocation.ArgumentDefinition)
    // TODO: A directive definition must not contain the use of a directive which references itself
}

pub fn validateDirectiveDefinitions(
    diagnostics: *DiagnosticList,
    schema: *const Schema,
) !void {
    for (schema.directive_definitions.values()) |def| {
        try validateDirectiveDefinition(diagnostics, schema, def);
    }
}

pub fn validateDirectives(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: ?*const Schema,
    directives: ?[]const ast.DirectiveNode,
    dir_loc: ast.DirectiveLocation,
    // TODO: use var_defs once validateVariableUsage is wired up
    _: []const ast.VariableDefinitionNode,
) !void {
    const dirs = directives orelse return;

    var seen_directives = std.StringHashMap(bool).init(allocator);
    defer seen_directives.deinit();

    for (dirs) |dir| {
        // check for duplicate argument names within this directive usage
        try validateArguments(
            allocator,
            diagnostics,
            dir.arguments,
        );

        const name = dir.name.value;

        // look up the directive definition in the schema
        const directive_definition: ?ast.DirectiveDefinitionNode = if (schema) |s|
            s.directive_definitions.get(name)
        else
            null;

        // uniqueness. non-repeatable directives must not appear more than once at the same location.
        if (seen_directives.get(name)) |_| {
            const is_repeatable = if (directive_definition) |def|
                def.repeatable
            else
                // Assume unknown directives are repeatable to avoid confusing diagnostics.
                true;

            if (!is_repeatable) {
                try diagnostics.push(.UniqueDirective);
            }
        } else {
            try seen_directives.put(name, true);
        }

        _ = schema orelse return;
        if (directive_definition) |def| {
            // check the directive is allowed at this location.
            if (!isLocationAllowed(def.locations, dir_loc)) {
                try diagnostics.push(.UnsupportedLocation);
            }

            // per argument validation against the directive definition.
            if (dir.arguments) |args| {
                for (args) |arg| {
                    const arg_def = findArgumentDefinition(def.arguments, arg.name.value);
                    if (arg_def) |input_value| {
                        // TODO: validate variable usage once validateVariableUsage supported
                        // TODO: validate value type correctness once validateValues supported
                        _ = input_value;
                    } else {
                        try diagnostics.push(.UndefinedArgument);
                    }
                }
            }

            // every nonnull argument without a default must be provided
            if (def.arguments) |arg_defs| {
                for (arg_defs) |arg_def| {
                    if (isRequiredArgument(arg_def)) {
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

fn findArgumentDefinition(
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

fn isRequiredArgument(arg_def: ast.InputValueDefinitionNode) bool {
    return arg_def.type.* == .NonNullType and arg_def.default_value == null;
}

fn isArgumentProvided(arguments: ?[]const ast.ArgumentNode, name: []const u8) bool {
    const args = arguments orelse return false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg.name.value, name)) {
            return arg.value != .Null;
        }
    }
    return false;
}
