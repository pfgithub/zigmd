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

pub const TextStyle = struct {};

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
        pub const CodeRange = union(enum) {
            text: struct {
                // node: *RangeList.Node?
                style: TextStyle,
                text: std.ArrayList(u8),
                // might need to include individual character sizes too
                // ^ do, not might.
                measure: ?struct {
                    characters: std.ArrayList(struct { width: i64 }),
                    measure: Measurement,
                    data: Measurer.Text, // measurer.render
                },
            },
            start,
        };
        pub const RangeList = LinkedList(CodeRange);

        alloc: *Alloc,
        measurer: Measurer,

        code: *RangeList.Node,

        cursor: TextPoint,
        pub const TextPoint = struct { node: *RangeList.Node, offset: u64 };

        pub fn insert(me: *Core, point: TextPoint, text: []const u8) !void {
            try point.value.text.text.insertSlice(point.offset, text);
            point.value.text.measure = null;
            // point.value.text
            // insert
            // update tree-sitter
            // â€™
        }
        // render
        // deltaScroll will scroll based on the current saved node to scroll based
        // on.
        // returns []{x: , y: , data: Measurer.Text}. free it yourself.
        pub fn render(width: i64, deltaScroll: i64) void {}

        pub fn init(alloc: *Alloc, measurer: Measurer) !Core {
            const startNode = try RangeList.Node.create(alloc, .start);
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
            if (iter.next().?.remove(me.alloc) != .start) unreachable;
            while (iter.next()) |itm| {
                itm.remove(me.alloc).text.data.deinit();
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
                .height = 50,
                .baseline = 45,
            };
        }
        pub fn deinit(me: *Measurer) void {}
    };
    var core = try EditorCore(Measurer).init(alloc, Measurer{ .someData = 5 }); // , struct {fn measureText()} {};
    defer core.deinit();

    // std.testing.expectEqual(expected: var, actual: @TypeOf(expected))
}
