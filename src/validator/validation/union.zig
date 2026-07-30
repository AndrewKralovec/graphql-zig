const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;
const validateDirectives = @import("./directive.zig").validateDirectives;

// TODO: wire up in validateSchema() once the type-definition dispatch loop is implemented.
pub fn validateUnionDefinition(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    schema: *const Schema,
    union_def: ast.UnionTypeDefinitionNode,
) !void {
    try validateDirectives(
        allocator,
        diagnostics,
        schema,
        union_def.directives,
        .Union,
        &[_]ast.VariableDefinitionNode{},
    );

    const member_types = union_def.types orelse &[_]ast.NamedTypeNode{};
    for (member_types) |union_member| {
        // TODO(rs): (?) A Union type must include one or more unique member types.

        const type_def = schema.type_definitions.get(union_member.name.value) orelse {
            // Union member must be defined.
            try diagnostics.push(.UndefinedDefinition);
            continue;
        };
        switch (type_def) {
            .ObjectTypeDefinition => {}, // valid union member
            else => {
                // Union members must be Object types.
                // https://spec.graphql.org/draft/#sec-Unions
                try diagnostics.push(.UnionMemberObjectType);
            },
        }
    }

    // validate there is at least one union member on the union type
    // https://spec.graphql.org/draft/#sel-HAHdfFBABAB6Bw3R
    if (member_types.len == 0) {
        try diagnostics.push(.EmptyMemberSet);
    }
}
