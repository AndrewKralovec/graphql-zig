const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const BuiltInScalars = @import("../schema/validation.zig").BuiltInScalars;

pub fn validateInputObjectDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    input_obj: ast.InputObjectTypeDefinitionNode,
) !void {
    _ = allocator;
    _ = diagnostics;
    _ = schema;
    _ = builtin_scalars;
    _ = input_obj;
    // TODO: Implement input object definition validation
    // - validate directives at InputObject location
    // - check for circular references (FindRecursiveInputValue)
    // - validate input value definitions (fields)
    // - check at least one field exists
}

pub fn validateArgumentDefinitions(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    arguments: ?[]const ast.InputValueDefinitionNode,
    dir_loc: ast.DirectiveLocation,
) !void {
    _ = allocator;
    _ = diagnostics;
    _ = schema;
    _ = builtin_scalars;
    _ = arguments;
    _ = dir_loc;
    // TODO: Implement argument definition validation
    // - call validateInputValueDefinitions for each argument
    // - check for duplicate argument names (UniqueInputValue)
}

fn validateInputValueDefinitions(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    builtin_scalars: *BuiltInScalars,
    input_values: ?[]const ast.InputValueDefinitionNode,
    dir_loc: ast.DirectiveLocation,
    describe: []const u8,
) !void {
    _ = allocator;
    _ = diagnostics;
    _ = schema;
    _ = builtin_scalars;
    _ = input_values;
    _ = dir_loc;
    _ = describe;
    // TODO: Implement input value definition validation
    // For each input value:
    //   - validateTypeSystemName(diagnostics, input_value.name, describe)
    //   - validateDirectives at dir_loc (no variables in type-system context)
    //   - check input_value type is an input type (Scalar, Enum, InputObject)
    //   - handle built-in scalars via builtin_scalars.recordTypeRef()
    //   - push .UndefinedDefinition if type not found and not built-in
}
