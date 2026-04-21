# graphql-zig
A graphql parsing library written in zig.
After reading that [bun](https://bun.sh/) was coded in zig, i wanted to try it out.

## Table of Contents

- [Getting Started](#getting-started)
- [Usage](#usage)
    - [Lexer](#lexer) for tokenization.
    - [Parser](#parser) for building an abstract syntax tree (AST).
- [Benchmarks](#benchmarks)
- [TODO](#todo)
- [Inspiration And Resources](#inspiration-and-resources)

## Getting Started

### Prerequisites

- [Zig](https://ziglang.org/) (version 0.14.0 or later)

### Building

To build the project, use the following command

```bash
zig build
```

To enable debug mode, pass the `-Ddebug=true` flag when building or testing the project

```bash
zig build -Ddebug=true
```

When debug mode is enabled, the parser will print additional state and parsing details.
This option might go away after the project matures.

### Testing

To run the project tests

```bash
zig build test
```

## Usage

graphql-zig provides two main components for working with GraphQL.

- [Lexer](#lexer) for tokenization.
- [Parser](#parser) for building an abstract syntax tree (AST).

### Lexer

The `Lexer` tokenizes GraphQL text into individual tokens, which can then be processed by the parser or analyzed directly. It exposes several methods for tokenization and navigation.

#### Tokenization

The simplest way to use the lexer is to tokenize an entire GraphQL document at once. The `tokenize()` method returns all tokens or the first error encountered during scanning.
This approach is useful when you want fail-fast behavior that stops at the first error rather than collecting all errors.


Example.
```zig
const source =
    \\ query {
    \\  users(id: 1) {
    \\   id
    \\  }
    \\ }
;

const Lexer = @import("graphql").lexer.Lexer;
var lexer = Lexer.init(source, .{});
const tokens = try lexer.tokenize(allocator);
defer allocator.free(tokens);

for (tokens) |token| {
    // Process each token.
}
```

The library exposes a `tokenize()` function, which provides a convenient way to tokenize GraphQL documents without manually creating a Lexer instance.


Example.
```zig
const graphql = @import("graphql");

const tokens = try graphql.lexer.tokenize(allocator, source);
defer allocator.free(tokens);
```

#### Stream Lexing

Sometimes you need more control over the tokenization process. The `next()` method allows you to read tokens one at a time, which is useful for streaming scenarios or when you want to process tokens immediately as they are read. The `next()` method returns an optional token when you hit the end of the input, you get `null`. This makes it safe to call repeatedly without worrying about going past the end.


Example.
```zig
const source =
    \\ query {
    \\  users(id: 1) {
    \\   id
    \\  }
    \\ }
;

const Lexer = @import("graphql").lexer.Lexer;
var lexer = Lexer.init(source, .{});
while (try lexer.next()) |token| {
    if (token.kind == TokenKind.Eof) {
        break; // Reached EOF.
    }
    // Process token.
}
```

#### Bounded Tokenization

It is recommended to limit how far the lexer can scan. You can use the `tokenizeWithLimit()` function or pass a `limit` in the options struct into the Lexer.


Example with `tokenizeWithLimit()`.
```zig
const graphql = @import("graphql");

const tokens = try graphql.lexer.tokenizeWithLimit(allocator, source, 10); // Only scan up to 10 tokens.
defer allocator.free(tokens);
```


Example with options struct.
```zig
var lexer = Lexer.init(source, .{ .limit = 10 }); // Only scan up to 10 tokens.

const tokens = try lexer.tokenize(allocator);
defer allocator.free(tokens);
```

### Parser

The `Parser` converts GraphQL text into a structured AST, which you can use for analyzing or transforming GraphQL operations. It exposes several methods for parsing and token navigation. You should only pay attention to `init()` and `parse()` for basic usage.


Since the AST nodes contain slices, you will need to manage their memory appropriately to avoid leaks.
Using an `ArenaAllocator` is recommended for simpler memory management. You can just defer the arena's memory to clean up everything at once.

#### Basic Parsing

The simplest way to use the Parser is to parse an entire GraphQL document at once. The `parse()` method returns a structured AST that you can traverse and analyze.

Example.
```zig
const source =
    \\ query {
    \\  users(id: 1) {
    \\   id
    \\  }
    \\ }
;
defer allocator.deinit(); // Clean up all allocated memory.

const Parser = @import("graphql").parser.Parser;
var parser = Parser.init(allocator, source, .{});
const doc = try parser.parse();

for (doc.definitions) |definition| {
    // Process each definition in the document.
}
```

For basic parsing, the library exposes a `parse()` function, which provides a convenient way to parse GraphQL documents without manually creating a parser instance.


Example.
```zig
const graphql = @import("graphql");

const doc = try graphql.parser.parse(allocator, source);
```

#### Bounded Parsing

Similar to the lexer, it is recommended to limit how far the parser can process tokens. You can use the `parseWithLimit()` function or pass a `limit` in the options struct.

Example with `parseWithLimit()`.
```zig
const doc = try graphql.parser.parseWithLimit(allocator, source, 100);
// Will throw LimitReached error if we hit the limit.
```

Example with options struct.
```zig
var parser = Parser.init(allocator, source, .{ .limit = 100 }); // Only process up to 100 tokens.

const doc = try parser.parse();
// Will throw LimitReached error if we hit the limit.
```

## Benchmarks

To run the benchmarks

```bash
zig build bench
```

The benchmark suite is always compiled with `ReleaseFast` regardless of any `-Doptimize` flag.

### Validator

TODO: TODO

#### Validation Rules

The validator implements the following GraphQL validation rules:

| Rule | Description | Status |
|------|-------------|--------|
| **Executable Definition Rules** | | |
| ExecutableDefinitionsRule | A GraphQL document is only valid for execution if all definitions are either operation or fragment definitions. | TODO |
| FieldsOnCorrectTypeRule | Fields selected on an object, interface, or union must be defined on that type. | TODO |
| FragmentsOnCompositeTypesRule | Fragments can only be spread into a composite type (object, interface, or union). | TODO |
| KnownArgumentNamesRule | All arguments provided to a field or directive must be defined by that field or directive. | TODO |
| KnownDirectivesRule | All directives used must be defined in the schema. | TODO |
| DirectivesAreInValidLocationsRule | Directives must only be used in locations they are declared to support. | TODO |
| KnownFragmentNamesRule | All fragment spreads must refer to fragments defined in the same document. | TODO |
| KnownTypeNamesRule | All referenced types (in variable definitions and fragment conditions) must be defined in the schema. | TODO |
| LoneAnonymousOperationRule | A document containing an anonymous operation must contain only that one operation. | TODO |
| NoFragmentCyclesRule | Fragments must not form cycles via fragment spreads. | TODO |
| NoUndefinedVariablesRule | All variables used in an operation must be defined by that operation. | TODO |
| NoUnusedFragmentsRule | All fragment definitions must be used within operations or other used fragments. | TODO |
| NoUnusedVariablesRule | All variables defined by an operation must be used in that operation. | TODO |
| OverlappingFieldsCanBeMergedRule | Fields selected in the same scope must have compatible types and arguments. | TODO |
| PossibleFragmentSpreadsRule | Fragment spreads must be on types that are possible given the parent type. | TODO |
| ProvidedRequiredArgumentsRule | All required arguments on fields and directives must be provided. | TODO |
| ScalarLeafsRule | Leaf fields (fields without sub-selections) must be scalar or enum types. | TODO |
| SingleFieldSubscriptionsRule | Subscription operations must contain exactly one root field. | TODO |
| UniqueArgumentNamesRule | Argument names must be unique within a field or directive call. | TODO |
| UniqueDirectivesPerLocationRule | Directives that are not repeatable must appear at most once per location. | TODO |
| UniqueFragmentNamesRule | Fragment names must be unique within a document. | TODO |
| UniqueInputFieldNamesRule | Input field names must be unique within an input object value. | TODO |
| UniqueOperationNamesRule | Operation names must be unique within a document. | TODO |
| UniqueVariableNamesRule | Variable names must be unique within an operation. | TODO |
| ValuesOfCorrectTypeRule | Input values must be compatible with their expected input types. | TODO |
| VariablesAreInputTypesRule | Variables must be of input types (scalar, enum, or input object). | TODO |
| VariablesInAllowedPositionRule | Variables must be used in locations compatible with their defined types. | TODO |
| **Schema Definition Rules** | | |
| LoneSchemaDefinitionRule | A document must contain at most one schema definition. | TODO |
| UniqueOperationTypesRule | There must be at most one of each operation type (query, mutation, subscription) in a schema definition. | TODO |
| UniqueTypeNamesRule | Type names must be unique within a schema. | TODO |
| UniqueEnumValueNamesRule | Enum value names must be unique within an enum type definition. | TODO |
| UniqueFieldDefinitionNamesRule | Field names must be unique within an object, interface, or input object type definition. | TODO |
| UniqueArgumentDefinitionNamesRule | Argument names must be unique within a field or directive definition. | TODO |
| UniqueDirectiveNamesRule | Directive names must be unique within the schema. | TODO |
| PossibleTypeExtensionsRule | Type extensions must extend a type that exists in the schema. | TODO |
| ReservedNamesRule | Names starting with `__` are reserved by the GraphQL introspection system. | TODO |
| **Recommended Security Rules** | | |
| DeeplyNestedTypeRule | Fragment definitions must not contain excessive nesting to prevent abuse. | TODO |
| MaxIntrospectionDepthRule | Introspection queries must not exceed a depth limit to prevent DoS attacks. | TODO |

## TODO

### Features

#### Validator

Create a graphql validator for validating graphql documents.
This is a work in progress.
Help wanted if you happen to be reading this.

### Improvements

#### ArrayList vs Slices.
Find out if the types should be changed from slices to `ArrayList`.
Returning slices may involve unnecessary allocations, which could impact performance.
`toOwnedSlice` tries to remap the original list and if it cant then it memcopies.
[toOwnedSlice docs](https://ziglang.org/documentation/master/std/#std.array_list.ArrayListAlignedUnmanaged.toOwnedSlice).

An `ArrayList` can be appended to. But, for our use case the document and nodes were parsed and dont need further appending. Slice seems more suitable, but revisit this later.

#### Custom Deinit Methods
The user has to manage the memory of the document. It would be nice to have a deinit method so they dont have to recursively free the memory. We can add a deinit method on the document to do this for the user.
The allocator can be passed in. Using an arena allocator, also provides an elegant way to free the memory after use without having to recursively free the memory.

#### Testing
Research best practices for organizing and executing tests in Zig. Currently, unit tests are embedded in the source files, which seems to align with Zig conventions but may not scale well as the project gets bigger.

## Inspiration And Resources
This project was inspired by a mix of curiosity for [zig](https://ziglang.org/), and a desire to see its use in web services.

I also drew inspiration from existing GraphQL libraries like [graphql-js](https://github.com/graphql/graphql-js) ([MIT](https://github.com/apollographql/apollo-rs/blob/main/LICENSE-MIT)) and [apollo-rs](https://github.com/apollographql/apollo-rs) ([MIT](https://github.com/apollographql/apollo-rs/blob/main/LICENSE-MIT)). They provided a great reference for how a GraphQL parser should behave.

This project follows the [October 2021 GraphQL specification](https://spec.graphql.org/October2021) for its grammar and parsing rules.