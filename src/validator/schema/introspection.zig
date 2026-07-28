const ast = @import("../../graphql.zig").ast;

pub const MetaFields = struct {
    ready: bool = false,

    string_named: ast.TypeNode = undefined,
    string_nonnull: ast.TypeNode = undefined,
    schema_named: ast.TypeNode = undefined,
    schema_nonnull: ast.TypeNode = undefined,
    type_named: ast.TypeNode = undefined,
    name_arg_type: ast.TypeNode = undefined,
    name_args: [1]ast.InputValueDefinitionNode = undefined,

    __typename: ast.FieldDefinitionNode = undefined,
    __schema: ast.FieldDefinitionNode = undefined,
    __type: ast.FieldDefinitionNode = undefined,

    // TODO: review rs usage of OnceLock<MetaFieldDefinitions> = OnceLock::new()
    pub fn get() *const MetaFields {
        if (!meta.ready) {
            meta.init();
            meta.ready = true;
        }
        return &meta;
    }

    fn init(self: *MetaFields) void {
        self.string_named = .{ .NamedType = .{ .name = .{ .value = "String" } } };
        self.string_nonnull = .{ .NonNullType = .{ .type = &self.string_named } };

        self.schema_named = .{ .NamedType = .{ .name = .{ .value = "__Schema" } } };
        self.schema_nonnull = .{ .NonNullType = .{ .type = &self.schema_named } };

        self.type_named = .{ .NamedType = .{ .name = .{ .value = "__Type" } } };

        self.name_arg_type = .{ .NonNullType = .{ .type = &self.string_named } };
        self.name_args = .{.{
            .name = .{ .value = "name" },
            .type = &self.name_arg_type,
            .default_value = null,
            .directives = null,
        }};

        self.__typename = .{
            .name = .{ .value = "__typename" },
            .type = &self.string_nonnull,
            .description = null,
            .arguments = null,
            .directives = null,
        };
        self.__schema = .{
            .name = .{ .value = "__schema" },
            .type = &self.schema_nonnull,
            .description = null,
            .arguments = null,
            .directives = null,
        };
        self.__type = .{
            .name = .{ .value = "__type" },
            .type = &self.type_named,
            .description = null,
            .arguments = &self.name_args,
            .directives = null,
        };
    }
};

var meta: MetaFields = .{};
