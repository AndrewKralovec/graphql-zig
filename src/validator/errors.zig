const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ValidationErrorKind = enum {
    // UniqueArgumentNamesRule
    // UniqueArgument
    /// Unique argument names
    ///
    /// A GraphQL field or directive is only valid if all supplied arguments are
    /// uniquely named.
    ///
    /// See https://spec.graphql.org/draft/#sec-Argument-Names
    DuplicateArgumentName,
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
