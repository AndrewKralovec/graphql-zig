const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const Schema = @import("../validator.zig").Schema;

pub fn validateSchema(diagnostics: *DiagnosticList, schema: *const Schema) !void {
    var builtin_scalars = BuiltInScalars.init(diagnostics.allocator); // TODO: pass allocator.
    defer builtin_scalars.deinit();

    _ = schema;
    // TODO: add validation logic
}

/// Validate type system names according to GraphQL spec
/// https://spec.graphql.org/draft/#sec-Names.Reserved-Names
pub fn validateTypeSystemName(
    diagnostics: *DiagnosticList,
    name: ast.NameNode,
    describe: []const u8,
) !void {
    _ = diagnostics;
    _ = name;
    _ = describe;
    // TODO: add validation logic
}

// TODO: Implement type
/// Keeps track of usage of [built-in scalars] in a schema to determine which definitions
/// should be removed or added.
///
/// > When returning the set of types from the `__Schema` introspection type,
/// > all referenced built-in scalars must be included.
/// > If a built-in scalar type is not referenced anywhere in a schema
/// > (there is no field, argument, or input field of that type) then it must not be included.
///
/// We reflect this behavior of introspection in the `types` map of a `Valid<Schema>`.
///
/// [built-in scalars]: https://spec.graphql.org/draft/#sec-Scalars.Built-in-Scalars
pub const BuiltInScalars = struct {
    allocator: std.mem.Allocator,
    // all: &'static HashMap<Name, Node<ScalarType>>,
    // used_and_defined: HashSet<Name>,
    // used_and_undefined: HashSet<Name>,

    pub fn init(allocator: std.mem.Allocator) BuiltInScalars {
        return BuiltInScalars{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BuiltInScalars) void {
        _ = self;
        // TODO: cleanup resources if needed
    }

    /// Records a type reference to keep track of which built-in scalars are used in a schema,
    /// and returns whether this type name is for a built-in scalar
    pub fn recordTypeRef(self: *BuiltInScalars, schema: *const Schema, name: []const u8) bool {
        _ = self;
        _ = schema;
        _ = name;
        // TODO: Implement built-in scalar tracking
        return false;
    }

    fn all_used(self: *BuiltInScalars) bool {
        // let used_count = self.used_and_defined.len() + self.used_and_undefined.len();
        // used_count == self.all.len()
        // TODO: add validation logic
        _ = self;
        return true;
    }
};
