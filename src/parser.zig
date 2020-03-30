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
    display: union(enum) {
        eolSpace: void, // `·`
        newline: void, // `⏎`
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
    thematic_break: bool = false,

    pub fn renderStyle(cs: Class) RenderStyle {
        if (cs.soft_line_break) return .{ .display = .newline };
        if (cs.hard_line_break) return .{ .display = .eolSpace };
        if (cs.text) {
            if (cs.atx_heading) return .{ .heading = .{} };
            if (cs.strong_emphasis and cs.emphasis)
                return .{ .text = .bolditalic };
            if (cs.strong_emphasis) return .{ .text = .bold };
            if (cs.emphasis) return .{ .text = .italic };
            return .{ .text = .normal };
        }
        return .control; // note that raw newlines will become control. these should be handled as a special case.
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

const TreeCursor = struct {
    cursor: c.TSTreeCursor,
    fn init(initialNode: Node) TreeCursor {
        return .{
            .cursor = c.ts_tree_cursor_new(initialNode.node),
        };
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

pub fn getNodeAtPosition(char: u64, parentNode: Node) Node {
    var cursor = TreeCursor.init(parentNode);
    var bestMatch: Node = parentNode;
    while (char >= cursor.node().position().from) {
        var currentPosition = cursor.node().position();
        if (char >= currentPosition.from and char < currentPosition.to) {
            bestMatch = cursor.node();
        }
        // advance cursor
        if (!cursor.advance()) break;
    }
    return bestMatch;
}

pub const Tree = struct {
    parser: *c.TSParser,
    tree: *c.TSTree,
    pub fn init(sourceCode: []const u8) !Tree {
        var parser = c.ts_parser_new().?;
        errdefer c.ts_parser_delete(parser);
        if (!c.ts_parser_set_language(parser, tree_sitter_markdown()))
            return error.IncompatibleLanguageVersion;

        var tree = c.ts_parser_parse_string(parser, null, sourceCode.ptr, @intCast(u32, sourceCode.len)).?; // does this mean tree sitter can't handle files more than 4.3gb? probably. it's probably not a good idea to give it files that size anyway.
        errdefer c.ts_tree_delete(tree);

        return Tree{
            .parser = parser,
            .tree = tree,
        };
    }
    pub fn deinit(ts: *Tree) void {
        c.ts_tree_delete(ts.tree);
        c.ts_parser_delete(ts.parser);
    }
    pub fn root(ts: *Tree) Node {
        return Node.wrap(c.ts_tree_root_node(ts.tree));
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
