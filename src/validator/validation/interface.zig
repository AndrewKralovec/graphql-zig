const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;

pub fn validateInterfaceDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    iface_def: ast.InterfaceTypeDefinitionNode,
) !void {
    _ = allocator;
    _ = diagnostics;
    _ = schema;
    _ = iface_def;
    // TODO: validateTypeSystemName, validateDirectives, validateFieldDefinitions
    // TODO: check that the interface has at least one field (EmptyFieldSet)
    // TODO: validate implemented interfaces (interfaces can implement interfaces per the 2021 spec)
}

pub fn validateImplementsInterfaces(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    obj: ast.ObjectTypeDefinitionNode,
) !void {
    _ = allocator;
    _ = diagnostics;
    _ = schema;
    _ = obj;
    // TODO: for each interface reference in obj.interfaces
}

pub fn validateImplementationFieldTypes(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    obj: ast.ObjectTypeDefinitionNode,
) !void {
    _ = allocator;
    _ = diagnostics;
    _ = schema;
    _ = obj;
    // TODO: for each interface implemented by obj, for each interface field
}

pub fn validateImplementationFieldArguments(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    obj: ast.ObjectTypeDefinitionNode,
) !void {
    _ = allocator;
    _ = diagnostics;
    _ = schema;
    _ = obj;
    // TODO: for each interface implemented by obj, for each interface field
}
