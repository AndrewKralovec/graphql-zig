const std = @import("std");

pub const SyntaxKind = enum {
    Document,
    OperationDefinition,
    SelectionSet,
    Field,
    FragmentSpread,
    InlineFragment,
    Name,
    VariableDefinition,
    Int,
    Float,
    NamedType,
    ListType,
    NonNullType,
    Variable,
    String,
    Directive,
    Argument,
    ExecutableDefinition,
    OperationType,
    FieldDefinition,
    InputValueDefinition,
    SchemaDefinition,
    OperationTypeDefinition,
    ScalarTypeDefinition,
    ObjectTypeDefinition,
    InterfaceTypeDefinition,
    UnionTypeDefinition,
    EnumTypeDefinition,
    EnumValueDefinition,
    InputObjectTypeDefinition,
    DirectiveDefinition,
    FragmentDefinition,
    ScalarTypeExtension,
    ObjectTypeExtension,
    InterfaceTypeExtension,
    UnionTypeExtension,
    EnumTypeExtension,
    InputObjectTypeExtension,
    SchemaExtension,
    List,
    Object,
    ObjectField,
    Boolean,
    Null,
    Enum,
};

/// See: https://spec.graphql.org/October2021/#Document
///
/// *Document*
///     Definition*
pub const DocumentNode = struct {
    kind: SyntaxKind = SyntaxKind.Document,
    definitions: []const DefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#Definition
///
/// *Definition*:
///    ExecutableDefinition
///    TypeSystemDefinition
///    TypeSystemExtension
pub const DefinitionNode = union(enum) {
    ExecutableDefinition: ExecutableDefinitionNode,
    TypeSystemDefinition: TypeSystemDefinitionNode,
    TypeSystemExtension: TypeSystemExtensionNode,
};

/// See: https://spec.graphql.org/October2021/#ExecutableDefinition
///
/// *ExecutableDefinition*:
///    OperationDefinition
///    FragmentDefinition
pub const ExecutableDefinitionNode = union(enum) {
    OperationDefinition: OperationDefinitionNode,
    FragmentDefinition: FragmentDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#TypeSystemDefinition
///
/// *TypeSystemDefinition*:
///    SchemaDefinition
///    TypeDefinition
///    DirectiveDefinition
pub const TypeSystemDefinitionNode = union(enum) {
    TypeDefinition: TypeDefinitionNode,
    SchemaDefinition: SchemaDefinitionNode,
    DirectiveDefinition: DirectiveDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#OperationDefinition
///
/// *OperationDefinition*:
///    OperationType Name? VariableDefinitions? Directives? SelectionSet
///    SelectionSet
pub const OperationDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.OperationDefinition,
    operation: OperationType,
    name: ?NameNode,
    variable_definitions: ?[]const VariableDefinitionNode,
    directives: ?[]const DirectiveNode,
    selection_set: ?SelectionSetNode,
};

/// See: https://spec.graphql.org/October2021/#OperationType
///
/// *OperationType*: one of
///    **query**    **mutation**    **subscription**
pub const OperationType = enum {
    Query,
    Mutation,
    Subscription,
};

/// See: https://spec.graphql.org/October2021/#SelectionSet
///
/// *SelectionSet*:
///     **{** Selection* **}**
pub const SelectionSetNode = struct {
    kind: SyntaxKind = SyntaxKind.SelectionSet,
    selections: []const SelectionNode,
};

/// See: https://spec.graphql.org/October2021/#Selection
///
/// *Selection*:
///     Field
///     FragmentSpread
///     InlineFragment
pub const SelectionNode = union(enum) {
    Field: FieldNode,
    FragmentSpread: FragmentSpreadNode,
    InlineFragment: InlineFragmentNode,
};

/// See: https://spec.graphql.org/October2021/#Field
///
/// *Field*:
///     Alias? Name Arguments? Directives? SelectionSet?
pub const FieldNode = struct {
    kind: SyntaxKind = SyntaxKind.Field,
    name: NameNode,
    alias: ?NameNode,
    arguments: ?[]const ArgumentNode,
    directives: ?[]const DirectiveNode,
    selection_set: ?SelectionSetNode,
};

/// See: https://spec.graphql.org/October2021/#FragmentSpread
///
/// *FragmentSpread*:
///     **...** FragmentName Directives?
pub const FragmentSpreadNode = struct {
    kind: SyntaxKind = SyntaxKind.FragmentSpread,
    name: NameNode,
    directives: ?[]const DirectiveNode,
};

/// See: https://spec.graphql.org/October2021/#InlineFragment
///
/// *InlineFragment*:
///     **...** TypeCondition? Directives? SelectionSet
pub const InlineFragmentNode = struct {
    kind: SyntaxKind = SyntaxKind.InlineFragment,
    type_condition: ?NamedTypeNode,
    directives: ?[]const DirectiveNode,
    selection_set: SelectionSetNode,
};

/// See: https://spec.graphql.org/October2021/#Name
///
/// *Name*:
///     [_A-Za-z][_0-9A-Za-z]
pub const NameNode = struct {
    kind: SyntaxKind = SyntaxKind.Name,
    value: []const u8,
};

/// See: https://spec.graphql.org/October2021/#Directive
///
/// *Directive[Const]*:
///     **@** Name Arguments[?Const]?
pub const DirectiveNode = struct {
    kind: SyntaxKind = SyntaxKind.Directive,
    name: NameNode,
    arguments: ?[]const ArgumentNode,
};

/// See: https://spec.graphql.org/October2021/#Argument
///
/// *Argument[Const]*:
///    Name **:** Value[?Const]
pub const ArgumentNode = struct {
    kind: SyntaxKind = SyntaxKind.Argument,
    name: NameNode,
    value: ValueNode,
};

/// See: https://spec.graphql.org/October2021/#Value
///
/// *Value[Const]*
///     [if not Const] Variable
///     IntValue
///     FloatValue
///     StringValue
///     BooleanValue
///     NullValue
///     EnumValue
///     ListValue[?Const]
///     ObjectValue[?Const]
// TODO: should we separate node for const values?
// If we need to differentiate between comptime(fixed) and runtime values
// We need to indicate that in the AST, either by type or field. Come back to this later.
pub const ValueNode = union(enum) {
    Variable: VariableNode,
    Int: IntValueNode,
    Float: FloatValueNode,
    String: StringValueNode,
    Boolean: BooleanValueNode,
    Null: NullValueNode,
    Enum: EnumValueNode,
    List: ListValueNode,
    Object: ObjectValueNode,
};

/// See: https://spec.graphql.org/October2021/#Variable
///
/// *Variable*:
///     **$** Name
pub const VariableNode = struct {
    kind: SyntaxKind = SyntaxKind.Variable,
    name: NameNode,
};

/// See: https://spec.graphql.org/October2021/#StringValue
///
/// *StringValue*:
///   **"** [^"\\]*(?:\\.[^"\\]*)* **"**
pub const StringValueNode = struct {
    kind: SyntaxKind = SyntaxKind.String,
    value: []const u8,
};

/// See: https://spec.graphql.org/October2021/#IntValue
///
/// *IntValue*:
///   **-**? **Digit+**
pub const IntValueNode = struct {
    kind: SyntaxKind = SyntaxKind.Int,
    value: []const u8,
};

/// See: https://spec.graphql.org/October2021/#FloatValue
///
/// *FloatValue*:
///    **Digit+** **.** **Digit+**
pub const FloatValueNode = struct {
    kind: SyntaxKind = SyntaxKind.Float,
    value: []const u8,
};

/// See: https://spec.graphql.org/October2021/#ListValue
///
/// *ListValue[Const]*:
///     **[** **]**
///     **[** Value[?Const]* **]**
pub const ListValueNode = struct {
    kind: SyntaxKind = SyntaxKind.List,
    values: []const ValueNode,
};

/// See: https://spec.graphql.org/October2021/#ObjectValue
///
/// *ObjectValue[Const]*:
///     **{** **}**
///     **{** ObjectField[?Const]* **}**
pub const ObjectValueNode = struct {
    kind: SyntaxKind = SyntaxKind.Object,
    fields: []const ObjectFieldNode,
};

/// See: https://spec.graphql.org/October2021/#ObjectField
///
/// *ObjectField[Const]*:
///     Name **:** Value[?Const]
pub const ObjectFieldNode = struct {
    kind: SyntaxKind = SyntaxKind.ObjectField,
    name: NameNode,
    value: ValueNode,
};

/// See: https://spec.graphql.org/October2021/#BooleanValue
///
/// *BooleanValue*:
///     **true** | **false**
pub const BooleanValueNode = struct {
    kind: SyntaxKind = SyntaxKind.Boolean,
    value: bool,
};

/// See: https://spec.graphql.org/October2021/#NullValue
///
/// *NullValue*:
///     **null**
pub const NullValueNode = struct {
    kind: SyntaxKind = SyntaxKind.Null,
};

/// See: https://spec.graphql.org/October2021/#EnumValue
///
/// *EnumValue*:
///     Name *but not* **true** *or* **false** *or* **null**
pub const EnumValueNode = struct {
    kind: SyntaxKind = SyntaxKind.Enum,
    value: []const u8,
};

/// See: https://spec.graphql.org/October2021/#VariableDefinition
///
/// *VariableDefinition*:
///     Variable **:** Type DefaultValue? Directives[Const]?
///
pub const VariableDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.VariableDefinition,
    variable: VariableNode,
    type: *TypeNode,
    default_value: ?ValueNode, // ConstValueNode
    directives: ?[]const DirectiveNode, // ConstDirectiveNode
};

/// See: https://spec.graphql.org/October2021/#Type
///
/// *Type*:
///     NamedType
///     ListType
///         **[** Type **]**
///     NonNullType
///         NamedType **!**
///         ListType **!**
pub const TypeNode = union(enum) {
    NamedType: NamedTypeNode,
    ListType: ListTypeNode,
    NonNullType: NonNullTypeNode,

    pub fn deinit(self: *const TypeNode, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .NamedType => {},
            .ListType => |list_type| {
                list_type.type.deinit(allocator);
                allocator.destroy(list_type.type);
            },
            .NonNullType => |non_null_type| {
                non_null_type.type.deinit(allocator);
                allocator.destroy(non_null_type.type);
            },
        }
    }

    pub fn isNonNull(self: *const TypeNode) bool {
        return self.* == .NonNullType;
    }

    pub fn nullable(self: *const TypeNode) *const TypeNode {
        return switch (self.*) {
            .NonNullType => |non_null| non_null.type,
            else => self,
        };
    }

    pub fn isAssignableTo(self: *const TypeNode, target: *const TypeNode) bool {
        switch (target.*) {
            .NonNullType => |target_nn| {
                switch (self.*) {
                    .NonNullType => |self_nn| return self_nn.type.isAssignableTo(target_nn.type),
                    else => return false,
                }
            },
            .ListType => |target_list| {
                const unwrapped = self.nullable();
                switch (unwrapped.*) {
                    .ListType => |self_list| return self_list.type.isAssignableTo(target_list.type),
                    else => return false,
                }
            },
            .NamedType => |target_named| {
                const unwrapped = self.nullable();
                switch (unwrapped.*) {
                    .NamedType => |self_named| return std.mem.eql(u8, self_named.name.value, target_named.name.value),
                    else => return false,
                }
            },
        }
    }
};

/// See: https://spec.graphql.org/October2021/#NamedType
///
/// *NamedType*:
///     Name
pub const NamedTypeNode = struct {
    kind: SyntaxKind = SyntaxKind.NamedType,
    name: NameNode,
};

/// See: https://spec.graphql.org/October2021/#ListType
///
/// *ListType*:
///     **[** Type **]**
pub const ListTypeNode = struct {
    kind: SyntaxKind = SyntaxKind.ListType,
    type: *TypeNode,
};

// See: https://spec.graphql.org/October2021/#NonNullType
///
/// *NonNullType*:
///     NamedType **!**
///     ListType **!**
pub const NonNullTypeNode = struct {
    kind: SyntaxKind = SyntaxKind.NonNullType,
    type: *TypeNode,
};

/// See: https://spec.graphql.org/October2021/#SchemaDefinition
///
/// *SchemaDefinition*:
///     Description? **schema** Directives[Const]? **{** RootOperationTypeDefinition* **}**
pub const SchemaDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.SchemaDefinition,
    description: ?StringValueNode,
    directives: ?[]const DirectiveNode,
    operation_types: []const OperationTypeDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#OperationDefinition
///
/// *OperationDefinition*:
///    OperationType Name? VariableDefinitions? Directives? SelectionSet
///    SelectionSet
pub const OperationTypeDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.OperationTypeDefinition,
    operation: OperationType,
    type: NamedTypeNode,
};

/// See: https://spec.graphql.org/October2021/#TypeDefinition
///
/// *TypeDefinition*:
///     ScalarTypeDefinition
///     ObjectTypeDefinition
///     InterfaceTypeDefinition
///     UnionTypeDefinition
///     EnumTypeDefinition
///     InputObjectTypeDefinition
pub const TypeDefinitionNode = union(enum) {
    ScalarTypeDefinition: ScalarTypeDefinitionNode,
    ObjectTypeDefinition: ObjectTypeDefinitionNode,
    InterfaceTypeDefinition: InterfaceTypeDefinitionNode,
    UnionTypeDefinition: UnionTypeDefinitionNode,
    EnumTypeDefinition: EnumTypeDefinitionNode,
    InputObjectTypeDefinition: InputObjectTypeDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#ScalarTypeDefinition
///
/// *ScalarTypeDefinition*:
///     Description? **scalar** Name Directives[Const]?
pub const ScalarTypeDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.ScalarTypeDefinition,
    description: ?StringValueNode,
    name: NameNode,
    directives: ?[]const DirectiveNode, // ConstDirectiveNode
};

/// See: https://spec.graphql.org/October2021/#ObjectTypeDefinition
///
/// *ObjectTypeDefinition*:
///     Description? **type** Name ImplementsInterfaces? Directives[Const]? FieldsDefinition?
pub const ObjectTypeDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.ObjectTypeDefinition,
    name: NameNode,
    description: ?StringValueNode,
    interfaces: ?[]const NamedTypeNode,
    directives: ?[]const DirectiveNode,
    fields: ?[]const FieldDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#InterfaceTypeDefinition
///
/// *InterfaceTypeDefinition*:
///     Description? **interface** Name ImplementsInterface? Directives[Const]? FieldsDefinition?
pub const InterfaceTypeDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.InterfaceTypeDefinition,
    name: NameNode,
    description: ?StringValueNode,
    interfaces: ?[]const NamedTypeNode,
    directives: ?[]const DirectiveNode, // ConstDirectiveNode
    fields: ?[]const FieldDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#UnionTypeDefinition
///
/// *UnionTypeDefinition*:
///     Description? **union** Name Directives[Const]? UnionDefMemberTypes?
pub const UnionTypeDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.UnionTypeDefinition,
    name: NameNode,
    description: ?StringValueNode,
    directives: ?[]const DirectiveNode, // ConstDirectiveNode
    types: ?[]const NamedTypeNode,
};

/// See: https://spec.graphql.org/October2021/#EnumTypeDefinition
///
/// *EnumTypeDefinition*:
///     Description? **enum** Name Directives? EnumValuesDefinition?
pub const EnumTypeDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.EnumTypeDefinition,
    name: NameNode,
    description: ?StringValueNode,
    directives: ?[]const DirectiveNode, // ConstDirectiveNode
    values: ?[]const EnumValueDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#EnumValueDefinition
///
/// *EnumValueDefinition*:
///     Description? EnumValue Directives[Const]?
pub const EnumValueDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.EnumValueDefinition,
    name: NameNode,
    description: ?StringValueNode,
    directives: ?[]const DirectiveNode, // ConstDirectiveNode
};

/// See: https://spec.graphql.org/October2021/#FieldDefinition
///
/// *FieldDefinition*:
///     Description? Name ArgumentsDefinition? **:** Type Directives[Const]?
pub const FieldDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.FieldDefinition,
    name: NameNode,
    type: *TypeNode,
    description: ?StringValueNode,
    arguments: ?[]const InputValueDefinitionNode,
    directives: ?[]const DirectiveNode,
};

/// See: https://spec.graphql.org/October2021/#InputObjectTypeDefinition
///
/// *InputObjectTypeDefinition*:
///     Description? **input** Name Directives[Const]? InputFieldsDefinition?
pub const InputObjectTypeDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.InputObjectTypeDefinition,
    name: NameNode,
    description: ?StringValueNode,
    directives: ?[]const DirectiveNode, // ConstDirectiveNode
    fields: ?[]const InputValueDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#InputValueDefinition
///
/// *InputValueDefinition*:
///     Description? Name **:** Type DefaultValue? Directives[Const]?
pub const InputValueDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.InputValueDefinition,
    name: NameNode,
    type: *TypeNode,
    default_value: ?ValueNode,
    directives: ?[]const DirectiveNode,
};

/// See: https://spec.graphql.org/October2021/#DirectiveDefinition
///
/// *DirectiveDefinition*:
///     Description? **directive @** Name ArgumentsDefinition? **repeatable**? **on** DirectiveLocations
pub const DirectiveDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.DirectiveDefinition,
    description: ?StringValueNode,
    name: NameNode,
    arguments: ?[]const InputValueDefinitionNode,
    repeatable: bool,
    locations: []const NameNode,
};

/// See: https://spec.graphql.org/October2021/#FragmentDefinition
///
/// *FragmentDefinition*:
///     **fragment** FragmentName TypeCondition Directives? SelectionSet
pub const FragmentDefinitionNode = struct {
    kind: SyntaxKind = SyntaxKind.FragmentDefinition,
    name: NameNode,
    type_condition: NamedTypeNode,
    directives: ?[]const DirectiveNode,
    selection_set: SelectionSetNode,
};

// See: https://spec.graphql.org/October2021/#TypeSystemExtension
///
/// *TypeSystemExtension*:
///    SchemaExtension
///    TypeExtension
///    DirectiveDefinition
pub const TypeSystemExtensionNode = union(enum) {
    SchemaExtension: SchemaExtensionNode,
    TypeExtension: TypeExtensionNode,
};

/// See: https://spec.graphql.org/October2021/#SchemaExtension
///
/// *SchemaExtension*:
///     **extend** **schema** Directives[Const]? **{** RootOperationTypeDefinition* **}**
///     **extend** **schema** Directives[Const]
pub const SchemaExtensionNode = struct {
    kind: SyntaxKind = SyntaxKind.SchemaExtension,
    directives: ?[]const DirectiveNode,
    operation_types: ?[]const OperationTypeDefinitionNode,
};

// TODO: This is very similar to TypeDefinitionNode.
// We should consider merging them in the future.
// But for now, we will keep them separate for clarity.
// This is a type extension node. It is used to extend existing types in the schema.
/// See: https://spec.graphql.org/October2021/#TypeExtension
/// *TypeExtension*:
///    ScalarTypeExtension
///    ObjectTypeExtension
///    InterfaceTypeExtension
///    UnionTypeExtension
///    EnumTypeExtension
///    InputObjectTypeExtension
pub const TypeExtensionNode = union(enum) {
    ScalarTypeExtension: ScalarTypeExtensionNode,
    ObjectTypeExtension: ObjectTypeExtensionNode,
    InterfaceTypeExtension: InterfaceTypeExtensionNode,
    UnionTypeExtension: UnionTypeExtensionNode,
    EnumTypeExtension: EnumTypeExtensionNode,
    InputObjectTypeExtension: InputObjectTypeExtensionNode,
};

/// See: https://spec.graphql.org/October2021/#ScalarTypeExtension
///
/// *ScalarTypeExtension*:
///     **extend** **scalar** Name Directives[Const]
pub const ScalarTypeExtensionNode = struct {
    kind: SyntaxKind = SyntaxKind.ScalarTypeExtension,
    name: NameNode,
    directives: ?[]const DirectiveNode,
};

/// See: https://spec.graphql.org/October2021/#ObjectTypeExtension
///
/// *ObjectTypeExtension*:
///     **extend** **type** Name ImplementsInterfaces? Directives[Const]? FieldsDefinition
///     **extend** **type** Name ImplementsInterfaces? Directives[Const]?
///     **extend** **type** Name ImplementsInterfaces
pub const ObjectTypeExtensionNode = struct {
    kind: SyntaxKind = SyntaxKind.ObjectTypeExtension,
    name: NameNode,
    interfaces: ?[]const NamedTypeNode,
    directives: ?[]const DirectiveNode,
    fields: ?[]const FieldDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#InterfaceTypeExtension
///
/// *InterfaceTypeExtension*:
///     **extend** **interface** Name ImplementsInterface? Directives[Const]? FieldsDefinition
///     **extend** **interface** Name ImplementsInterface? Directives[Const]
///     **extend** **interface** Name ImplementsInterface
pub const InterfaceTypeExtensionNode = struct {
    kind: SyntaxKind = SyntaxKind.InterfaceTypeExtension,
    name: NameNode,
    interfaces: ?[]const NamedTypeNode,
    directives: ?[]const DirectiveNode,
    fields: ?[]const FieldDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#UnionTypeExtension
///
/// *UnionTypeExtension*:
///     **extend** **union** Name Directives[Const]? UnionDefMemberTypes
///     **extend** **union** Name Directives[Const]
pub const UnionTypeExtensionNode = struct {
    kind: SyntaxKind = SyntaxKind.UnionTypeExtension,
    name: NameNode,
    directives: ?[]const DirectiveNode,
    types: ?[]const NamedTypeNode,
};

/// See: https://spec.graphql.org/October2021/#EnumTypeExtension
///
// *EnumTypeExtension*:
///    **extend** **enum** Name Directives[Const]? EnumValuesDefinition
///    **extend** **enum** Name Directives[Const]?
pub const EnumTypeExtensionNode = struct {
    kind: SyntaxKind = SyntaxKind.EnumTypeExtension,
    name: NameNode,
    directives: ?[]const DirectiveNode,
    values: ?[]const EnumValueDefinitionNode,
};

/// See: https://spec.graphql.org/October2021/#InputObjectTypeExtension
///
/// *InputObjectTypeExtension*:
///     **extend** **input** Name Directives[Const]? InputFieldsDefinition
///     **extend** **input** Name Directives[Const]
pub const InputObjectTypeExtensionNode = struct {
    kind: SyntaxKind = SyntaxKind.InputObjectTypeExtension,
    name: NameNode,
    directives: ?[]const DirectiveNode,
    fields: ?[]const InputValueDefinitionNode,
};

const directive_locations = [_][]const u8{
    "QUERY",
    "MUTATION",
    "SUBSCRIPTION",
    "FIELD",
    "FRAGMENT_DEFINITION",
    "FRAGMENT_SPREAD",
    "INLINE_FRAGMENT",
    "VARIABLE_DEFINITION",
    "SCHEMA",
    "SCALAR",
    "OBJECT",
    "FIELD_DEFINITION",
    "ARGUMENT_DEFINITION",
    "INTERFACE",
    "UNION",
    "ENUM",
    "ENUM_VALUE",
    "INPUT_OBJECT",
    "INPUT_FIELD_DEFINITION",
};

/// Checks if the given string matches a known GraphQL directive location.
pub fn is_directive_location(value: []const u8) bool {
    inline for (directive_locations) |loc| {
        if (std.mem.eql(u8, value, loc)) {
            return true;
        }
    }
    return false;
}

/// See: https://spec.graphql.org/October2021/#DirectiveLocation
pub const DirectiveLocation = enum {
    Query,
    Mutation,
    Subscription,
    Field,
    FragmentDefinition,
    FragmentSpread,
    InlineFragment,
    VariableDefinition,
    Schema,
    Scalar,
    Object,
    FieldDefinition,
    ArgumentDefinition,
    Interface,
    Union,
    Enum,
    EnumValue,
    InputObject,
    InputFieldDefinition,
};

const directive_location_map = std.StaticStringMap(DirectiveLocation).initComptime(.{
    .{ "QUERY", .Query },
    .{ "MUTATION", .Mutation },
    .{ "SUBSCRIPTION", .Subscription },
    .{ "FIELD", .Field },
    .{ "FRAGMENT_DEFINITION", .FragmentDefinition },
    .{ "FRAGMENT_SPREAD", .FragmentSpread },
    .{ "INLINE_FRAGMENT", .InlineFragment },
    .{ "VARIABLE_DEFINITION", .VariableDefinition },
    .{ "SCHEMA", .Schema },
    .{ "SCALAR", .Scalar },
    .{ "OBJECT", .Object },
    .{ "FIELD_DEFINITION", .FieldDefinition },
    .{ "ARGUMENT_DEFINITION", .ArgumentDefinition },
    .{ "INTERFACE", .Interface },
    .{ "UNION", .Union },
    .{ "ENUM", .Enum },
    .{ "ENUM_VALUE", .EnumValue },
    .{ "INPUT_OBJECT", .InputObject },
    .{ "INPUT_FIELD_DEFINITION", .InputFieldDefinition },
});

pub fn directiveLocationFromString(value: []const u8) ?DirectiveLocation {
    return directive_location_map.get(value);
}

/// This enum defines the keywords in the GraphQL syntax.
/// The keywords are used to identify the type of node in the AST.
pub const SyntaxKeyWord = enum {
    Directive,
    Enum,
    Extend,
    Fragment,
    Input,
    Interface,
    Type,
    Query,
    Mutation,
    Subscription,
    LCurly,
    Scalar,
    Schema,
    Union,
    Implements,
    On,
    Repeatable,
};

/// This struct is used to map keywords to their corresponding enum values.
const KeywordMap = struct {
    name: []const u8,
    value: SyntaxKeyWord,
};

/// This is a map of keywords to their corresponding enum values.
const keyword_map = [_]KeywordMap{
    .{ .name = "directive", .value = SyntaxKeyWord.Directive },
    .{ .name = "enum", .value = SyntaxKeyWord.Enum },
    .{ .name = "extend", .value = SyntaxKeyWord.Extend },
    .{ .name = "fragment", .value = SyntaxKeyWord.Fragment },
    .{ .name = "input", .value = SyntaxKeyWord.Input },
    .{ .name = "interface", .value = SyntaxKeyWord.Interface },
    .{ .name = "type", .value = SyntaxKeyWord.Type },
    .{ .name = "query", .value = SyntaxKeyWord.Query },
    .{ .name = "mutation", .value = SyntaxKeyWord.Mutation },
    .{ .name = "subscription", .value = SyntaxKeyWord.Subscription },
    .{ .name = "{", .value = SyntaxKeyWord.LCurly },
    .{ .name = "scalar", .value = SyntaxKeyWord.Scalar },
    .{ .name = "schema", .value = SyntaxKeyWord.Schema },
    .{ .name = "union", .value = SyntaxKeyWord.Union },
    .{ .name = "implements", .value = SyntaxKeyWord.Implements },
    .{ .name = "on", .value = SyntaxKeyWord.On },
    .{ .name = "repeatable", .value = SyntaxKeyWord.Repeatable },
};

/// Converts to a `SyntaxKeyWord` or returns null if not in the SyntaxKeyWord enum.
pub fn stringToKeyword(str: []const u8) ?SyntaxKeyWord {
    inline for (keyword_map) |entry| {
        if (std.mem.eql(u8, entry.name, str)) {
            return entry.value;
        }
    }
    return null;
}
