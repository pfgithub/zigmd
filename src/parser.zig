const c = @import("./c.zig");
const std = @import("std");

extern fn tree_sitter_json() ?*c.TSLanguage;
extern fn tree_sitter_markdown() ?*c.TSLanguage;

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
    display: union(enum) {
        eolSpace: void,
    },
    errort: void,
};

const Class = struct {
    document: bool = false,
    paragraph: bool = false,
    emphasis: bool = false, // text && italic
    strong_emphasis: bool = false, // text && bold
    text: bool = false, // !text: control character, monospace
    atx_heading: bool = false, // text && heading
    atx_heading_marker: bool = false,
    heading_content: bool = false,
    hard_line_break: bool = false, // .display.eolSpace
    soft_line_break: bool = false, // .display.newline
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
    ERROR: bool = false,

    pub fn renderStyle(cs: Class) RenderStyle {
        if (cs.ERROR) return .errort;

        if (cs.soft_line_break) return .{ .showInvisibles = .all };
        if (cs.hard_line_break) return .{ .display = .eolSpace };
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
        context: var,
        comptime Errors: type,
        comptime output: fn (@TypeOf(context), []const u8) Errors!void,
    ) Errors!void {
        inline for (@typeInfo(Class).Struct.fields) |field| {
            if (@field(classesStruct, field.name)) {
                try std.fmt.format(context, Errors, output, ".{}", .{field.name});
            }
        }
    }
};

pub const Position = struct { from: u64, to: u64 };
pub const Node = struct {
    node: c.TSNode,
    fn wrap(rawNode: c.TSNode) Node {
        return .{ .node = rawNode };
    }
    pub fn position(n: Node) Position {
        return .{
            .from = c.ts_node_start_byte(n.node),
            .to = c.ts_node_end_byte(n.node),
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
        } else {
            std.debug.warn("Unsupported class name: {s}\n", .{className});
        }
        if (n.parent()) |p| p.createClassesStructInternal(classesStruct);
    }
    pub fn createClassesStruct(n: Node) Class {
        var classes: Class = .{};
        n.createClassesStructInternal(&classes);
        return classes;
    }
    pub fn class(n: Node) [*c]const u8 {
        return c.ts_node_type(n.node);
    }
    fn printClassesInternal(n: Node) void {
        if (n.parent()) |up| {
            up.printClassesInternal();
            std.debug.warn(".", .{});
        }
        std.debug.warn("{s}", .{n.class()});
    }
    pub fn printClasses(n: Node) void {
        n.printClassesInternal();
        std.debug.warn("\n", .{});
    }
    pub fn firstChild(n: Node) ?Node {
        const result = c.ts_node_parent(n.node);
        if (c.ts_node_is_null(result)) return null;
        return Node.wrap(result);
    }
    pub fn nextSibling(n: Node) ?Node {
        const result = c.ts_node_parent(n.node);
        if (c.ts_node_is_null(result)) return null;
        return Node.wrap(result);
    }
    pub fn parent(n: Node) ?Node {
        const result = c.ts_node_parent(n.node);
        if (c.ts_node_is_null(result)) return null;
        return Node.wrap(result);
    }
    pub fn format(
        n: Node,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        context: var,
        comptime Errors: type,
        comptime output: fn (@TypeOf(context), []const u8) Errors!void,
    ) Errors!void {
        var str = c.ts_node_string(n.node);
        defer c.free(str);
        return std.fmt.format(context, Errors, output, "[{}] {s}", .{ n.position(), str });
    }
};

pub const TreeCursor = struct {
    cursor: c.TSTreeCursor,
    pub fn init(initialNode: Node) TreeCursor {
        return .{
            .cursor = c.ts_tree_cursor_new(initialNode.node),
        };
    }
    pub fn deinit(tc: *TreeCursor) void {
        c.ts_tree_cursor_delete(&tc.cursor);
    }
    fn goFirstChild(tc: *TreeCursor) bool {
        return c.ts_tree_cursor_goto_first_child(&tc.cursor);
    }
    fn goNextSibling(tc: *TreeCursor) bool {
        return c.ts_tree_cursor_goto_next_sibling(&tc.cursor);
    }
    fn goParent(tc: *TreeCursor) bool {
        return c.ts_tree_cursor_goto_parent(&tc.cursor);
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
        return Node.wrap(c.ts_tree_cursor_current_node(&tc.cursor));
    }
    fn fieldName(tc: *TreeCursor) []u8 {
        return c.ts_tree_cursor_current_field_name(&tc.cursor);
    }
    fn fieldID(tc: *TreeCursor) c.TSFieldId {
        return c.ts_tree_cursor_current_field_id(&tc.cursor);
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

pub const RowCol = struct {
    row: u64,
    col: u64,
    fn point(cp: RowCol) c.TSPoint {
        return .{ .row = @intCast(u32, cp.row), .column = @intCast(u32, cp.col) };
    }
};

pub const Tree = struct {
    parser: *c.TSParser,
    tree: *c.TSTree,
    locked: bool,

    /// source code must exist for Tree's lifetime.
    pub fn init(sourceCode: []const u8) !Tree {
        var parser = c.ts_parser_new().?;
        errdefer c.ts_parser_delete(parser);
        if (!c.ts_parser_set_language(parser, tree_sitter_markdown()))
            return error.IncompatibleLanguageVersion;

        var tree = c.ts_parser_parse_string(parser, null, sourceCode.ptr, @intCast(u32, sourceCode.len)).?;
        errdefer c.ts_tree_delete(tree);

        return Tree{
            .parser = parser,
            .tree = tree,
            .locked = false,
        };
    }
    pub fn deinit(ts: *Tree) void {
        c.ts_tree_delete(ts.tree);
        c.ts_parser_delete(ts.parser);
    }
    pub fn lock(ts: *Tree) void {
        if (ts.locked) unreachable;
        ts.locked = true;
    }
    pub fn unlock(ts: *Tree) void {
        if (!ts.locked) unreachable;
        ts.locked = false;
    }
    pub fn reparse(ts: *Tree, sourceCode: []const u8) void {
        // not sure if it is necessary to reassign tree
        // this line crashes sometimes at some character counts:
        ts.tree = c.ts_parser_parse_string(
            ts.parser,
            null,
            sourceCode.ptr,
            @intCast(u32, sourceCode.len),
        ).?;
    }
    pub fn root(ts: *Tree) Node {
        return Node.wrap(c.ts_tree_root_node(ts.tree));
    }

    /// Update source text FIRST!
    /// Calling this function may invalidate any existing Node instances. Do not store node instances across frames.
    /// because tree-sitter, caller must calculate row and column of text. how do you calculate this when you don't know the start row? idk, glhf.
    pub fn edit(
        ts: *Tree,
        startByte: u64,
        oldEndByte: u64,
        newEndByte: u64,
        start: RowCol,
        oldEnd: RowCol,
        newEnd: RowCol,
    ) void {
        if (ts.locked) unreachable;
        c.ts_tree_edit(ts.tree, &c.TSInputEdit{
            .start_byte = @intCast(u32, startByte),
            .old_end_byte = @intCast(u32, oldEndByte),
            .new_end_byte = @intCast(u32, newEndByte),
            .start_point = start.point(), // why do TSPoints exist, who needed this
            .old_end_point = oldEnd.point(), // who why
            .new_end_point = newEnd.point(), // can I get rid of this
        });
    }
};

fn testParser() !void {
    const sourceCode = "Test **Markdown**\n\n# a\n\nText  \nMore Text\nHi!\n\nHola";

    var tree = try Tree.init(sourceCode);
    defer tree.deinit();

    var rootNode = tree.root();

    var cursor = TreeCursor.init(rootNode);

    var i: u64 = 0;
    for (sourceCode) |charStr| {
        var classs = getNodeAtPosition(i, rootNode).createClassesStruct();
        std.debug.warn(
            "Char: [{}]`{c}`, Class: {}, Style: {}\n",
            .{
                i,
                switch (charStr) {
                    '\n' => '!',
                    else => |q| q,
                },
                classs,
                classs.renderStyle(),
            },
        );
        i += 1;
    }
    std.debug.warn("Root: {}\n", .{rootNode});

    // what we want is to be able to query the class of a character
    // it looks like that's not easy. how about instead, we use the "Walking Trees with Tree Cursors" thing
}

test "parser" {
    try testParser();
}
