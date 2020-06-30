const std = @import("std");
const Alloc = std.mem.Allocator;
const help = @import("helpers.zig");
const header = @import("header_match.zig");

// note std.unicode can be used to do some things

// editor core

// usingnamespace autoinit(Me, struct {
//     pub fn init() {}
//     pub fn deinit() {}
// });

pub fn Stack(comptime Child: type) type {
    return struct {
        const Me = @This();
        al: std.ArrayList(Child),
        // could be useful if this could expose al.items for easier iteration but f.
        pub fn init(alloc: *Alloc) Me {
            return .{
                .al = std.ArrayList(Child).init(alloc),
            };
        }
        pub fn deinit(me: *Me) void {
            me.al.deinit();
        }

        pub fn push(me: *Me, itm: Child) !void {
            return me.al.append(itm);
        }
        pub fn pop(me: *Me) ?Child {
            return me.al.popOrNull();
        }
        pub fn last(me: Me) ?Child {
            if (me.al.items.len == 0) return null;
            return me.al.items[me.al.items.len - 1];
        }
    };
}

pub const CursorPos = struct {
    byte: u64,
};

// this should be built into arraylist
pub fn alRemoveRange(al: var, start: usize, end: usize) void {
    if (@typeInfo(@TypeOf(al)) != .Pointer) @compileError("must be *std.ArrayList(...)");
    const ChildT = @typeInfo(@TypeOf(al).Child.Slice).Pointer.child;
    std.mem.copy(ChildT, al.items[start..], al.items[end..]);
    al.items.len -= end - start;
}

pub const Action = union(enum) {
    insert: Insert,
    pub const Insert = struct {
        text: []const u8,
        cursorPos: CursorPos,
        pub fn initCopy(text: []const u8, startPos: CursorPos, alloc: *Alloc) !Action {
            return Action{
                .insert = .{
                    .text = try std.mem.dupe(alloc, u8, text),
                    .cursorPos = startPos,
                },
            };
        }
        pub fn redo(me: Insert, core: *EditorCore) !void {
            try core.text.insertSlice(me.cursorPos.byte, me.text);
            // move cursor?
        }
        pub fn undo(me: Insert, core: *EditorCore) !void {
            alRemoveRange(&core.text, me.cursorPos.byte, me.cursorPos.byte + me.text.len);
            // move cursor?
        }
        pub fn deinit(me: *Insert, alloc: *Alloc) void {
            alloc.free(me.text);
            me.* = undefined;
        }
    };

    pub fn redo(me: Action, core: *EditorCore) !void {
        try help.unionCallThis("redo", me, .{core});
    }
    pub fn undo(me: Action, core: *EditorCore) !void {
        try help.unionCallThis("undo", me, .{core});
    }
    pub fn deinit(me: *Action, alloc: *Alloc) void {
        help.unionCallThis("deinit", me, .{alloc});
    }
};

pub const Measurement = struct {
    width: i64,
    height: i64,
    baseline: i64,
};

pub fn LinkedList(comptime Value: type) type {
    return struct {
        pub const Iterator = struct {
            thisPtr: ?*Node,
            /// do not insert/remove the returned node's next
            /// if you plan on continuing iteration
            /// any other modifications are okay (eg removing
            /// the returned node or inserting before
            /// the returned node)
            pub fn next(iter: *Iterator) ?*Node {
                const res = iter.thisPtr;
                if (iter.thisPtr) |tp| iter.thisPtr = tp.next;
                return res;
            }
        };
        pub const Node = struct {
            value: Value,
            next: ?*Node,
            previous: ?*Node,
            alloc: *Alloc,
            pub fn create(alloc: *Alloc, value: Value) !*Node {
                var node = try alloc.create(Node);
                node.* = .{ .alloc = alloc, .value = value, .next = null, .previous = null };
                return node;
            }
            pub fn remove(me: *Node) Value {
                if (me.next) |nxt| nxt.previous = me.previous;
                if (me.previous) |prev| prev.next = me.next;

                const result = me.value;
                me.alloc.destroy(me);
                return result;
            }
            pub fn insertAfter(me: *Node, value: Value) !*Node {
                var node = try me.alloc.create(Node);
                node.* = .{ .alloc = me.alloc, .value = value, .next = me.next, .previous = me };
                if (me.next) |nxt| nxt.previous = node;
                me.next = node;
                return node;
            }
            pub fn insertBefore(me: *Node, value: Value) !*Node {
                var node = try me.alloc.create(Node);
                node.* = .{ .alloc = me.alloc, .value = value, .next = me.previous, .previous = me };
                if (me.previous) |prv| prv.next = node;
                me.previous = node;
                return node;
            }
            pub fn iter(me: *Node) Iterator {
                return .{ .thisPtr = me };
            }
        };
    };
}

// const MeasurerInterface = struct {
//     pub const Text = struct {
//         fn deinit(text: *Text) void {}
//     };
//     pub fn render(me: *Measurer, text: []const u8, style: TextStyle, measure: Measurement) Text {
//         return undefined;
//     }
//     pub fn measure(me: *Measurer, text: []const u8, style: TextStyle) Measurement {
//         return undefined;
//     }
//     pub fn deinit(me: *Measurer) void {}
// };
// header.conformsTo(MeasurerInterface, Measurer);
//    zig compiler crash oops
pub fn EditorCore(comptime Measurer: type) type {
    return struct {
        const Core = @This();

        pub const CharacterMeasure = struct { width: i64 };
        pub const MeasurementData = struct {
            characters: std.ArrayList(CharacterMeasure),
            measure: Measurement,
            data: Measurer.Text, // measurer.render
            pub fn deinit(md: *MeasurementData) void {
                md.characters.deinit();
                md.data.deinit();
                md.* = undefined;
            }
        };
        pub const CodeText = struct {
            // in the future, if really large files are ever supported, it might be possible
            // for a given range of text to not exist and require fetching the file to find.
            // luckily,  this is not necessary to  worry about right  now because now is not
            // the future.
            text: std.ArrayList(u8),
            // might need to include individual character sizes too
            // ^ do, not might.
            measure: ?MeasurementData,

            pub fn node(me: *CodeText) *RangeList.Node {
                return @fieldParentPtr(RangeList.Node, "value", me);
            }
            pub fn prev(me: *CodeText) ?*CodeText {
                const node_ = me.node();
                if (node_.previous) |prev_| return &prev_.value;
                return null;
            }
            pub fn next(me: *CodeText) ?*CodeText {
                const node_ = me.node();
                if (node_.next) |next_| return &next_.value;
                return null;
            }
            pub fn deinit(me: *CodeText) void {
                me.text.deinit();
                if (me.measure) |*measure| {
                    measure.deinit();
                }
            }
        };
        pub const RangeList = LinkedList(CodeText);

        alloc: *Alloc,
        measurer: Measurer,

        code: *RangeList.Node,

        /// must be the start of a line
        top: struct {
            text: *CodeText,
            scroll: i64, // if this goes past the line height, move forwards/backwards
        } = undefined,

        readonly: bool = false,

        cursor: TextPoint,
        pub const TextPoint = struct { text: *CodeText, offset: u64 };

        /// force remeasure a given node. use remeasureIfNeeded instead
        pub fn remeasure(me: *Core, text: *CodeText) !void {
            var charactersAl = std.ArrayList(CharacterMeasure).init(me.alloc);
            errdefer charactersAl.deinit();

            for (text.text.items) |_, i| {
                const progress: Measurement = try me.measurer.measure(text.text.items[0 .. i + 1]);
                try charactersAl.append(.{ .width = progress.width });
            }

            const measurement = try me.measurer.measure(text.text.items);
            const data = try me.measurer.render(text.text.items, measurement);
            errdefer data.deinit();

            text.measure = .{
                .measure = measurement,
                .data = data,
                .characters = charactersAl,
            };
        }

        // todo: move by whole codepoints
        pub fn addPoint(me: *Core, point: TextPoint, add: i64) TextPoint {
            if (add == 0) return .{ .text = point.text, .offset = point.offset };
            // there is probably a sensible way to do this
            var currentPoint: TextPoint = .{ .text = point.text, .offset = point.offset };
            var remaining: u64 = std.math.absCast(add);
            var direction: enum { left, right } = if (add < 0) .left else .right;

            while (true) {
                var lenlen = switch (direction) {
                    .right => currentPoint.text.text.items.len - currentPoint.offset,
                    .left => currentPoint.offset,
                };
                if (remaining <= lenlen) {
                    return .{
                        .text = currentPoint.text,
                        .offset = switch (direction) {
                            .left => currentPoint.offset - remaining,
                            .right => currentPoint.offset + remaining,
                        },
                    };
                }
                remaining -= lenlen + 1;
                while (true) {
                    switch (direction) {
                        .left => currentPoint.text = currentPoint.text.prev() orelse
                            return .{ .text = currentPoint.text, .offset = 0 },
                        .right => currentPoint.text = currentPoint.text.next() orelse
                            return .{ .text = currentPoint.text, .offset = currentPoint.text.text.items.len },
                    }
                    if (currentPoint.text.text.items.len > 0) break;
                }
                currentPoint.offset = switch (direction) {
                    .left => currentPoint.offset + currentPoint.text.text.items.len - 1,
                    .right => 1,
                };
            }

            unreachable;
        }

        /// after calling this function, text.measure is not null
        /// and up to date, unless this function returns an error.
        pub fn remeasureIfNeeded(me: *Core, text: *CodeText) !void {
            // when editing nodes, any affected will have measure reset to nlul
            if (text.measure == null) return me.remeasure(text);
        }

        pub fn insert(me: *Core, point: TextPoint, text: []const u8) !void {
            try point.text.text.insertSlice(point.offset, text);
            if (text.len != 0) clearMeasure(point.text);
            // 1. update tree-sitter
            // 2. remeasure? idk
            // 3. â€™
            // also how to make sure eg cursor never has an invalid offset? idk. todo think.

            // update all saved TextPoints at the updated point to the new point.
            // maybe a fn to handle this?
            if (me.cursor.text == point.text) {
                // depending on insert direction, choose > or >=
                if (me.cursor.offset >= point.offset) me.cursor.offset += text.len;
            }
        }

        pub fn removeNodeText(me: *Core, node: *RangeList.Node, from: usize, to: usize) void {
            alRemoveRange(&node.value.text, from, to);
            if (to - from != 0) clearMeasure(&node.value);

            if (me.cursor.text == &node.value) {
                if (me.cursor.offset > to) me.cursor.offset -= to - from
                // zig fmt bug
                else if (me.cursor.offset > from) me.cursor.offset = from;
            }
            if (node.value.text.items.len != 0) return;

            // first node:
            if (me.code == node) {
                if (node.next == null) return;
                me.code = node.next.?;
            }
            if (me.cursor.text == &node.value) {
                if (node.next) |nxt| me.cursor = .{ .text = &nxt.value, .offset = 0 }
                // zig
                else me.cursor = .{ .text = &node.previous.?.value, .offset = node.previous.?.value.text.items.len };
            }
            node.remove().deinit();
        }

        pub fn delete(me: *Core, from: TextPoint, to: TextPoint) void {
            if (from.text == to.text) {
                me.removeNodeText(from.text.node(), from.offset, to.offset);
                return;
            }
            var currentText: ?*CodeText = from.text;
            while (currentText) |ctxt| : (currentText = currentText.?.next()) {
                if (ctxt == from.text) {
                    me.removeNodeText(ctxt.node(), from.offset, ctxt.text.items.len);
                } else if (ctxt == to.text) {
                    me.removeNodeText(ctxt.node(), 0, to.offset);
                } else {
                    me.removeNodeText(ctxt.node(), 0, ctxt.text.items.len);
                }
            }
        }

        pub fn splitNode(me: *Core, point: TextPoint) !void {
            // split the node
            // update any saved nodes eg cursor position
            if (point.offset == 0) return; // nothing to split
            if (point.offset == point.text.text.items.len) return; // nothing to split
            var removeSlice = point.text.text.items[point.offset..];

            var al = try std.ArrayList(u8).initCapacity(me.alloc, removeSlice.len);
            errdefer al.deinit();

            al.appendSlice(removeSlice) catch unreachable;
            alRemoveRange(&point.text.text, point.offset, point.text.text.items.len);

            clearMeasure(point.text);
            var insertedNode = try point.text.node().insertAfter(.{ .text = al, .measure = null });
            errdefer _ = insertedNode.remove();

            if (me.cursor.text == point.text and me.cursor.offset > point.text.text.items.len) {
                me.cursor = .{
                    .text = &insertedNode.value,
                    .offset = me.cursor.offset - point.text.text.items.len, // hmm
                };
            }
        }

        pub fn mergeNextNode(me: *Core, first: *CodeText) !void {
            if (first.node().next == null) return; // nothing to merge

            var next = &first.node().next.?.value;
            if (me.cursor.text == next) {
                me.cursor = .{
                    .text = first,
                    .offset = first.text.items.len - 1 + me.cursor.offset,
                };
            }
            try first.text.appendSlice(next.text.items);
            next.node().remove().deinit();

            clearMeasure(first);
        }

        pub fn clearMeasure(node: *CodeText) void {
            if (node.measure) |*m| m.deinit();
            node.measure = null;
        }

        pub fn splitNewlines(me: *Core, start: *CodeText) !void {
            // find the next newline
            // split/merge until we get there
            // leave the newline/space in the same line
            var i: usize = 0;
            while (i < start.text.items.len) : (i += 1) {
                const char = start.text.items[i];
                // std.debug.warn("Char[{}] = `{c}`\n", .{ i, char });
                if (char == ' ' or char == '\n') {
                    try me.splitNode(.{ .text = start, .offset = i + 1 });
                    // try me.splitNode(.{ .text = start, .offset = i }); // put the newline/space into its own node.
                    break;
                }
                if (i == start.text.items.len - 1) { // todo and nextNode != '\n' || ' '
                    // this is why it might be better to not put the newline/space into its own line
                    // but idk
                    try me.mergeNextNode(start);
                }
            }
            // either we broke from the loop or hit the end of the text
        }

        // what if renderIterator handles all the tree sitter stuff and the only thing
        // the other fns have to do is publish edits?
        // that wouldn't be terrible
        // so renderIterator will be splitting nodes and stuff while looping
        pub const RenderIterator = struct {
            current: ?*CodeText,
            y: i64 = 0,
            width: i64,
            height: i64,
            core: *Core,

            const RenderPiece = struct { x: i64, y: i64, measure: *MeasurementData, text: *CodeText };
            const RenderResult = struct {
                pieces: []RenderPiece,
                lineHeight: i64,
                alloc: *Alloc,
                y: i64,
                pub fn deinit(me: *RenderResult) void {
                    me.alloc.free(me.pieces);
                    me.* = undefined;
                }
            };
            pub fn next(ri: *RenderIterator, alloc: *Alloc) !?RenderResult {
                if (ri.y > ri.height) return null;
                if (ri.current == null) return null;

                var currentNode: ?*RangeList.Node = ri.current.?.node();

                var cx: i64 = 0;
                var lineHeight: i64 = 0;
                var lineBaseline: i64 = 0;

                var resAL = std.ArrayList(RenderPiece).init(alloc);
                errdefer resAL.deinit();

                while (currentNode) |node| {
                    var text: *CodeText = &node.value;

                    try ri.core.splitNewlines(text);
                    try ri.core.remeasureIfNeeded(text);

                    const measure = text.measure.?;
                    cx += measure.measure.width;

                    if (cx >= ri.width and resAL.items.len > 0) break;

                    lineBaseline = std.math.max(lineBaseline, measure.measure.baseline);
                    lineHeight = std.math.max(lineHeight, measure.measure.height);

                    try resAL.append(.{ .x = cx - measure.measure.width, .y = undefined, .measure = &text.measure.?, .text = text });
                    currentNode = node.next;

                    if (node.value.text.items.len != 0 and node.value.text.items[node.value.text.items.len - 1] == '\n') break; // oh god why eww
                }
                for (resAL.items) |*item| {
                    item.y = ri.y + (lineBaseline - item.measure.measure.baseline);
                }
                const itemY = ri.y;

                if (currentNode) |cn| {
                    ri.current = &cn.value;
                } else ri.current = null;
                ri.y += lineHeight;

                return RenderResult{
                    .pieces = resAL.toOwnedSlice(),
                    .lineHeight = lineHeight,
                    .alloc = alloc,
                    .y = itemY,
                };
            }
        };
        pub fn render(me: *Core, width: i64, height: i64, deltaScroll: i64) RenderIterator {
            return .{ .current = &me.code.value, .width = width, .height = height, .core = me };
        }

        pub fn init(alloc: *Alloc, measurer: Measurer) !Core {
            var snal = std.ArrayList(u8).init(alloc);
            errdefer snal.deinit();
            const startNode = try RangeList.Node.create(
                alloc,
                .{ .text = snal, .measure = null },
            );
            errdefer startNode.remove(alloc);

            return Core{
                .alloc = alloc,
                .measurer = measurer,
                .cursor = .{ .text = &startNode.value, .offset = 0 },
                .code = startNode,
            };
        }

        pub fn deinit(me: *Core) void {
            me.measurer.deinit();
            var iter = me.code.iter();
            while (iter.next()) |itm| {
                itm.remove().deinit();
            }
            me.* = undefined;
        }
    };
}

test "editor core" {
    const alloc = std.testing.allocator;

    const Measurer = struct {
        const Measurer = @This();
        someData: u32,

        pub const Text = struct {
            txt: []const u8,
            pub fn deinit(me: *Text) void {}
        };
        pub fn render(me: *Measurer, text: []const u8, mesur: Measurement) !Text {
            if (me.someData != 5) unreachable;
            return Text{ .txt = text };
        }
        pub fn measure(me: *Measurer, text: []const u8) !Measurement {
            if (me.someData != 5) unreachable;
            var finalSize: i64 = 0;
            for (text) |char| {
                finalSize += switch (char) {
                    'i' => 5,
                    'm' => 15,
                    else => @as(i64, 10),
                };
            }
            return Measurement{
                .width = finalSize,
                .height = if (text.len > 0) 50 else 25,
                .baseline = 45,
            };
        }
        pub fn deinit(me: *Measurer) void {}
    };
    var core: EditorCore(Measurer) = try EditorCore(Measurer).init(alloc, Measurer{ .someData = 5 }); // , struct {fn measureText()} {};
    defer core.deinit();

    try core.insert(core.cursor, "Hello, World! ");
    try testRenderCore(&core, alloc, &[_][]const []const u8{
        &[_][]const u8{ "Hello, ", "World! " },
    });

    try core.insert(core.cursor, "Oop!");
    try testRenderCore(&core, alloc, &[_][]const []const u8{
        &[_][]const u8{ "Hello, ", "World! ", "Oop!" },
    });

    try core.insert(core.cursor, "\nnewline");
    try testRenderCore(&core, alloc, &[_][]const []const u8{
        &[_][]const u8{ "Hello, ", "World! ", "Oop!\n" },
        &[_][]const u8{"newline"},
    });

    renderCursorPosition(core);
    core.cursor = core.addPoint(core.cursor, -12);
    renderCursorPosition(core);

    try core.insert(core.cursor, "Fix this? ");
    try testRenderCore(&core, alloc, &[_][]const []const u8{
        &[_][]const u8{ "Hello, ", "World! ", "Fix ", "this? ", "Oop!\n" },
        &[_][]const u8{"newline"},
    });

    // std.testing.expectEqual(expected: var, actual: @TypeOf(expected))
}

pub fn renderCursorPosition(core: var) void {
    std.debug.warn("Cursor is on text `", .{});
    for (core.cursor.text.text.items) |char, i| {
        if (i == core.cursor.offset) std.debug.warn("|", .{});
        std.debug.warn("{c}", .{char});
    }
    if (core.cursor.offset == core.cursor.text.text.items.len) std.debug.warn("|", .{});
    std.debug.warn("` at offset {}\n", .{core.cursor.offset});
}

pub fn testRenderCore(core: var, alloc: var, expected: []const []const []const u8) !void {
    var riter = core.render(1000, 500, 0);
    var gi: usize = 0;
    std.debug.warn("Testing\n", .{});
    var fail = false;
    while (try riter.next(alloc)) |*nxt| : (gi += 1) {
        defer nxt.deinit();

        std.debug.warn("  Rendering line with height {}\n", .{nxt.lineHeight});

        for (nxt.pieces) |piece, i| {
            std.debug.warn("    Piece x={}: `{}`\n", .{ piece.x, piece.measure.data.txt });
            if (i >= expected[gi].len or !std.mem.eql(u8, expected[gi][i], piece.measure.data.txt)) fail = true;
        }
        if (expected[gi].len != nxt.pieces.len) fail = true;
    }
    if (gi != expected.len) fail = true;
    if (fail) return error.TestFailure;
}
