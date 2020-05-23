const std = @import("std");
// editor core

// some things this should do:
// unicode codepoints should always be treated as a single character
pub const EditorCore = struct {
    text: std.ArrayList(u8),
    measureCache: std.ArrayList(LineMeasure),
    pub fn insert(core: *EditorCore, insertPoint: Point) void {
        // invalidate the measure cache
        // edit the tree-sitter node
    }
};
