const std = @import("std");
const ast = @import("../../graphql.zig").ast;
const DiagnosticList = @import("../validator.zig").DiagnosticList;
const ExecutableDocument = @import("../validator.zig").ExecutableDocument;
const OperationValidationContext = @import("../validator.zig").OperationValidationContext;
const Schema = @import("../validator.zig").Schema;
const validateField = @import("./field.zig").validateField;
const validateFragmentSpread = @import("./fragment.zig").validateFragmentSpread;
const validateInlineFragment = @import("./fragment.zig").validateInlineFragment;

pub fn validateSelectionSet(
    diagnostics: *DiagnosticList,
    exec_doc: *const ExecutableDocument,
    against_type: ?ast.NamedTypeNode,
    selection_set: ast.SelectionSetNode,
    context: *OperationValidationContext,
) std.mem.Allocator.Error!void {
    for (selection_set.selections) |selection| {
        switch (selection) {
            .Field => |field| try validateField(
                diagnostics,
                exec_doc,
                against_type,
                field,
                context,
            ),
            .FragmentSpread => |spread| try validateFragmentSpread(
                diagnostics,
                exec_doc,
                against_type,
                spread,
                context,
            ),
            .InlineFragment => |inline_frag| try validateInlineFragment(
                diagnostics,
                exec_doc,
                against_type,
                inline_frag,
                context,
            ),
        }
    }
}

// Field Selection Merging
// https://spec.graphql.org/draft/#sec-Field-Selection-Merging
//
// The implementation follows the XING algorithm described in:
// https://tech.new-work.se/graphql-overlapping-fields-can-be-merged-fast-ea6e92e0a01
// (also referenced in apollo-rs selection.rs)
//
// The cache below (FieldsInSetCanMerge.cache) implements the OnceBool / MergedFieldSet
// optimization from apollo-rs: each field selection slice is validated at most once per pass.
// This is safe because all slices live in the arena for the duration of the validation pass,
// so slice pointer identity is a stable and correct cache key.

// The field depth in the field merging validation matches the nesting level in the resulting
// data. It makes sense to use the same limit as serde_json.
const FIELD_DEPTH_LIMIT: usize = 128;

// mirror rs TypeAttributeCoordinate, trimmed.
const FieldCoordinate = struct {
    parent_type_name: ?[]const u8,
    field_name: []const u8,
};

/// Represents a field selected against a parent type.
const FieldSelection = struct {
    /// Cached hash: field selections are always hashed at least once, and often multiple times.
    /// Hashing Node<Field> is not that cheap, so we do it eagerly.
    hash: u64,
    /// The type of the selection set this field selection is part of.
    parent_type: ?ast.NamedTypeNode,
    /// Pointer into the AST, valid for the lifetime of the source document.
    field: *const ast.FieldNode,
    /// Schema field definition resolved at expansion time.  Null when the
    /// field is not found in the schema (another validator raises the error).
    field_def: ?ast.FieldDefinitionNode,

    fn responseKey(self: FieldSelection) []const u8 {
        return if (self.field.alias) |a| a.value else self.field.name.value;
    }

    fn coordinate(self: FieldSelection) FieldCoordinate {
        return .{
            .parent_type_name = if (self.parent_type) |pt| pt.name.value else null,
            .field_name = self.field.name.value,
        };
    }
};

const SelectionQueueItem = struct {
    selection_set: ast.SelectionSetNode,
    parent_type: ?ast.NamedTypeNode,
};

fn isCompositeDef(type_def: ast.TypeDefinitionNode) bool {
    return switch (type_def) {
        .ObjectTypeDefinition, .InterfaceTypeDefinition, .UnionTypeDefinition => true,
        else => false,
    };
}

fn isLeafDef(type_def: ast.TypeDefinitionNode) bool {
    return switch (type_def) {
        .ScalarTypeDefinition, .EnumTypeDefinition => true,
        else => false,
    };
}

fn isConcreteObjectDef(type_def: ast.TypeDefinitionNode) bool {
    return type_def == .ObjectTypeDefinition;
}

/// A temporary index for argument lookups by name.
/// Uses a HashMap when len > 20, linear scan otherwise.
const ArgumentLookup = union(enum) {
    map: std.StringHashMap(*const ast.ArgumentNode),
    list: []const ast.ArgumentNode,

    fn init(allocator: std.mem.Allocator, args: []const ast.ArgumentNode) std.mem.Allocator.Error!ArgumentLookup {
        if (args.len > 20) {
            var map = std.StringHashMap(*const ast.ArgumentNode).init(allocator);
            try map.ensureTotalCapacity(@intCast(args.len));
            for (args) |*arg| {
                map.putAssumeCapacity(arg.name.value, arg);
            }
            return .{ .map = map };
        }
        return .{ .list = args };
    }

    fn deinit(self: *ArgumentLookup) void {
        switch (self.*) {
            .map => |*m| m.deinit(),
            .list => {},
        }
    }

    fn byName(self: *const ArgumentLookup, name: []const u8) ?*const ast.ArgumentNode {
        return switch (self.*) {
            .map => |m| m.get(name),
            .list => |l| for (l) |*arg| {
                if (std.mem.eql(u8, arg.name.value, name)) break arg;
            } else null,
        };
    }
};

/// Check if two field selections from the overlapping types are the same, so the fields can be merged.
fn sameNameAndArguments(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
    field_a: FieldSelection,
    field_b: FieldSelection,
) !bool {
    // 2bi. fieldA and fieldB must have identical field names.
    if (!std.mem.eql(u8, field_a.field.name.value, field_b.field.name.value)) {
        try diagnostics.push(.ConflictingFieldName);
        return false;
    }

    const args_a = field_a.field.arguments orelse &[_]ast.ArgumentNode{};
    const args_b = field_b.field.arguments orelse &[_]ast.ArgumentNode{};

    // 2bii. fieldA and fieldB must have identical sets of arguments.
    // rs ArgumentLookup: use HashMap for >20 args, linear scan otherwise.
    var lookup_b = try ArgumentLookup.init(allocator, args_b);
    defer lookup_b.deinit();
    for (args_a) |arg_a| {
        const other_arg = lookup_b.byName(arg_a.name.value) orelse {
            try diagnostics.push(.ConflictingFieldArgument);
            return false;
        };
        if (!sameValue(arg_a.value, other_arg.value)) {
            try diagnostics.push(.ConflictingFieldArgument);
            return false;
        }
    }
    // Reverse pass: catch args in b that are absent from a (guards against
    // duplicate arg names in a making the length check pass spuriously).
    var lookup_a = try ArgumentLookup.init(allocator, args_a);
    defer lookup_a.deinit();
    for (args_b) |arg_b| {
        _ = lookup_a.byName(arg_b.name.value) orelse {
            try diagnostics.push(.ConflictingFieldArgument);
            return false;
        };
    }
    return true;
}

/// Expand one or more selection sets to a list of all fields selected.
// walk over one or more selection sets, collecting every concrete field.
// Fragment spreads are deduped so repeated spreads and cycles don't reexpand.
// Inline fragments without a type condition inherit the parent type.
fn expandSelections(
    allocator: std.mem.Allocator,
    exec_doc: *const ExecutableDocument,
    schema: ?*const Schema,
    initial_seeds: []const SelectionQueueItem,
) !std.ArrayList(FieldSelection) {
    var result = std.ArrayList(FieldSelection).init(allocator);

    var seen_fragments = std.StringHashMap(void).init(allocator);
    defer seen_fragments.deinit();

    var queue = std.ArrayList(SelectionQueueItem).init(allocator);
    defer queue.deinit();

    for (initial_seeds) |seed| try queue.append(seed);

    while (queue.items.len > 0) {
        // NOTE:
        // rs would use `VecDeque` (pop_front, O(1) BFS ringer buffer)
        // were using pop() (zig has std.fifo.LinearFifo(.Dynamic), which should match `VecDeque`.)
        // should be (LIFO/DFS, O(1)) because both consumers sort the result before use
        const item = queue.pop() orelse break; // TODO: review if well have a bug breaking if this returns null.
        // iterate by pointer so that |*field| below points into the stable
        // slice memory (the AST), not into a transient stack copy.
        for (item.selection_set.selections) |*selection| {
            switch (selection.*) {
                .Field => |*field| {
                    const field_def: ?ast.FieldDefinitionNode = blk: {
                        const s = schema orelse break :blk null;
                        const pt = item.parent_type orelse break :blk null;
                        break :blk switch (s.typeField(pt.name.value, field.name.value)) {
                            .found => |def| def,
                            else => null,
                        };
                    };
                    const sel_hash = blk: {
                        var h = std.hash.Wyhash.init(0);
                        h.update(if (item.parent_type) |pt| pt.name.value else "");
                        h.update("\x00");
                        h.update(field.name.value);
                        h.update("\x00");
                        h.update(if (field.alias) |a| a.value else "");
                        const ptr_int = @intFromPtr(field);
                        h.update(std.mem.asBytes(&ptr_int));
                        break :blk h.final();
                    };
                    try result.append(FieldSelection{
                        .hash = sel_hash,
                        .parent_type = item.parent_type,
                        .field = field,
                        .field_def = field_def,
                    });
                },
                .FragmentSpread => |spread| {
                    const gop = try seen_fragments.getOrPut(spread.name.value);
                    if (gop.found_existing) continue;
                    const frag = exec_doc.getFragment(spread.name.value) orelse continue;
                    try queue.append(.{
                        .selection_set = frag.selection_set,
                        .parent_type = frag.type_condition,
                    });
                },
                .InlineFragment => |inline_frag| {
                    const frag_type: ?ast.NamedTypeNode =
                        if (inline_frag.type_condition) |tc| tc else item.parent_type;
                    try queue.append(.{
                        .selection_set = inline_frag.selection_set,
                        .parent_type = frag_type,
                    });
                },
            }
        }
    }

    return result;
}

/// Compare two input values, with two special cases for objects: assuming no duplicate keys,
/// and order independence.
fn sameValue(left: ast.ValueNode, right: ast.ValueNode) bool {
    switch (left) {
        .Null => return right == .Null,
        .Boolean => |l| return right == .Boolean and right.Boolean.value == l.value,
        .Int => |l| return right == .Int and std.mem.eql(u8, right.Int.value, l.value),
        .Float => |l| return right == .Float and std.mem.eql(u8, right.Float.value, l.value),
        .String => |l| return right == .String and std.mem.eql(u8, right.String.value, l.value),
        .Enum => |l| return right == .Enum and std.mem.eql(u8, right.Enum.value, l.value),
        .Variable => |l| return right == .Variable and
            std.mem.eql(u8, right.Variable.name.value, l.name.value),
        .List => |l| {
            if (right != .List) return false;
            const r = right.List;
            if (l.values.len != r.values.len) return false;
            for (l.values, r.values) |lv, rv| {
                if (!sameValue(lv, rv)) return false;
            }
            return true;
        },
        .Object => |l| {
            if (right != .Object) return false;
            const r = right.Object;
            if (l.fields.len != r.fields.len) return false;
            // This check could miss out on keys that exist in `right`, but not in `left`, if `left` contains duplicate keys.
            // We assume that that doesn't happen. GraphQL does not support duplicate keys and
            // that is checked elsewhere in validation.
            for (l.fields) |lf| {
                const found = blk: for (r.fields) |rf| {
                    if (std.mem.eql(u8, lf.name.value, rf.name.value)) {
                        break :blk sameValue(lf.value, rf.value);
                    }
                } else false;
                if (!found) return false;
            }
            return true;
        },
    }
}

fn sameOutputTypeShape(
    schema: *const Schema,
    type_a: *const ast.TypeNode,
    type_b: *const ast.TypeNode,
) bool {
    switch (type_a.*) {
        .NonNullType => |nn_a| {
            if (type_b.* != .NonNullType) return false;
            return sameOutputTypeShape(schema, nn_a.type, type_b.NonNullType.type);
        },
        .ListType => |list_a| {
            if (type_b.* != .ListType) return false;
            return sameOutputTypeShape(schema, list_a.type, type_b.ListType.type);
        },
        .NamedType => |named_a| {
            if (type_b.* != .NamedType) return false;
            const named_b = type_b.NamedType;
            const def_a = schema.type_definitions.get(named_a.name.value) orelse return true;
            const def_b = schema.type_definitions.get(named_b.name.value) orelse return true;
            // Step 5: if either is Scalar or Enum they must be the same type
            if (isLeafDef(def_a) or isLeafDef(def_b)) {
                return std.mem.eql(u8, named_a.name.value, named_b.name.value);
            }
            // Step 6: both composite → OK; catch all (InputObject etc.) → mismatch
            if (isCompositeDef(def_a) and isCompositeDef(def_b)) return true;
            return false;
        },
    }
}

fn fieldSelectionLessThan(_: void, a: FieldSelection, b: FieldSelection) bool {
    const pt_a = if (a.parent_type) |pt| pt.name.value else "";
    const pt_b = if (b.parent_type) |pt| pt.name.value else "";
    const cmp = std.mem.order(u8, pt_a, pt_b);
    if (cmp != .eq) return cmp == .lt;
    const name_cmp = std.mem.order(u8, a.field.name.value, b.field.name.value);
    if (name_cmp != .eq) return name_cmp == .lt;
    return @intFromPtr(a.field) < @intFromPtr(b.field);
}

/// Returns a sorted duplicate of `selections` using `self.allocator`.
/// The caller owns the returned slice, when using an arena allocator the
/// arena frees it automatically.
fn sortFieldSelections(
    allocator: std.mem.Allocator,
    selections: []const FieldSelection,
) ![]FieldSelection {
    const sorted = try allocator.dupe(FieldSelection, selections);
    std.sort.pdq(FieldSelection, sorted, {}, fieldSelectionLessThan);
    return sorted;
}

/// HashMap context for `[]const FieldSelection` keys.
/// Keys MUST be in sorted order (use `sortFieldSelections` before lookup).
/// `eql` performs a deep content comparison, so hash collisions never cause
/// a false cache hit, unlike keying by a bare u64 digest.
const FieldSelectionContext = struct {
    pub fn hash(_: FieldSelectionContext, key: []const FieldSelection) u64 {
        var hasher = std.hash.Wyhash.init(0);
        for (key) |sel| {
            hasher.update(std.mem.asBytes(&sel.hash));
        }
        return hasher.final();
    }

    pub fn eql(_: FieldSelectionContext, a: []const FieldSelection, b: []const FieldSelection) bool {
        if (a.len != b.len) return false;
        for (a, b) |sa, sb| {
            const pt_a = if (sa.parent_type) |pt| pt.name.value else "";
            const pt_b = if (sb.parent_type) |pt| pt.name.value else "";
            if (!std.mem.eql(u8, pt_a, pt_b)) return false;
            if (!std.mem.eql(u8, sa.field.name.value, sb.field.name.value)) return false;
            const alias_a = if (sa.field.alias) |al| al.value else "";
            const alias_b = if (sb.field.alias) |al| al.value else "";
            if (!std.mem.eql(u8, alias_a, alias_b)) return false;
            if (sa.field != sb.field) return false;
        }
        return true;
    }
};

/// OnceBool equivalent: tracks which validation passes have already run for a given slice.
/// Also caches the by response key grouping so both validation passes share one allocation.
const CacheEntry = struct {
    response_shape: bool = false,
    common_parents: bool = false,
    /// Computed on first use; pointer is arena stable so it survives cache rehashes.
    by_response_key: ?*std.StringArrayHashMap(std.ArrayList(FieldSelection)) = null,
};

/// Implements the `FieldsInSetCanMerge()` validation.
/// https://spec.graphql.org/draft/#sec-Field-Selection-Merging
///
/// This uses the [validation algorithm described by XING][0] ([archived][1]), which
/// scales much better with larger selection sets that may have many overlapping fields,
/// and with widespread use of fragments.
///
/// [0]: https://tech.new-work.se/graphql-overlapping-fields-can-be-merged-fast-ea6e92e0a01
/// [1]: https://web.archive.org/web/20240208084612/https://tech.new-work.se/graphql-overlapping-fields-can-be-merged-fast-ea6e92e0a01
pub const FieldsInSetCanMerge = struct {
    allocator: std.mem.Allocator,
    schema: ?*const Schema,
    exec_doc: *const ExecutableDocument,
    /// Stores merged field sets.
    ///
    /// The value is an Rc because it needs to have an independent lifetime from `self`,
    /// so the cache can be updated while a field set is borrowed.
    cache: std.HashMap([]const FieldSelection, CacheEntry, FieldSelectionContext, std.hash_map.default_max_load_percentage),
    depth: usize,
    // so the effective limit does apply to field nesting levels in both cases.
    recursion_limit_exceeded: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        schema: ?*const Schema,
        exec_doc: *const ExecutableDocument,
    ) FieldsInSetCanMerge {
        return .{
            .allocator = allocator,
            .schema = schema,
            .exec_doc = exec_doc,
            .depth = 0,
            .recursion_limit_exceeded = false,
            .cache = std.HashMap([]const FieldSelection, CacheEntry, FieldSelectionContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    /// Expand the nested selection sets of every field in `fields` into a
    /// flat list of FieldSelections.  Uses each field's resolved definition
    /// to determine the nested parent type.
    fn expandNestedSelections(
        self: *FieldsInSetCanMerge,
        fields: []const FieldSelection,
    ) std.mem.Allocator.Error!std.ArrayList(FieldSelection) {
        var seeds = std.ArrayList(SelectionQueueItem).init(self.allocator);
        defer seeds.deinit();

        for (fields) |sel| {
            const sel_set = sel.field.selection_set orelse continue;
            const nested_type: ?ast.NamedTypeNode = blk: {
                const def = sel.field_def orelse break :blk null;
                break :blk def.type.innerNamedType();
            };
            try seeds.append(.{ .selection_set = sel_set, .parent_type = nested_type });
        }

        return expandSelections(self.allocator, self.exec_doc, self.schema, seeds.items);
    }

    /// Group a flat slice of FieldSelections by response key.
    /// The returned map and its ArrayList values are owned by `self.allocator`.
    fn groupByResponseKey(
        self: *FieldsInSetCanMerge,
        selections: []const FieldSelection,
    ) std.mem.Allocator.Error!std.StringArrayHashMap(std.ArrayList(FieldSelection)) {
        var map = std.StringArrayHashMap(std.ArrayList(FieldSelection)).init(self.allocator);
        for (selections) |sel| {
            const gop = try map.getOrPut(sel.responseKey());
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(FieldSelection).init(self.allocator);
            }
            try gop.value_ptr.*.append(sel);
        }
        return map;
    }

    /// No need to do this if this field set has been checked before
    pub fn sameResponseShapeByName(
        self: *FieldsInSetCanMerge,
        diagnostics: *DiagnosticList,
        selections: []const FieldSelection,
    ) std.mem.Allocator.Error!void {
        // Retrieve (or create) the cache entry and obtain a stable pointer to the
        // grouped map.  We close this block before recursing so that any cache
        // rehash triggered by nested calls cannot invalidate `gop.value_ptr`.
        // `map_ptr` itself is arena stable and remains valid regardless.
        var map_ptr: *std.StringArrayHashMap(std.ArrayList(FieldSelection)) = undefined;
        {
            const key = try sortFieldSelections(self.allocator, selections);
            const gop = try self.cache.getOrPut(key);
            if (!gop.found_existing) gop.value_ptr.* = CacheEntry{};
            if (gop.value_ptr.response_shape) return;
            gop.value_ptr.response_shape = true;

            if (gop.value_ptr.by_response_key == null) {
                const p = try self.allocator.create(std.StringArrayHashMap(std.ArrayList(FieldSelection)));
                p.* = try self.groupByResponseKey(selections);
                gop.value_ptr.by_response_key = p;
            }
            map_ptr = gop.value_ptr.by_response_key.?;
        }

        for (map_ptr.values()) |group| {
            // Type shape comparison: only meaningful when 2+ fields share a response key.
            if (group.items.len >= 2) {
                // Find the first group member with a known field_def to use as the
                // comparison anchor.  Pinning to items[0] silently skips the whole
                // group when that entry has no definition.
                var anchor_idx: ?usize = null;
                for (group.items, 0..) |item, i| {
                    if (item.field_def != null) {
                        anchor_idx = i;
                        break;
                    }
                }
                if (anchor_idx) |ai| {
                    const field_a = group.items[ai];
                    for (group.items) |field_b| {
                        if (field_b.field == field_a.field) continue;
                        const def_b = field_b.field_def orelse continue;
                        const s = self.schema orelse continue;
                        if (!sameOutputTypeShape(s, field_a.field_def.?.type, def_b.type)) {
                            try diagnostics.push(.ConflictingFieldType);
                        }
                    }
                }
            }

            // Recurse into the merged nested selection sets of this group.
            // Must run even for single field groups to validate nested selections.
            var nested = try self.expandNestedSelections(group.items);
            defer nested.deinit();
            if (nested.items.len > 0) {
                self.depth += 1;
                defer self.depth -= 1;
                if (self.depth >= FIELD_DEPTH_LIMIT) {
                    self.recursion_limit_exceeded = true;
                    return;
                }
                try self.sameResponseShapeByName(diagnostics, nested.items);
            }
        }
    }

    /// Given a set of fields, do all the fields selecting from potentially overlapping types
    /// select from the same thing?
    ///
    /// This prevents selecting two different fields from the same type into the same name. That
    /// would be a contradiction because there would be no way to know which field takes precedence.
    /// Spec 5.3.2 , step 2: same for common parents.
    pub fn sameForCommonParentsByName(
        self: *FieldsInSetCanMerge,
        diagnostics: *DiagnosticList,
        selections: []const FieldSelection,
    ) std.mem.Allocator.Error!void {
        // Same pointer escape pattern as sameResponseShapeByName: close the cache
        // block before recursing.  If sameResponseShapeByName already ran on this
        // set, by_response_key is populated and we skip the groupByResponseKey call.
        var map_ptr: *std.StringArrayHashMap(std.ArrayList(FieldSelection)) = undefined;
        {
            const key = try sortFieldSelections(self.allocator, selections);
            const gop = try self.cache.getOrPut(key);
            if (!gop.found_existing) gop.value_ptr.* = CacheEntry{};
            if (gop.value_ptr.common_parents) return;
            gop.value_ptr.common_parents = true;

            if (gop.value_ptr.by_response_key == null) {
                const p = try self.allocator.create(std.StringArrayHashMap(std.ArrayList(FieldSelection)));
                p.* = try self.groupByResponseKey(selections);
                gop.value_ptr.by_response_key = p;
            }
            map_ptr = gop.value_ptr.by_response_key.?;
        }

        for (map_ptr.values()) |group| {
            // Partition into concrete (Object) parent types and abstract/unknown.
            var concrete = std.StringArrayHashMap(std.ArrayList(FieldSelection)).init(self.allocator);
            defer {
                for (concrete.values()) |*v| v.deinit();
                concrete.deinit();
            }
            var abstract = std.ArrayList(FieldSelection).init(self.allocator);
            defer abstract.deinit();

            for (group.items) |sel| {
                const pt = sel.parent_type orelse {
                    try abstract.append(sel);
                    continue;
                };
                const s = self.schema orelse continue;
                const def = s.type_definitions.get(pt.name.value) orelse continue;
                switch (def) {
                    .ObjectTypeDefinition => {
                        const gop = try concrete.getOrPut(pt.name.value);
                        if (!gop.found_existing) {
                            gop.value_ptr.* = std.ArrayList(FieldSelection).init(self.allocator);
                        }
                        try gop.value_ptr.*.append(sel);
                    },
                    .InterfaceTypeDefinition, .UnionTypeDefinition => {
                        try abstract.append(sel);
                    },
                    else => {}, // Scalar, Enum, InputObject → drop (matches Rust `_ => {}`)
                }
            }

            if (concrete.count() == 0) {
                // All fields come from abstract or unknown types; check them together.
                try self.checkCommonParentGroup(diagnostics, abstract.items);
            } else {
                // For each concrete object type, check that type's fields combined with all abstract fields.
                for (concrete.values()) |concrete_group| {
                    var combined = std.ArrayList(FieldSelection).init(self.allocator);
                    defer combined.deinit();
                    try combined.appendSlice(concrete_group.items);
                    try combined.appendSlice(abstract.items);
                    try self.checkCommonParentGroup(diagnostics, combined.items);
                }
            }
        }
    }

    /// rs same_for_common_parents_by_name inner loop , for a group of fields
    /// sharing a response key and a concrete (or all abstract) parent set: assert identical field name and arguments, then recurse.
    ///
    /// rs: "2bi. fieldA and fieldB must have identical field names.
    /// 2bii. fieldA and fieldB must have identical sets of arguments.
    /// The same arguments check is reflexive so we don't need to check  all combinations." (we check [0] against [1..])
    fn checkCommonParentGroup(
        self: *FieldsInSetCanMerge,
        diagnostics: *DiagnosticList,
        fields: []const FieldSelection,
    ) std.mem.Allocator.Error!void {
        // Name/arg check: only meaningful when 2+ fields share a response key.
        if (fields.len >= 2) {
            const field_a = fields[0];
            for (fields[1..]) |field_b| {
                _ = try sameNameAndArguments(self.allocator, diagnostics, field_a, field_b);
            }
        }

        // Recurse into merged nested selection sets.
        // Must run even for single field groups to validate nested selections.
        var nested = try self.expandNestedSelections(fields);
        defer nested.deinit();
        if (nested.items.len > 0) {
            self.depth += 1;
            defer self.depth -= 1;
            if (self.depth >= FIELD_DEPTH_LIMIT) {
                self.recursion_limit_exceeded = true;
                return;
            }
            try self.sameForCommonParentsByName(diagnostics, nested.items);
        }
    }

    /// Validates one operation's selection set against spec rule 5.3.2
    /// "Field Selection Merging".
    ///
    /// Mirrors Rust's `FieldsInSetCanMerge::validate_operation`. Called once
    /// per operation from the document loop in `validateWithSchema`
    /// (`validator.zig`), keeping this instance alive so the cache persists
    /// across operations.
    pub fn validateOperation(
        self: *FieldsInSetCanMerge,
        diagnostics: *DiagnosticList,
        alloc: std.mem.Allocator,
        selection_set: ast.SelectionSetNode,
        against_type: ?ast.NamedTypeNode,
    ) !void {
        // Reset per operation traversal state. The cache is intentionally NOT
        // reset — sharing it across operations is what avoids redundant
        // re validation of identical field sets (the whole point of keeping
        // this instance alive across the document loop).
        self.depth = 0;
        self.recursion_limit_exceeded = false;

        const seed = SelectionQueueItem{ .selection_set = selection_set, .parent_type = against_type };
        var selections = try expandSelections(alloc, self.exec_doc, self.schema, &.{seed});
        defer selections.deinit();

        try self.sameResponseShapeByName(diagnostics, selections.items);
        self.depth = 0;
        try self.sameForCommonParentsByName(diagnostics, selections.items);

        // Report the limit breach at the operation level, matching Rust's
        // validate_operation which checks recursion_limit after both passes.
        if (self.recursion_limit_exceeded) {
            try diagnostics.push(.RecursionError);
        }
    }
};
