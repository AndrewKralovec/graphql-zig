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
        _ = self;
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
