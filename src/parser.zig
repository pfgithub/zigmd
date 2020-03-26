const c = @import("./c.zig");
const std = @import("std");

extern fn tree_sitter_json() ?*c.TSLanguage;

pub fn main() !void {
    var parser = c.ts_parser_new();
    defer c.ts_parser_delete(parser);
    if (c.ts_parser_set_language(parser, tree_sitter_json()) == false) return error.IncompatibleLanguageVersion;

    // const sourceCode = "Test **Markdown**\n\n# a";
    const sourceCode = "{\"Test\": \"JSON\"}";
    var tree = c.ts_parser_parse_string(parser, null, sourceCode, sourceCode.len);
    defer c.ts_tree_delete(tree);

    var rootNode = c.ts_tree_root_node(tree);

    var str = c.ts_node_string(rootNode);
    defer c.free(str);

    std.debug.warn("Syntax tree: {s}\n", .{str});
}
