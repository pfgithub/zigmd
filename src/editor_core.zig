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
            // 1. update tree-sitter /
            // 2. remeasure? idk /
            // 3. â€™ /
            // also how to make sure eg cursor never has an invalid offset? idk. todo think. /

            // update all saved TextPoints at the updated point to the new point. /
            // maybe a fn to handle this? /
            if (me.cursor.text == point.text) {
                // depending on insert direction, choose > or >= /
                if (me.cursor.offset > point.offset) me.cursor.offset += point.offset;
            }
        }

        pub fn removeNodeText(me: *Core, node: *RangeList.Node, from: usize, to: usize) void {
            alRemoveRange(node.value.text, from, to);
            if (me.cursor.text == &node.value) {
                if (me.cursor.offset > to) me.cursor.offset -= to - from
                // zig fmt bug/
                else if (me.cursor.offset > from) me.cursor.offset = from;
            }
            if (node.value.text.items != 0) return;

            // first node:/
            if (me.code == node) {
                if (node.next == null) return;
                me.code = node.next.?;
            }
            if (me.cursor.text == &node.value) {
                if (node.next) |nxt| me.cursor = .{ .text = &nxt.value, .offset = 0 }
                // zig/
                else me.cursor = .{ .text = &node.previous.?.value, .offset = node.previous.?.value.text.items.len };
            }
            node.remove().deinit();
        }

        pub fn delete(me: *Core, from: TextPoint, to: TextPoint) void {
            // TODO: remove 0-length nodes unless the node is the/
            // start node and there is no next node./
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
            remainingItemsInLine: usize = 0,
            lineHeight: i64 = 0,
            lineBaseline: i64 = undefined,
            pub fn next(ri: *RenderIterator) ?struct { x: i64, y: i64, height: i64, measure: MeasurementData } {
                if (ri.y > ri.height) return null;
                if (ri.current == null) return null;

                const current = ri.current.?;

                if (ri.remainingItemsInLine == 0) {
                    ri.y += ri.lineHeight;
                    ri.lineHeight = undefined;
                    ri.lineBaseline = undefined;

                    // tree sitter get node () /
                    // if node.length > ts node.lengthUntilNewline
                    //    split node
                    // else if node.length < ts node.lengthUntilNewline
                    //    merge node /
                    // ts next node (or just next part after newline)

                    // loop over this line until reaching the end.
                    //   tree sitter get and split/merge this node into the nodes tree-sitter wants
                    //   if tree sitter says this node should render newlines, split out the newline node too
                    //   (we don't talk to tree-sitter directly, we use Measurer.syntaxHighlighter)
                    //   measure
                    // if the measurement
                    // save line height (= max height), linebaseline (= max baseline), and remainingItemsInLine /
                }
                const measure = current.measure.?; // measured above already

                const cx = ri.x;
                ri.x += measure.width;
                ri.current = current.node().next();

                return .{ .x = cx, .y = ri.y + (ri.lineBaseline - measure.measure.baseline), .measure = measure };
            }
        };
        pub fn render(me: *EditorCore, width: i64, height: i64, deltaScroll: i64) RenderIterator {
            return .{ .current = &me.code.value, .width = width, .height = height };
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
