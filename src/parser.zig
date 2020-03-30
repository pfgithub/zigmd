const c = @import("./c.zig");
const std = @import("std");

extern fn tree_sitter_json() ?*c.TSLanguage;
extern fn tree_sitter_markdown() ?*c.TSLanguage;

pub fn main() !void {
    try testParser();
}

const RenderStyle = union(enum) {
    control: void,
    text: struct {
        bold: bool,
        italic: bool,
    },
    heading: struct {},
    display: union(enum) {
        eolSpace: bool, // `·`
        newline: bool, // `⏎`
    },
};

const Class = struct {
    document: bool,
    paragraph: bool,
    strong: bool, // text && bold
    emphasis: bool, // text && italic
    text: bool, // !text: control character, monospace
    atx_heading: bool, // text && heading
    atx_heading_marker: bool,
    heading_content: bool,
    hard_line_break: bool, // control character, monospace, `·`
};

const Position = struct { from: u64, to: u64 };
const Node = struct {
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

fn getNodeAtPosition(char: u64, parentNode: Node) Node {
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

fn testParser() !void {
    var parser = c.ts_parser_new();
    defer c.ts_parser_delete(parser);
    if (c.ts_parser_set_language(parser, tree_sitter_markdown()) == false) return error.IncompatibleLanguageVersion;

    const sourceCode = "Test **Markdown**\n\n# a\n\nText  \nMore Text\nHi!\n\nHola";
    var tree = c.ts_parser_parse_string(parser, null, sourceCode, sourceCode.len);
    defer c.ts_tree_delete(tree);

    var rootNode = Node.wrap(c.ts_tree_root_node(tree));

    var cursor = TreeCursor.init(rootNode);

    var i: u64 = 0;
    for (sourceCode) |charStr| {
        std.debug.warn(
            "Char: [{}]`{c}`, Class: ",
            .{ i, switch (charStr) {
                '\n' => '!',
                else => |q| q,
            } },
        );
        getNodeAtPosition(i, rootNode).printClasses();
        i += 1;
    }
    std.debug.warn("Root: {}\n", .{rootNode});

    // what we want is to be able to query the class of a character
    // it looks like that's not easy. how about instead, we use the "Walking Trees with Tree Cursors" thing
}

test "parser" {
    try testParser();
}
