const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const Validator = @import("../validator.zig").Validator;

pub fn validateDirectivesDefinition(ctx: *Validator, def: ast.DirectiveDefinitionNode) !void {
    _ = ctx;
    _ = def;
    // TODO: add validation logic
    // TODO: try validateTypeSystemName(ctx, def.name, "");
    // TODO: try validateArgumentDefinitions(ctx, args);
}

pub fn validateDirectivesDefinitions(ctx: *Validator) !void {
    _ = ctx;
    // TODO: add validation logic
}

pub fn validateDirectives(ctx: *Validator, directives: ?[]const ast.DirectiveNode, location: ast.DirectiveLocation) !void {
    _ = ctx;
    _ = directives;
    _ = location;
    // TODO: add validation logic
}
