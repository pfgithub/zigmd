const c = @import("./c.zig");
const std = @import("std");

extern fn tree_sitter_json() ?*c.TSLanguage;
extern fn tree_sitter_markdown() ?*c.TSLanguage;

pub fn main() !void {
    try testParser();
}

pub const RenderStyle = union(enum) {
    control: void,
    text: struct {
        bold: bool = false,
        italic: bool = false,
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
    strong: bool = false, // text && bold
    emphasis: bool = false, // text && italic
    text: bool = false, // !text: control character, monospace
    atx_heading: bool = false, // text && heading
    atx_heading_marker: bool = false,
    heading_content: bool = false,
    hard_line_break: bool = false, // .display.eolSpace
    strong_emphasis: bool = false,
    soft_line_break: bool = false, // .display.newline

    pub fn renderStyle(cs: Class) RenderStyle {
        if (cs.soft_line_break) return .{ .display = .newline };
        if (cs.hard_line_break) return .{ .display = .eolSpace };
        if (cs.text) {
            if (cs.atx_heading) return .{ .heading = .{} };
            if (cs.strong and cs.emphasis)
                return .{ .text = .{ .bold = true, .italic = true } };
            if (cs.strong) return .{ .text = .{ .bold = true } };
            if (cs.emphasis) return .{ .text = .{ .italic = true } };
            return .{ .text = .{} };
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
