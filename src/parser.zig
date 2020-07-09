usingnamespace @cImport({
    @cInclude("tree_sitter/api.h");
});
const std = @import("std");

extern fn tree_sitter_json() ?*TSLanguage;
extern fn tree_sitter_markdown() ?*TSLanguage;

pub fn main() !void {
    try testParser();
}

pub const RenderStyle = union(enum) {
    control: void,
    text: union(enum) {
        bolditalic: void,
        bold: void,
        italic: void,
        normal: void,
    },
    heading: struct {},
    code: void,
    inlineCode: void,
    codeLanguage: void,
    showInvisibles: enum { all, inlin_ }, // zig has too many keywords
    errort: void,
};

const Class = struct {
    document: bool = false,
    paragraph: bool = false,
    emphasis: bool = false,
    strong_emphasis: bool = false,
    text: bool = false,
    atx_heading: bool = false,
    atx_heading_marker: bool = false,
    heading_content: bool = false,
    hard_line_break: bool = false,
    soft_line_break: bool = false,
    code_fence_content: bool = false,
    fenced_code_block: bool = false,
    info_string: bool = false,
    line_break: bool = false,
    table: bool = false,
    table_cell: bool = false,
    table_data_row: bool = false,
    table_delimiter_row: bool = false,
    table_column_alignment: bool = false,
    table_header_row: bool = false,
    block_quote: bool = false,
    tight_list: bool = false,
    list_item: bool = false,
    list_marker: bool = false,
    image: bool = false,
    image_description: bool = false,
    link: bool = false,
    link_text: bool = false,
    link_destination: bool = false,
    html_open_tag: bool = false,
    html_tag_name: bool = false,
    html_close_tag: bool = false,
    backslash_escape: bool = false, // this is set for both \*, we only want it on the \ itself but want the * to be text. This means, we need to do some manual work so the \ itself is highlighted but the * is not, and make sure it works for other things like \\ where the second \ needs to be plain text. I think looking at the node structure would make that clear (hopefully), so this struct might need a tiny bit of node structural information (eg, this is the second character in this node)
    strikethrough: bool = false,
    code_span: bool = false,
    thematic_break: bool = false, // should get represented by each character taking 1/3 of the page width and drawing a horizontal line
    indented_code_block: bool = false, // the indent before this should be show invisibles. unfortunately, tree-sitter doesn't output anything for that.
    html_atrribute: bool = false, // [sic]
    html_attribute_key: bool = false,
    html_attribute_value: bool = false,
    html_block: bool = false,
    loose_list: bool = false,
    ERROR: bool = false,
    IS_CHAR_0: bool,

    pub fn renderStyle(cs: Class) RenderStyle {
        if (cs.ERROR) return .errort;

        if (cs.soft_line_break) return .{ .showInvisibles = .all };
        if (cs.hard_line_break) return .{ .showInvisibles = .inlin_ };
        if (cs.backslash_escape and !cs.IS_CHAR_0) return .{ .text = .normal };
        if (cs.text) {
            if (cs.indented_code_block) return .code;
            if (cs.fenced_code_block and cs.code_fence_content) return .code;
            if (cs.code_span) return .inlineCode;
            if (cs.info_string) return .codeLanguage;

            if (cs.atx_heading) return .{ .heading = .{} };
            if (cs.strong_emphasis and cs.emphasis)
                return .{ .text = .bolditalic };
            if (cs.strong_emphasis) return .{ .text = .bold };
            if (cs.emphasis) return .{ .text = .italic };
            return .{ .text = .normal };
        }
        return .{ .showInvisibles = .inlin_ };
    }
    pub fn format(
        classesStruct: Class,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: var,
    ) !void {
        inline for (@typeInfo(Class).Struct.fields) |field| {
            if (@field(classesStruct, field.name)) {
                try std.fmt.format(out_stream, ".{}", .{field.name});
            }
        }
    }
};

pub const Position = struct { from: u64, to: u64 };
pub const Node = struct {
    node: TSNode,
    fn wrap(rawNode: TSNode) Node {
        return .{ .node = rawNode };
    }
    pub fn position(n: Node) Position {
        return .{
            .from = ts_node_start_byte(n.node),
            .to = ts_node_end_byte(n.node),
        };
    }
    fn createClassesStructInternal(n: Node, classesStruct: *Class) void {
        var className = n.class();
        inline for (@typeInfo(Class).Struct.fields) |field| {
            if (field.name[0] == '_') continue;
            if (std.mem.eql(u8, field.name, std.mem.span(className))) {
                @field(classesStruct, field.name) = true;
                break;
            }
        } else if (n.named()) {
            std.debug.warn("Unsupported class name: {s}\n", .{className});
        }
        if (n.parent()) |p| p.createClassesStructInternal(classesStruct);
    }
    pub fn createClassesStruct(n: Node, cidx: u64) Class {
        var classes: Class = .{
            .IS_CHAR_0 = @intCast(u32, cidx) == ts_node_start_byte(n.node),
        };
        n.createClassesStructInternal(&classes);
        return classes;
    }
    pub fn class(n: Node) []const u8 {
        return std.mem.span(ts_node_type(n.node));
    }
    pub fn named(n: Node) bool {
        return ts_node_is_named(n.node);
    }
    pub fn printClasses(
        n: Node,
        res: *std.ArrayList(u8),
    ) std.mem.Allocator.Error!void {
        if (n.parent()) |up| {
            try up.printClasses(res);
            try res.appendSlice(".");
        }
        var isNamed = n.named();
        if (!isNamed)
            try res.appendSlice("<");
        try res.appendSlice(n.class());
        if (!isNamed)
            try res.appendSlice(">");
    }
    pub fn firstChild(n: Node) ?Node {
        const result = ts_node_parent(n.node);
        if (ts_node_is_null(result)) return null;
        return Node.wrap(result);
    }
    pub fn nextSibling(n: Node) ?Node {
        const result = ts_node_parent(n.node);
        if (ts_node_is_null(result)) return null;
        return Node.wrap(result);
    }
    pub fn parent(n: Node) ?Node {
        const result = ts_node_parent(n.node);
        if (ts_node_is_null(result)) return null;
        return Node.wrap(result);
    }
    pub fn next(n: Node) ?Node {
        if (n.firstChild()) |d| return d;
        var curr = n;
        while (true) {
            if (n.nextSibling()) |nxts| return nxts;
            if (curr.parent()) |nv|
                curr = nv
            else
                return null;
        }
        unreachable;
    }
};

pub const TreeCursor = struct {
    cursor: TSTreeCursor,
    pub fn init(initialNode: Node) TreeCursor {
        return .{
            .cursor = ts_tree_cursor_new(initialNode.node),
        };
    }
    pub fn deinit(tc: *TreeCursor) void {
        ts_tree_cursor_delete(&tc.cursor);
    }
    fn goFirstChild(tc: *TreeCursor) bool {
        return ts_tree_cursor_goto_first_child(&tc.cursor);
    }
    fn goNextSibling(tc: *TreeCursor) bool {
        return ts_tree_cursor_goto_next_sibling(&tc.cursor);
    }
    fn goParent(tc: *TreeCursor) bool {
        return ts_tree_cursor_goto_parent(&tc.cursor);
    }
    fn advance(tc: *TreeCursor) bool {
        // check if there are any children
        if (tc.goFirstChild()) return true;
        // go up and right
        while (!tc.goNextSibling()) {
            if (!tc.goParent()) return false;
        }
        return true;
    }

    fn node(tc: *TreeCursor) Node {
        return Node.wrap(ts_tree_cursor_current_node(&tc.cursor));
    }
    fn fieldName(tc: *TreeCursor) []u8 {
        return ts_tree_cursor_current_field_name(&tc.cursor);
    }
    fn fieldID(tc: *TreeCursor) TSFieldId {
        return ts_tree_cursor_current_field_id(&tc.cursor);
    }
};

pub fn getNodeAtPosition(char: u64, cursor: *TreeCursor) Node {
    var bestMatch: Node = cursor.node();
    while (char < cursor.node().position().from) {
        std.debug.assert(cursor.goParent() == true);
    }
    while (char >= cursor.node().position().from) {
        var currentPosition = cursor.node().position();
        if (char >= currentPosition.from and char < currentPosition.to) {
            bestMatch = cursor.node();
        }
        if (!cursor.advance()) break;
    }
    return bestMatch;
}

/// don't use this
pub const RowCol = struct {
    row: u64,
    col: u64,
    pub fn format(
        cp: RowCol,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: var,
    ) !void {
        try std.fmt.format(out_stream, "{}:{}", .{ cp.row + 1, cp.col + 1 });
    }
};
pub const Point = struct {
    row: u64,
    col: u64,
    byte: u64,
    fn toPoint(cp: Point) TSPoint {
        return .{ .row = @intCast(u32, cp.row), .column = @intCast(u32, cp.col) };
    }
    fn fromPoint(point: TSPoint, byte: u32) Point {
        return .{ .row = point.row, .col = point.column, .byte = byte };
    }
    pub fn format(
        cp: Point,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: var,
    ) !void {
        try std.fmt.format(out_stream, "{}:{}", .{ cp.row + 1, cp.col + 1 });
    }
};

pub const Tree = struct {
    parser: *TSParser,
    tree: *TSTree,
    locked: bool,

    /// source code must exist for Tree's lifetime.
    pub fn init(sourceCode: []const u8) !Tree {
        var parser = ts_parser_new().?;
        errdefer ts_parser_delete(parser);
        if (!ts_parser_set_language(parser, tree_sitter_markdown()))
            return error.IncompatibleLanguageVersion;

        var tree = ts_parser_parse_string(parser, null, sourceCode.ptr, @intCast(u32, sourceCode.len)).?;
        errdefer ts_tree_delete(tree);

        return Tree{
            .parser = parser,
            .tree = tree,
            .locked = false,
        };
    }
    pub fn deinit(ts: *Tree) void {
        ts_tree_delete(ts.tree);
        ts_parser_delete(ts.parser);
    }
    pub fn lock(ts: *Tree) void {
        if (ts.locked) unreachable;
        ts.locked = true;
    }
    pub fn unlock(ts: *Tree) void {
        if (!ts.locked) unreachable;
        ts.locked = false;
    }
    pub fn reparseFn(ts: *Tree, data: var, comptime read: fn (
        data: @TypeOf(data),
        pos: Point,
    ) []const u8) void {
        const Data = @TypeOf(data);
        // write .length is return.len and return return.ptr
        var tsinput: TSInput = .{
            .payload = @intToPtr(*c_void, @ptrToInt(&data)),
            .read = struct {
                fn read(data_: ?*c_void, byte: u32, point: TSPoint, outLen: [*c]u32) callconv(.C) [*c]const u8 {
                    const result = read(@intToPtr(*const Data, @ptrToInt(data_)).*, Point.fromPoint(point, byte));
                    outLen.* = @intCast(u32, result.len);
                    return result.ptr;
                }
            }.read,
            .encoding = .TSInputEncodingUTF8,
        };

        var newTree = ts_parser_parse(ts.parser, ts.tree, tsinput).?;
        ts_tree_delete(ts.tree);
        ts.tree = newTree;
    }
    pub fn reparse(ts: *Tree, sourceCode: []const u8) void {
        // not sure if it is necessary to reassign tree
        // this line crashes sometimes at some character counts:
        var newTree = ts_parser_parse_string(
            ts.parser,
            ts.tree,
            sourceCode.ptr,
            @intCast(u32, sourceCode.len),
        ).?;
        ts_tree_delete(ts.tree);
        ts.tree = newTree;
    }
    pub fn root(ts: *Tree) Node {
        return Node.wrap(ts_tree_root_node(ts.tree));
    }

    /// Update source text FIRST!
    /// Calling this function may invalidate any existing Node instances. Do not store node instances across frames.
    /// because tree-sitter, caller must calculate row and column of text. how do you calculate this when you don't know the start row? idk, glhf.
    pub fn edit(
        ts: *Tree,
        start: Point,
        oldEnd: Point,
        newEnd: Point,
    ) void {
        if (ts.locked) unreachable;
        ts_tree_edit(ts.tree, &TSInputEdit{
            .start_byte = @intCast(u32, start.byte),
            .old_end_byte = @intCast(u32, oldEnd.byte),
            .new_end_byte = @intCast(u32, newEnd.byte),
            .start_point = start.toPoint(),
            .old_end_point = oldEnd.toPoint(),
            .new_end_point = newEnd.toPoint(),
        });
    }
};
