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
            pub fn create(alloc: *Alloc, value: Value) !*Node {
                var node = try alloc.create(Node);
                node.* = .{ .value = value, .next = null, .previous = null };
                return node;
            }
            pub fn remove(me: *Node, alloc: *Alloc) Value {
                if (me.next) |nxt| nxt.previous = me.next;
                if (me.previous) |prev| prev.next = me.previous;

                const result = me.value;
                alloc.destroy(me);
                return result;
            }
            pub fn insertAfter(me: *Node, alloc: *Alloc, value: Value) !*Node {
                var node = try alloc.create(Node);
                node.* = .{ .value = value, .next = me.next, .previous = me };
                me.next.previous = node;
                me.next = node;
                return node;
            }
            pub fn insertBefore(me: *Node, alloc: *Alloc, value: Value) !*Node {
                var node = try alloc.create(Node);
                node.* = .{ .value = value, .next = me.previous, .previous = me };
                me.previous.next = node;
                me.previous = node;
                return node;
            }
            pub fn iter(me: *Node) Iterator {
                return .{ .thisPtr = me };
            }
        };
    };
}

pub fn EditorCore(comptime Measurer: type) type {
    const MeasurerInterface = struct {
        pub const Text = struct {
            fn deinit(text: *Text) void {}
        };
        pub fn render(me: *Measurer, text: []const u8, style: TextStyle, measure: Measurement) Text {
            return undefined;
        }
        pub fn measure(me: *Measurer, text: []const u8, style: TextStyle) Measurement {
            return undefined;
        }
        pub fn deinit(me: *Measurer) void {}
    };
    // header.conformsTo(MeasurerInterface, Measurer);
    //    zig compiler crash oops

    return struct {
        const Core = @This();

        pub const MeasurementData = struct {
            characters: std.ArrayList(struct { width: i64 }),
            measure: Measurement,
            data: Measurer.Text, // measurer.render
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
            pub fn deinit(me: *CodeText) void {
                me.text.deinit();
                if (me.measure) |*measure| {
                    measure.characters.deinit();
                    measure.measure.deinit();
                    measure.data.deinit();
                }
            }
        };
        pub const RangeList = LinkedList(CodeText);

        alloc: *Alloc,
        measurer: Measurer,

        code: *RangeList.Node,

        cursor: TextPoint,
        pub const TextPoint = struct { text: *CodeText, offset: u64 };

        pub fn insert(me: *Core, point: TextPoint, text: []const u8) !void {
            try point.text.text.insertSlice(point.offset, text);
            point.text.measure = null;
            // 1. update tree-sitter
            // 2. remeasure? idk
            // 3. â€™
            // also how to make sure eg cursor never has an invalid offset? idk. todo think.

            // update all saved TextPoints at the updated point to the new point.
            // maybe a fn to handle this?
            if (me.cursor.text == point.text) {
                // depending on insert direction, choose > or >=
                if (me.cursor.offset > point.offset) me.cursor.offset += point.offset;
            }
        }

        pub fn removeNodeText(me: *Core, node: *RangeList.Node, from: usize, to: usize) void {
            alRemoveRange(node.value.text, from, to);
            if (me.cursor.text == &node.value) {
                if (me.cursor.offset > to) me.cursor.offset -= to - from
                // zig fmt bug
                else if (me.cursor.offset > from) me.cursor.offset = from;
            }
            if (node.value.text.items != 0) return;

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
            // TODO: remove 0-length nodes unless the node is the
            // start node and there is no next node.
            if (from.node == to.node) {
                me.removeNodeText(from.text.node(), from.offset, to.offset);
                return;
            }
            var currentText: ?*CodeText = from.text;
            while (currentText) |ctxt| : (currentText = currentText.node().next) {
                if (ctxt == from.text) {
                    me.removeNodeText(ctxt.text.node(), from.offset, ctxt.items.len);
                } else if (ctxt == to.text) {
                    me.removeNodeText(ctxt.text.node(), 0, to.offset);
                } else {
                    me.removeNodeText(ctxt.text.node(), 0, ctxt.text.items.len);
                }
            }
        }

        pub fn splitNode(me: *Core, point: TextPoint) !void {
            // split the node
            // update any saved nodes eg cursor position
            if (point.offset == point.text.text.items.len) return; // nothing to split
            var removeSlice = point.text.text.items[point.offset..];

            var al = try std.ArrayList(u8).initCapacity(removeSlice.len);
            errdefer al.deinit();

            al.appendSlice(removeSlice) catch unreachable;
            alRemoveRange(al, point.offset, al.items.len);

            var insertedNode = try point.text.node().insertAfter(me.alloc, .{ .text = al, .measure = null });
            errdefer _ = insertedNode.remove();

            if (me.cursor.text == point.text and me.cursor.offset > point.text.text.items.len) {
                me.cursor = .{
                    .text = &insertedNode.value,
                    .offset = me.cursor.offset - point.text.text.items.len, // hmm
                };
            }
        }

        pub fn mergeNextNode(me: *Core, first: *CodeText) !void {
            if (first.node().next == null) return; // nothing to merge. @panic()?
            var next = &first.node().next.?.value;
            if (me.cursor.text == next) {
                me.cursor = .{
                    .text = first,
                    .offset = first.text.items.len - 1 + me.cursor.offset,
                };
            }
            try first.text.appendSlice(next.text.items);
            next.node().remove().deinit();
        }

        pub fn splitNewlines(me: *Core, start: *CodeText) !void {
            // find the next newline
            // split/merge until we get there
            // leave the newline/space in the same line
            var i: usize = 0;
            while (i < start.text.items.len) {
                const char = start.text.items[i];
                if (char == ' ' or char == '\n') {
                    try me.splitNode(.{ .text = start, .offset = i + 1 });
                    try me.splitNode(.{ .text = start, .offset = i }); // put the newline/space into its own node.
                    break;
                }
                if (i == start.text.items.len - 1) {
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
            x: i64 = 0,
            y: i64 = 0,
            width: i64,
            height: i64,
            core: *EditorCore,
            remainingItemsInLine: usize = 0,
            lineHeight: i64 = 0,
            lineBaseline: i64 = undefined,

            // this function might be better if it returned []struct{...} that you freed so it could do the whole line
            // at once without an inner loop
            pub fn next(ri: *RenderIterator) ?struct { x: i64, y: i64, height: i64, measure: MeasurementData } {
                if (ri.y > ri.height) return null;
                if (ri.current == null) return null;

                const current = ri.current.?;

                if (ri.remainingItemsInLine == 0) {
                    ri.y += ri.lineHeight;
                    ri.lineHeight = undefined;
                    ri.lineBaseline = undefined;

                    // for now, split at spaces and newlines and merge others
                    // - find distance to next space or newline
                    //   - if in this node, split this node at that point, keeping the space in this node
                    // - if this node ends with a space/newline, do nothing
                    // - if this node does not contain a space/newline, check next node. if !next node, do nothing.
                    //   if next node, find space in next node, split
                    // this sounds like a mess doesn't it
                    // actually no, it's surprisingly simple

                    var currentNode = current.node();
                    var cx = 0;
                    while (currentNode) |node| {
                        currentNode = currentNode.node().next; // advance current node

                        ri.core.splitNewlines(&node.value.text);
                        // measure + ?render node
                        // there was supposed to be a difference between measure and render
                        // I guess the only difference is render is an unknown type but measure is known

                        ri.core.remeasureIfNeeded(&node.value.text);
                        cx += node.text.measure.measure.width;

                        // no need to continue measuring if this goes over the line
                        if (cx >= ri.width) break;
                        if (std.mem.eql(u8, node.value.text.items, "\n")) break;
                    }

                    // update nodes to match tree-sitter (but split at newlines and spaces no matter what) here
                    // TODO.

                    // loop over this line until reaching the end.
                    //   tree sitter get and split/merge this node into the nodes tree-sitter wants
                    //   if tree sitter says this node should render newlines, split out the newline node too
                    //   (we don't talk to tree-sitter directly, we use Measurer.syntaxHighlighter)
                    //   measure
                    // if the measurement
                    // save line height (= max height), linebaseline (= max baseline), and remainingItemsInLine
                }
                const measure = current.measure.?; // measured above already

                const cx = ri.x;
                ri.x += measure.width;
                ri.current = current.node().next();

                return .{ .x = cx, .y = ri.y + (ri.lineBaseline - measure.measure.baseline), .measure = measure };
            }
        };
        pub fn render(me: *EditorCore, width: i64, height: i64, deltaScroll: i64) RenderIterator {
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

                .code = startNode,
            };
        }

        pub fn deinit(me: *Core) void {
            me.measurer.deinit();
            var iter = me.code.iter();
            while (iter.next()) |itm| {
                itm.remove(me.alloc).deinit();
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
        pub fn render(me: *Measurer, text: []const u8, style: TextStyle, measure: Measurement) Text {
            if (me.someData != 5) unreachable;
            return .{ .txt = text };
        }
        pub fn measure(me: *Measurer, text: []const u8, style: TextStyle) Measurement {
            if (me.someData != 5) unreachable;
            var finalSize: usize = 0;
            for (text) |char| {
                finalSize += switch (char) {
                    'i' => 5,
                    'm' => 15,
                    else => 10,
                };
            }
            return .{
                .width = finalSize,
                .height = if (text.len > 0) 50 else 25,
                .baseline = 45,
            };
        }
        pub fn deinit(me: *Measurer) void {}
    };
    var core = try EditorCore(Measurer).init(alloc, Measurer{ .someData = 5 }); // , struct {fn measureText()} {};
    defer core.deinit();

    // std.testing.expectEqual(expected: var, actual: @TypeOf(expected))
}
