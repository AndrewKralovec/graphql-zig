const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ValidationErrorKind = enum {
    // UniqueArgumentNamesRule
    /// Unique argument names
    ///
    /// A GraphQL field or directive is only valid if all supplied arguments are
    /// uniquely named.
    ///
    /// See https://spec.graphql.org/draft/#sec-Argument-Names
    UniqueArgumentName,
    // ExecutableDefinitionsRule
    /// Executable definitions
    ///
    /// A GraphQL document is only valid for execution if all definitions are either
    /// operation or fragment definitions.
    ///
    /// See https://spec.graphql.org/draft/#sec-Executable-Definitions
    NonExecutableDefinition,
    // LoneAnonymousOperationRule
    /// Lone anonymous operation
    ///
    /// A GraphQL document is only valid if when it contains an anonymous operation
    /// (the query short-hand) that it contains only that one operation definition.
    ///
    /// See https://spec.graphql.org/draft/#sec-Lone-Anonymous-Operation
    LoneAnonymousOperation,
    // UniqueOperationNamesRule
    /// Unique operation names
    ///
    /// A GraphQL document is only valid if all defined operations have unique names.
    ///
    /// See https://spec.graphql.org/draft/#sec-Operation-Name-Uniqueness
    UniqueOperation,
    // UniqueDirectivesPerLocationRule
    /// Unique directives per location
    ///
    /// A GraphQL directive is only valid if it's not repeated when non-repeatable.
    ///
    /// See https://spec.graphql.org/draft/#sec-Directives-Are-Unique-Per-Location
    UniqueDirective,
    // KnownDirectivesRule
    /// Known directives
    ///
    /// A GraphQL document is only valid if all `@directives` are known by the
    /// schema and legally positioned.
    ///
    /// See https://spec.graphql.org/draft/#sec-Directives-Are-Defined
    UndefinedDirective,
    // KnownDirectivesRule
    /// Directives are in valid locations
    ///
    /// A GraphQL document is only valid if all directives are used in locations
    /// that are valid for those directives.
    ///
    /// See https://spec.graphql.org/draft/#sec-Directives-Are-In-Valid-Locations
    UnsupportedLocation,
    // KnownArgumentNamesRule
    /// Known argument names
    ///
    /// A GraphQL field or directive is only valid if all supplied arguments are
    /// defined by that field or directive.
    ///
    /// See https://spec.graphql.org/draft/#sec-Argument-Names
    UndefinedArgument,
    // FieldsOnCorrectTypeRule
    /// A queried field does not exist on the type it is selected from.
    ///
    /// See https://spec.graphql.org/draft/#sec-Field-Selections
    UndefinedField,
    // ProvidedRequiredArgumentsRule
    /// Required argument is missing or null.
    /// A field or directive is only valid if all required (non-null without a
    /// default value) field arguments have been provided.
    ///
    /// See https://spec.graphql.org/draft/#sec-Required-Arguments
    RequiredArgument,
    // NoUnusedVariablesRule
    /// A GraphQL operation is only valid if all variables defined by an operation
    /// are used, either directly or within a spread fragment.
    ///
    /// See https://spec.graphql.org/draft/#sec-All-Variables-Used
    UnusedVariable,
    // RecursionError
    /// Selection set recursion exceeded the configured depth limit.
    RecursionError,
    // VariablesInAllowedPositionRule
    /// Variable usages must be compatible with the arguments they are passed to.
    ///
    /// See https://spec.graphql.org/draft/#sec-All-Variable-Usages-Are-Allowed
    DisallowedVariableUsage,
    // UniqueVariableNamesRule
    /// Unique variable names
    ///
    /// A GraphQL operation is only valid if all its variables are uniquely named.
    /// See https://spec.graphql.org/draft/#sec-Variable-Uniqueness
    UniqueVariable,
    // VariablesAreInputTypesRule
    /// Variables are input types
    ///
    /// A GraphQL operation is only valid if all the variables it defines are of
    /// input types (scalar, enum, or input object).
    /// See https://spec.graphql.org/draft/#sec-Variables-Are-Input-Types
    VariableInputType,
    // KnownTypeNamesRule
    /// Known type names
    ///
    /// A referenced type is not defined in the schema.
    ///
    /// See https://spec.graphql.org/draft/#sec-Named-Type-References
    UndefinedDefinition,
    /// Field selections on composite types must have sub-selections.
    ///
    /// A field that returns a composite type (Object, Interface, Union)
    /// must include a selection set.
    ///
    /// See https://spec.graphql.org/draft/#sec-Leaf-Field-Selections
    MissingSubselection,
    /// Leaf field selections must not have sub-selections.
    ///
    /// A field that returns a scalar or enum type must NOT include a selection set.
    ///
    /// See https://spec.graphql.org/draft/#sec-Leaf-Field-Selections
    SelectionOnLeafField,
    // OutputTypeValidation
    /// Output types
    ///
    /// A field definition's return type is not a valid output type.
    /// Field types in Object Types must be of output type
    /// (Scalar, Object, Interface, Union, or Enum).
    ///
    /// See https://spec.graphql.org/draft/#sec-Objects
    OutputType,
    // ValuesOfCorrectTypeRule
    /// A value is not compatible with the expected type.
    /// See https://spec.graphql.org/draft/#sec-Values-of-Correct-Type
    UnsupportedValueType,
    /// An Int value is out of the 32-bit signed integer range.
    IntCoercionError,
    /// A Float value could not be coerced to f64.
    FloatCoercionError,
    /// An enum value is not defined in the enum type.
    /// See https://spec.graphql.org/draft/#sec-Values-of-Correct-Type.Enum
    UndefinedEnumValue,
    /// An enum type must define one or more unique enum values.
    /// See https://spec.graphql.org/draft/#sel-DAHfFVFBAAEXBAAh7S
    EmptyValueSet,
    /// An object type or interface type must define one or more fields.
    /// See https://spec.graphql.org/draft/#sel-FAHZhCFDBAACDA4qe
    EmptyFieldSet,
    /// A union type must define one or more unique member types.
    /// See https://spec.graphql.org/draft/#sel-HAHdfFBABAB6Bw3R
    EmptyMemberSet,
    /// A union member type must be an Object type.
    /// Scalars, enums, interfaces, input objects, and other unions are not allowed.
    /// See https://spec.graphql.org/draft/#sec-Unions
    UnionMemberObjectType,
    /// An object type implementing an interface is missing a required field from that interface.
    /// See https://spec.graphql.org/draft/#sel-FAHbhCFNFAAhC3Xbb
    MissingInterfaceField,
    /// A variable referenced in a value is not defined.
    UndefinedVariable,
    /// A required field of an input object is missing or null.
    RequiredField,
    /// A field provided on an input object is not defined in the type.
    UndefinedInputValue,
    // FragmentsOnCompositeTypesRule
    /// Fragment's type condition is not a composite type.
    ///
    /// Fragments can only be defined on Object, Interface, or Union types.
    /// A fragment on a scalar, enum, or input type is invalid.
    ///
    /// See https://spec.graphql.org/draft/#sec-Fragments-On-Composite-Types
    InvalidFragmentTarget,
    // PossibleFragmentSpreadsRule
    /// Fragment spread is not possible against parent type.
    ///
    /// The concrete object types of the fragment's type condition and the
    /// parent type must have at least one type in common.
    ///
    /// See https://spec.graphql.org/draft/#sec-Fragment-spread-is-possible
    InvalidFragmentSpread,
    /// The referenced fragment is not defined in the document.
    ///
    /// See https://spec.graphql.org/draft/#sec-Fragment-spread-target-defined
    UndefinedFragment,
    /// An interface type declares itself in its implements list.
    ///
    /// See https://spec.graphql.org/draft/#sel-HAHdnBFBABABxB4V
    RecursiveInterfaceDefinition,
    /// A type implements interface B, and B implements interface A, but the type
    /// does not also declare that it implements A.
    ///
    /// See https://spec.graphql.org/draft/#sel-HAHhpJFCAACCBl1g
    TransitiveImplementedInterfaces,
    /// An implementing field's return type is not a valid subtype of the
    /// corresponding interface field's return type.
    ///
    /// See https://spec.graphql.org/draft/#IsValidImplementationFieldType()
    InvalidImplementationFieldType,
    /// An implementing field is missing an argument that the interface field declares.
    ///
    /// See https://spec.graphql.org/draft/#IsValidImplementation()
    MissingInterfaceFieldArgument,
    /// An implementing field has an argument whose type does not exactly match the
    /// type of the same-named argument on the interface field.
    ///
    /// See https://spec.graphql.org/draft/#IsValidImplementation()
    InvalidImplementationFieldArgumentType,
    /// An implementing field adds a required argument (non-null without a default)
    /// that is not present on the interface field.
    ///
    /// See https://spec.graphql.org/draft/#IsValidImplementation()
    ExtraRequiredImplementationFieldArgument,
    /// An input object has no fields defined.
    /// See https://spec.graphql.org/draft/#sel-HAHhBXDBABAB5BvgD
    EmptyInputValueSet,
    /// An input object type contains a circular reference through NonNull fields.
    /// See https://spec.graphql.org/October2021/#sec-Input-Objects.Circular-References
    RecursiveInputObjectDefinition,
    /// A directive definition references itself directly or transitively through its arguments.
    /// See https://spec.graphql.org/draft/#sec-Type-System.Directives
    RecursiveDirectiveDefinition,
    /// An input object (or other type) nests too deeply for the validator to check.
    /// Triggered when the cycle-detection depth limit (32) is reached.
    /// See https://spec.graphql.org/October2021/#sec-Input-Objects.Circular-References
    DeeplyNestedType,
    /// An argument or input field references a type that is not an input type.
    /// Input positions only accept Scalar, Enum, or InputObject types.
    /// See https://spec.graphql.org/draft/#sec-Input-and-Output-Types
    InputType,
    /// Duplicate argument or input field name at the definition site.
    /// See https://spec.graphql.org/draft/#sec-Argument-Uniqueness
    UniqueInputValue,
    /// A type or directive is defined more than once in the schema.
    /// The first definition wins; subsequent ones are ignored.
    /// See https://spec.graphql.org/draft/#sec-Type-System
    UniqueDefinition,
    /// A type, directive, field, or argument name starts with __ (double underscore),
    /// which is reserved for GraphQL introspection system use.
    /// See https://spec.graphql.org/draft/#sec-Names.Reserved-Names
    ReservedName,
    /// A fragment definition directly or transitively spreads itself,
    /// forming a cycle. Cycles are forbidden.
    /// See https://spec.graphql.org/draft/#sec-Fragment-spreads-must-not-form-cycles
    RecursiveFragmentDefinition,
    /// A fragment is defined but never used in any operation.
    /// See https://spec.graphql.org/draft/#sec-Fragments-Must-Be-Used
    UnusedFragment,
    /// A schema definition does not declare a Query root operation type.
    /// See https://spec.graphql.org/draft/#sec-Root-Operation-Types
    QueryRootOperationType,
    /// A root operation type (query/mutation/subscription) references a non-Object type.
    /// Scalars, enums, interfaces, unions, and input objects are not allowed here.
    /// See https://spec.graphql.org/draft/#sec-Root-Operation-Types
    RootOperationObjectType,
    // FieldsInSetCanMergeRule
    /// Two fields share the same response key but refer to different field names.
    /// See https://spec.graphql.org/draft/#sec-Field-Selection-Merging
    ConflictingFieldName,
    /// Two fields share the same response key but have non-identical argument sets.
    /// See https://spec.graphql.org/draft/#sec-Field-Selection-Merging
    ConflictingFieldArgument,
    /// Two fields share the same response key but have incompatible return type shapes.
    /// See https://spec.graphql.org/draft/#sec-Field-Selection-Merging
    ConflictingFieldType,
};

// TODO: import the validation object in the future
// for now, let it be a wrapper around the error kind.
// i can just replace ValidationError with the enum, would be easy if i choose.
pub const ValidationError = struct {
    kind: ValidationErrorKind,

    pub fn init(kind: ValidationErrorKind) ValidationError {
        return ValidationError{ .kind = kind };
    }

    pub fn deinit(self: *ValidationError) void {
        _ = self; // TODO: decide later
    }
};

pub const DiagnosticList = struct {
    allocator: Allocator,
    errors: std.ArrayList(ValidationError),

    pub fn init(allocator: Allocator) DiagnosticList {
        return DiagnosticList{
            .allocator = allocator,
            .errors = std.ArrayList(ValidationError).init(allocator),
        };
    }

    pub fn deinit(self: *DiagnosticList) void {
        self.errors.deinit();
    }

    pub fn push(self: *DiagnosticList, kind: ValidationErrorKind) !void {
        const err = ValidationError.init(kind);
        try self.errors.append(err);
    }

    pub fn toOwnedSlice(self: *DiagnosticList) ![]ValidationError {
        return self.errors.toOwnedSlice();
    }

    pub fn len(self: *const DiagnosticList) usize {
        return self.errors.items.len;
    }
};
