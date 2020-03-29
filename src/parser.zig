const c = @import("./c.zig");
const std = @import("std");

extern fn tree_sitter_json() ?*c.TSLanguage;
extern fn tree_sitter_markdown() ?*c.TSLanguage;

pub fn main() !void {
    try testParser();
}

const Node = struct {
    node: c.TSNode,
    fn wrap(rawNode: c.TSNode) Node {
        return .{ .node = rawNode };
    }
    fn print(n: *Node) void {
        var str = c.ts_node_string(n.node);
        defer c.free(str);
        std.debug.warn("Syntax tree: {s}\n", .{str});
    }
};

const TreeCursor = struct {
    cursor: c.TSTreeCursor,
    const Errors = error{NowhereToGo};
    fn init(initialNode: Node) TreeCursor {
        return .{
            .cursor = c.ts_tree_cursor_new(initialNode.node),
        };
    }
    fn firstChild(tc: *TreeCursor) !void {
        if (!c.ts_tree_cursor_goto_first_child(&tc.cursor)) return Errors.NowhereToGo;
    }
    fn nextSibling(tc: *TreeCursor) !void {
        if (!c.ts_tree_cursor_goto_next_sibling(&tc.cursor)) return Errors.NowhereToGo;
    }
    fn parent(tc: *TreeCursor) !void {
        if (!c.ts_tree_cursor_goto_parent(&tc.cursor)) return Errors.NowhereToGo;
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

fn testParser() !void {
    var parser = c.ts_parser_new();
    defer c.ts_parser_delete(parser);
    if (c.ts_parser_set_language(parser, tree_sitter_markdown()) == false) return error.IncompatibleLanguageVersion;

    const sourceCode = "Test **Markdown**\n\n# a\n\nText  \nMore Text\nHi!\n\nHola";
    var tree = c.ts_parser_parse_string(parser, null, sourceCode, sourceCode.len);
    defer c.ts_tree_delete(tree);

    var rootNode = Node.wrap(c.ts_tree_root_node(tree));

    var cursor = TreeCursor.init(rootNode);

    try cursor.firstChild();
    cursor.node().print();
    try cursor.nextSibling();
    cursor.node().print();
    try cursor.parent();
    cursor.node().print();

    // what we want is to be able to query the class of a character
    // it looks like that's not easy. how about instead, we use the "Walking Trees with Tree Cursors" thing
}

test "parser" {
    try testParser();
}
