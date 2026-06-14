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
    // Directive validation errors
    /// Unique directive
    ///
    /// A GraphQL directive is only valid if it's not repeated when non-repeatable.
    UniqueDirective,
    // KnownDirectivesRule
    /// Known directives
    ///
    /// A GraphQL document is only valid if all `@directives` are known by the
    /// schema and legally positioned.
    ///
    /// See https://spec.graphql.org/draft/#sec-Directives-Are-Defined
    UndefinedDirective,
    /// Directive used at an unsupported location.
    ///
    /// See https://spec.graphql.org/draft/#sec-Directives-Are-In-Valid-Locations
    UnsupportedLocation,
    /// Argument not defined for a directive.
    ///
    /// See https://spec.graphql.org/draft/#sec-Directives-Are-Defined
    UndefinedArgument,
    /// Required argument is missing or null.
    /// A field or directive is only valid if all required (non-null without a
    /// default value) field arguments have been provided.
    ///
    /// See https://spec.graphql.org/draft/#sec-Required-Arguments
    RequiredArgument,
    // UnusedVariableRule
    /// All variables defined by an operation must be used in that operation
    /// or a fragment transitively included by that operation. Unused variables
    /// cause a validation error.
    ///
    /// See https://spec.graphql.org/draft/#sec-All-Variables-Used
    UnusedVariable,
    // RecursionError
    /// Selection set recursion exceeded the configured depth limit.
    RecursionError,
    // AllVariableUsagesAllowedRule
    /// Variable usages must be compatible with the arguments they are
    /// passed to.
    ///
    /// See https://spec.graphql.org/draft/#sec-All-Variable-Usages-Are-Allowed
    DisallowedVariableUsage,
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
    // TODO: We use this allocator for non error reasons.
    // which is convenient, but not proper use.
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
