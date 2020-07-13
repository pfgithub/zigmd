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
pub fn alRemoveRange(al: anytype, start: usize, end: usize) void {
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

// in the future, it will probably be a goal for editorcore
// to be able to be used with two different measurers at once
// using a wrapper that handles measurement or something.
// must have the same syntax highlighter though, given how
// it works.
// unless this is rethought and done better next time
pub fn EditorCore(comptime Measurer: type) type {
    return struct {
        const Core = @This();

        pub const CharacterMeasure = struct { width: i64 };
        pub const MeasurementData = struct {
            characters: std.ArrayList(CharacterMeasure),
            measure: Measurement,
            data: Measurer.Text, // measurer.render
            measurementVersion: u64,
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
            style: ?Measurer.Style,
            splitVersion: u64 = 0, // node must be split to have this changed

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
            pub fn len(me: *CodeText) usize {
                return me.text.items.len;
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

        measurementVersion: u64 = 0,
        splitVersion: u64 = 1,

        /// call this any time the output of findNextSplit might change on existing text
        /// called automatically when text is edited.
        pub fn markResplit(me: *Core) void {
            me.splitVersion += 1;
        }

        pub const TextPoint = struct { text: *CodeText, offset: u64 };

        /// use this eg if you are changing the font or syntax highlighter
        /// or something and all text needs remeasuring
        pub fn remeasureAll(me: *Core) void {
            me.measurementVersion += 1;
        }

        /// force remeasure a given node. use remeasureIfNeeded instead
        fn remeasureForce(me: *Core, text: *CodeText) !void {
            clearMeasure(text);
            if (text.style == null) unreachable; // splitNewlines was not called before remeasuring

            var charactersAl = std.ArrayList(CharacterMeasure).init(me.alloc);
            errdefer charactersAl.deinit();

            for (text.text.items) |_, i| {
                const progress: Measurement = try me.measurer.measure(text.text.items[0 .. i + 1], text.style.?);
                try charactersAl.append(.{ .width = progress.width });
            }

            const measurement = try me.measurer.measure(text.text.items, text.style.?);
            const data = try me.measurer.render(text.text.items, measurement, text.style.?);
            errdefer data.deinit();

            text.measure = .{
                .measure = measurement,
                .data = data,
                .characters = charactersAl,
                .measurementVersion = me.measurementVersion,
            };
        }
        /// after calling this function, text.measure is not null
        /// and up to date, unless this function returns an error.
        fn remeasureIfNeeded(me: *Core, text: *CodeText) !void {
            // when editing nodes, any affected will have measure reset to null
            if (text.measure) |measure| {
                if (measure.measurementVersion != me.measurementVersion) return me.remeasureForce(text);
            } else return me.remeasureForce(text);
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
                    .left => currentPoint.text.text.items.len - 1,
                    .right => 1,
                };
            }

            unreachable;
        }

        /// â€™
        pub fn insert(me: *Core, point: TextPoint, text: []const u8) !void {
            const startPointCopy = point; // because of zig, moving the cursor updates the immutable arg...
            defer {
                me.markResplit();
                // note the edit
                const fromPoint = me.startPosition().advanceToPoint(startPointCopy);
                const toPoint = fromPoint.advanceToPoint(me.addPoint(startPointCopy, @intCast(i64, text.len)));
                me.measurer.edit(fromPoint, fromPoint, toPoint);
            }

            try point.text.text.insertSlice(point.offset, text);
            if (text.len != 0) clearMeasure(point.text);

            if (me.cursor.text == point.text) {
                if (me.cursor.offset >= point.offset) me.cursor.offset += text.len;
                // instead of handling this manually here, why not handle it in an edit fn
                // like eg when something is edited, search within that range and move any
                // saved things like the cursor position or the scroll top or the highlight
                // range
            }
        }

        /// internal use only. DOES NOT note the edit. removes text in a node.
        fn removeNodeText(me: *Core, node: *RangeList.Node, from: usize, to: usize) void {
            alRemoveRange(&node.value.text, from, to);
            if (to - from != 0) clearMeasure(&node.value);

            if (me.cursor.text == &node.value) {
                if (me.cursor.offset > to) me.cursor.offset -= to - from
                //.
                else if (me.cursor.offset > from) me.cursor.offset = from;
            }
            if (node.value.text.items.len != 0) return;

            // node is empty. delete:

            if (me.code == node) {
                // first node:
                if (node.next == null) return;
                me.code = node.next.?;
            }
            if (me.cursor.text == &node.value) {
                if (node.next) |nxt| me.cursor = .{ .text = &nxt.value, .offset = 0 }
                //.
                else me.cursor = .{ .text = &node.previous.?.value, .offset = node.previous.?.value.text.items.len };
            }
            node.remove().deinit();
        }

        pub fn startPosition(me: *Core) CharacterPosition {
            return .{ .lyn = 0, .col = 0, .byte = 0, .ref = &me.code.value, .offset = 0 };
        }

        pub fn delete(me: *Core, from: TextPoint, to: TextPoint) void {
            const fromPoint = me.startPosition().advanceToPoint(from);
            const toPoint = fromPoint.advanceToPoint(to);
            defer {
                me.markResplit();
                // note the edit
                // is fromPoint still valid if from.text gets deleted because it's empty? no.
                // scary.
                me.measurer.edit(fromPoint, toPoint, fromPoint);
            }

            if (from.text == to.text) {
                me.removeNodeText(from.text.node(), from.offset, to.offset);
                return;
            }
            var currentText: ?*CodeText = from.text;
            while (currentText) |ctxt| {
                var next = ctxt.next();
                defer currentText = next;

                if (ctxt == from.text) {
                    me.removeNodeText(ctxt.node(), from.offset, ctxt.text.items.len);
                } else if (ctxt == to.text) {
                    me.removeNodeText(ctxt.node(), 0, to.offset);
                    break;
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
            var insertedNode = try point.text.node().insertAfter(.{ .text = al, .measure = null, .style = null });
            errdefer _ = insertedNode.remove();

            if (me.cursor.text == point.text and me.cursor.offset > point.text.len()) {
                me.cursor = .{
                    .text = &insertedNode.value,
                    .offset = me.cursor.offset - point.text.len(),
                };
            }
        }

        pub fn mergeNextNode(me: *Core, first: *CodeText) !void {
            if (first.node().next == null) return; // nothing to merge

            var next = &first.node().next.?.value;
            if (me.cursor.text == next) {
                me.cursor = .{
                    .text = first,
                    .offset = first.len() + me.cursor.offset,
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

        pub const CharacterPosition = struct {
            lyn: usize,
            col: usize,
            byte: usize,
            ref: *CodeText,
            offset: usize,
            pub fn format(me: CharacterPosition, comptime fmt: []const u8, options: std.fmt.FormatOptions, out: anytype) !void {
                return std.fmt.format(out, "{}:{}", .{ me.lyn, me.col });
            }
            pub fn char(me: CharacterPosition) ?u8 {
                var ref = me.ref;
                var offset = me.offset;
                while (offset >= ref.text.items.len) {
                    offset -= ref.text.items.len;
                    ref = ref.next() orelse return null; // eof
                }
                return ref.text.items[offset];
            }
            /// advance to the start of a text. unreachable if the point is behind me
            pub fn advanceTo(me: CharacterPosition, to: *CodeText) CharacterPosition {
                return me.advanceToPoint(.{ .text = to, .offset = 0 });
            }
            /// advance to a point. unreachable if the point is behind me
            pub fn advanceToPoint(me: CharacterPosition, to: TextPoint) CharacterPosition {
                var res = me;
                while (true) {
                    // instead of this, we have to advance until reaching res.ref == to.text and res.offset == to.offset
                    if (to.offset == res.offset and res.ref == to.text) {
                        return res;
                    }
                    for (res.ref.text.items[res.offset..]) |char_| {
                        res.byte += 1;
                        res.offset += 1;
                        if (char_ == '\n') {
                            res.col = 0;
                            res.lyn += 1;
                        } else {
                            res.col += 1;
                        }
                        if (res.ref == to.text and res.offset == to.offset) {
                            return res;
                        }
                    }
                    if (res.ref == to.text and res.offset > to.offset) unreachable; // to is in the past.
                    res.ref = res.ref.next() orelse unreachable; // to is in the past
                    res.offset = 0;
                }
            }
            // next character. null on eof
            pub fn next(me: CharacterPosition) ?CharacterPosition {
                // note that the newline character is the last character on a line>>
                var nxt: CharacterPosition = me;
                if (me.offset + 1 >= me.ref.text.items.len) {
                    nxt.offset = 0;
                    nxt.ref = me.ref.next() orelse return null;
                } else {
                    nxt.offset += 1;
                }
                if (me.char().? == '\n') {
                    nxt.lyn += 1;
                    nxt.col = 0;
                } else {
                    nxt.col += 1;
                }
                nxt.byte += 1;
                return nxt;
            }
            // previous character. null on first character.
            // note that previous character after a newline is slow
            pub fn prev(me: CharacterPosition) ?CharacterPosition {
                // prev is easy unless the previous character is a newline
                var nxt: CharacterPosition = undefined;
                if (me.offset == 0) {
                    nxt.ref = me.ref.prev() orelse return null; // eof
                    nxt.offset = nxt.ref.len() - 1;
                }
                nxt.lyn = me.lyn;
                if (pos.col == 0) blk: {
                    if (nxt.lyn == 0) unreachable; // already caught
                    nxt.lyn -= 1;
                    // go backwards until the previous newline or start of file
                    // set col appropriately
                    var pos = nxt;
                    pos.col = std.math.maxInt(usize);
                    while (true) {
                        pos = pos.prev() orelse unreachable;
                        // not allowed to recurse. note for 0.7.0
                        // first character already caught
                        if (pos.ref.text.items[pos.offset] == '\n') break;
                    }
                    nxt.col = std.math.maxInt(usize) - pos.col - 1;
                } else {
                    if (nxt.char() == '\n') unreachable;
                    nxt.col -= 1;
                }
            }
        };

        pub const NextSplit = struct {
            style: Measurer.Style,
            distance: usize,
        };

        pub fn splitNewlines(me: *Core, pos: CharacterPosition) !void {
            if (pos.offset != 0) unreachable; // not ok.
            const start = pos.ref;
            start.splitVersion = me.splitVersion;
            // getDistanceToNextSplit
            // split and merge until that is made
            // this is only necessary if text has been changed since the last frame
            const splitInfo = me.measurer.findNextSplit(pos);
            var distanceToNextSplit = splitInfo.distance;
            if (distanceToNextSplit == 0) unreachable; // distance should be >= 1.

            // if the style changed, clear the measurement
            if (pos.ref.style) |styl| {
                if (!splitInfo.style.eql(styl)) clearMeasure(pos.ref);
            } else clearMeasure(pos.ref);
            pos.ref.style = splitInfo.style;

            // distance to next split is eg min(end of tree-sitter node, a space, a newline)

            // find the next newline
            // split/merge until we get there
            // leave the newline/space in the same line
            var i: usize = 0;
            while (i <= start.text.items.len) : (i += 1) {
                if (distanceToNextSplit - i <= 0) {
                    try me.splitNode(.{ .text = start, .offset = i });
                    break;
                }
                if (i == start.text.items.len) {
                    try me.mergeNextNode(start);
                }
            }
            // either we broke from the loop or hit the end of the text. same thing.
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
            position: CharacterPosition,

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

                    if (text.splitVersion != ri.core.splitVersion) {
                        ri.position = ri.position.advanceTo(text);
                        try ri.core.splitNewlines(ri.position);
                    }
                    try ri.core.remeasureIfNeeded(text);

                    const measure = text.measure.?;
                    cx += measure.measure.width;

                    if (cx >= ri.width and resAL.items.len > 0) break;

                    lineBaseline = std.math.max(lineBaseline, measure.measure.baseline);
                    lineHeight = std.math.max(lineHeight, measure.measure.height);

                    try resAL.append(.{ .x = cx - measure.measure.width, .y = undefined, .measure = &text.measure.?, .text = text });
                    currentNode = node.next;

                    if (node.value.style.?.newlines and node.value.len() != 0 and node.value.text.items[node.value.len() - 1] == '\n') break; // oh god why eww
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
            return .{
                .current = &me.code.value,
                .width = width,
                .height = height,
                .core = me,
                .position = me.startPosition(),
            };
        }

        pub fn init(alloc: *Alloc, measurer: Measurer) !Core {
            var snal = std.ArrayList(u8).init(alloc);
            errdefer snal.deinit();
            const startNode = try RangeList.Node.create(
                alloc,
                .{ .text = snal, .measure = null, .style = null },
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

const TestingMeasurer = struct {
    const Measurer = @This();
    someData: u32,
    alloc: *std.mem.Allocator,

    const Style = struct {
        /// if a newline should be put
        newlines: bool,

        color: Colrenum,
        const Colrenum = enum { white, blue };

        pub fn eql(a: Style, b: Style) bool {
            return std.meta.eql(a, b);
        }
    };
    const Core = EditorCore(Measurer);

    pub const Text = struct {
        txt: []const u8,
        alloc: *std.mem.Allocator,
        pub fn deinit(me: *Text) void {
            me.alloc.free(me.txt);
        }
    };
    // can't be inline because of a zig compiler bug
    fn pickColor(colrenum: Style.Colrenum) []const u8 {
        return switch (colrenum) {
            .white => "\x1b[97m",
            .blue => "\x1b[96m",
        };
    }
    pub fn edit(
        me: *Measurer,
        start: Core.CharacterPosition,
        oldEnd: Core.CharacterPosition,
        newEnd: Core.CharacterPosition,
    ) void {
        std.debug.warn("Noted edit from [{}, {}] => [{}, {}]\n", .{ start, oldEnd, start, newEnd });
    }
    pub fn render(me: *Measurer, text: []const u8, mesur: Measurement, style: Style) !Text {
        if (me.someData != 5) unreachable;
        var txtCopy = std.ArrayList(u8).init(me.alloc);

        const strNormal = pickColor(style.color); //style.color);
        const strControl = "\x1b[36m";
        const strHidden = "\x1b[30m";
        try txtCopy.appendSlice(strNormal);
        for (text) |char| {
            // would prefer some kind of stream transformer so this could be used for measure
            switch (char) {
                '\n' => {
                    try txtCopy.appendSlice(strControl ++ "⌧ ");
                    try txtCopy.appendSlice(strNormal);
                },
                ' ' => {
                    try txtCopy.appendSlice(strHidden ++ "·");
                    try txtCopy.appendSlice(strNormal);
                },
                else => try txtCopy.append(char),
            }
        }
        try txtCopy.appendSlice("\x1B(B\x1B[m");
        return Text{ .txt = txtCopy.toOwnedSlice(), .alloc = me.alloc };
    }
    pub fn measure(me: *Measurer, text: []const u8, style: Style) !Measurement {
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
    pub fn findNextSplit(me: *Measurer, pos: Core.CharacterPosition) Core.NextSplit {
        // std.debug.warn("  - Finding split from {}\n", .{pos.byte});
        var style: Style = .{ .newlines = true, .color = undefined };
        switch (pos.char() orelse 0) {
            'A'...'Z' => style.color = .blue,
            else => style.color = .white,
        }

        var distance: usize = 1;

        // defer std.debug.warn("  - Found split at {} (byte {}).\n", .{ distance + 1, pos.byte + distance });
        var cpos = pos;
        while (cpos.char()) |chr| {
            if (chr == '\n') break; // character after the newline. would be useful to split both before and after.
            if (chr == ' ') break; // character after the space
            cpos = cpos.next() orelse break;
            distance += 1;
        }

        return .{
            .style = style,
            .distance = distance,
        };
    }
    pub fn deinit(me: *Measurer) void {}
};

pub fn tcflags(comptime itms: anytype) std.os.tcflag_t {
    comptime {
        var res: std.os.tcflag_t = 0;
        for (itms) |itm| res |= @as(std.os.tcflag_t, @field(std.os, @tagName(itm)));
        return res;
    }
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var core: EditorCore(TestingMeasurer) = try EditorCore(TestingMeasurer).init(alloc, TestingMeasurer{ .someData = 5, .alloc = alloc }); // , struct {fn measureText()} {};
    defer core.deinit();

    const stdin = std.io.getStdIn().inStream();
    const stdout = std.io.getStdIn().outStream();

    const origTermios = try std.os.tcgetattr(std.os.STDIN_FILENO);
    {
        var termios = origTermios;
        termios.lflag &= ~tcflags(.{ .ECHO, .ICANON, .ISIG, .IXON, .IEXTEN, .BRKINT, .INPCK, .ISTRIP, .CS8 });
        try std.os.tcsetattr(std.os.STDIN_FILENO, std.os.TCSA.FLUSH, termios);

        try stdout.writeAll("\x1b[?1049h\x1b[22;0;0t");
        try stdout.writeAll("\x1b[2J\x1b[H");
    }
    defer {
        std.os.tcsetattr(std.os.STDIN_FILENO, std.os.TCSA.FLUSH, origTermios) catch std.debug.warn("failed to reset termios on exit\n", .{});
        stdout.writeAll("\x1b[2J\x1b[H") catch std.debug.warn("could not clear screen before exit\n", .{});
        stdout.writeAll("\x1b[?1049l\x1b[23;0;0t") catch std.debug.warn("could not restore screen on exit\n", .{});
        std.debug.warn("Exited!\n", .{});
    }

    var autoRerender = false;

    while (true) {
        try stdout.writeAll("\x1b(B\x1b[m\x1b[2J\x1b[H");
        try stdout.print("Internal representation view. Rerender is {} (\x1b[94mctrl+d\x1b(B\x1b[m)\n", .{
            failPass(!autoRerender),
        });

        if (autoRerender) {
            var riter = core.render(100000, 100000, 0);
            while (try riter.next(alloc)) |*nxt| {
                defer nxt.deinit();
            }
        }

        renderCursorPositionOptions(core, .{ .cursor = .terminal_save });
        try stdout.writeAll("\x1b8");
        const rb = try stdin.readByte();
        switch (rb) {
            3 => break,
            4 => {
                autoRerender = !autoRerender;
            },
            '\x1b' => {
                switch (try stdin.readByte()) {
                    '[' => {
                        switch (try stdin.readByte()) {
                            '1'...'9' => |num| {
                                if ((try stdin.readByte()) != '~') std.debug.warn("Unknown escape 1-9 something\n", .{});
                                switch (num) {
                                    '3' => core.delete(core.cursor, core.addPoint(core.cursor, 1)),
                                    else => std.debug.warn("Unknown <esc>[#~ number {}\n", .{num}),
                                }
                            },
                            'A' => {},
                            'B' => {},
                            'C' => core.cursor = core.addPoint(core.cursor, 1),
                            'D' => core.cursor = core.addPoint(core.cursor, -1),
                            else => |chr| std.debug.warn("Unknown [ escape {c}\n", .{chr}),
                        }
                    },
                    else => |esch| std.debug.warn("Unknown Escape Type {}\n", .{esch}),
                }
            },
            10, 32...126 => {
                try core.insert(core.cursor, &[_]u8{rb});
            },
            127 => {
                core.delete(core.addPoint(core.cursor, -1), core.cursor);
            },
            else => {
                std.debug.warn("Control character {}\n", .{rb});
            },
        }
    }
}

test "editor core" {
    const alloc = std.testing.allocator;

    var core: EditorCore(TestingMeasurer) = try EditorCore(TestingMeasurer).init(alloc, TestingMeasurer{ .someData = 5, .alloc = alloc }); // , struct {fn measureText()} {};
    defer core.deinit();

    std.debug.warn("\n\n\n", .{});
    defer std.debug.warn("\n\n\n", .{});
    renderCursorPosition(core);

    try core.insert(core.cursor, "Hello, World! ");
    renderCursorPosition(core);
    try testRenderCore(&core, alloc, &[_][]const []const u8{
        &[_][]const u8{ "Hello, ", "World! " },
    });

    renderCursorPosition(core);

    try core.insert(core.cursor, "Oop!");
    renderCursorPosition(core);
    try testRenderCore(&core, alloc, &[_][]const []const u8{
        &[_][]const u8{ "Hello, ", "World! ", "Oop!" },
    });

    renderCursorPosition(core);

    try core.insert(core.cursor, "\nnewline");
    renderCursorPosition(core);
    try testRenderCore(&core, alloc, &[_][]const []const u8{
        &[_][]const u8{ "Hello, ", "World! ", "Oop!\n" },
        &[_][]const u8{"newline"},
    });
    // Hello, World!⌧newline

    renderCursorPosition(core);
    var i: usize = 0;
    // while (i < 12) : (i += 1) {
    //     core.cursor = core.addPoint(core.cursor, -1);
    //     renderCursorPosition(core);
    // }
    core.cursor = core.addPoint(core.cursor, -12);
    renderCursorPosition(core);

    try core.insert(core.cursor, "Fix this? ");
    renderCursorPosition(core);
    try testRenderCore(&core, alloc, &[_][]const []const u8{
        &[_][]const u8{ "Hello, ", "World! ", "Fix ", "this? ", "Oop!\n" },
        &[_][]const u8{"newline"},
    });

    renderCursorPosition(core);
    core.delete(core.addPoint(core.cursor, -15), core.cursor);
    renderCursorPosition(core);
    try testRenderCore(&core, alloc, &[_][]const []const u8{
        &[_][]const u8{ "Hello, ", "WoOop!\n" },
        &[_][]const u8{"newline"},
    });

    renderCursorPosition(core);
    // std.testing.expectEqual(expected: anytype, actual: @TypeOf(expected))
}

const CPOptions = struct {
    const CursorEnum = enum { drawn, terminal_save };
    cursor: CursorEnum = CursorEnum.drawn,
};

pub fn renderCursorPosition(core: anytype) void {
    return renderCursorPositionOptions(core, .{});
}
pub fn renderCursorPositionOptions(core: anytype, options: CPOptions) void {
    return renderPointPositionOptions(core, core.cursor, options);
}

pub fn renderPointPosition(core: anytype, point: anytype) void {
    return renderPointPositionOptions(core, point, .{});
}
pub fn renderPointPositionOptions(core: anytype, point: anytype, options: CPOptions) void {
    const reset = "\x1B(B\x1B[m";
    const cursor = switch (options.cursor) {
        .drawn => @as([]const u8, "\x1B[94m|" ++ reset),
        .terminal_save => "\x1b7",
    };
    const yellow = "\x1B[33m";
    std.debug.warn("Cursor:`", .{});
    defer std.debug.warn("`\n", .{});
    var cpos = &core.code.value;
    var first = true;
    var panic = false;
    while (true) {
        if (!first) std.debug.warn(" ", .{});
        if (first) first = false;

        const endWithNewline = cpos.len() > 0 and cpos.text.items[cpos.len() - 1] == '\n';
        defer if (endWithNewline) {
            std.debug.warn("\n", .{});
        };
        std.debug.warn(yellow ++ "[" ++ reset, .{});
        defer std.debug.warn(yellow ++ "]" ++ reset, .{});

        const cursorHere = point.text == cpos;
        for (cpos.text.items) |char, i| {
            if (cursorHere and i == point.offset) std.debug.warn("{}", .{cursor});
            switch (char) {
                '\n' => std.debug.warn("\x1b[32m\\n" ++ reset, .{}),
                else => std.debug.warn("{c}", .{char}),
            }
        }
        if (cursorHere and point.offset == cpos.text.items.len) std.debug.warn("{}", .{cursor});
        if (cursorHere and point.offset > cpos.text.items.len) {
            var offset = point.offset - cpos.text.items.len;
            while (offset > 0) : (offset -= 1) {
                std.debug.warn("\x1b[31m×\x1b[31m", .{});
            }
            std.debug.warn("{}", .{cursor});
            panic = true;
        }
        cpos = cpos.next() orelse break;
    }
    if (panic) unreachable; // cursor out of bounds
}

pub fn failPass(boole: bool) []const u8 {
    const reset = "\x1b(B\x1b[m";
    if (boole) return "\x1b[31m×" ++ reset;
    return "\x1b[32m√" ++ reset;
}

pub fn testRenderCore(core: anytype, alloc: anytype, expected: []const []const []const u8) !void {
    var gi: usize = 0;
    std.debug.warn("Testing\n", .{});
    var fail = false;

    var riter = core.render(1000, 500, 0);
    while (try riter.next(alloc)) |*nxt| : (gi += 1) {
        defer nxt.deinit();

        std.debug.warn("  Rendering line with height {}\n", .{nxt.lineHeight});

        for (nxt.pieces) |piece, i| {
            var pieceFailed = i >= expected[gi].len or !std.mem.eql(u8, expected[gi][i], piece.text.text.items);
            std.debug.warn(
                "    {} Piece x={}: `{}`\n",
                .{ failPass(pieceFailed), piece.x, piece.measure.data.txt },
            );
            if (pieceFailed) {
                fail = true;
                if (i >= expected[gi].len) std.debug.warn("    :: Out of bounds\n", .{}) else {
                    std.debug.warn("    :: Got     :  `{}`\n", .{piece.text.text.items});
                    std.debug.warn("    :: Expected:  `{}`\n", .{expected[gi][i]});
                }
            }
        }
        if (expected[gi].len != nxt.pieces.len) fail = true;
    }
    if (gi != expected.len) fail = true;
    std.debug.warn("Tested! ({})\n", .{failPass(fail)});
    if (fail) {
        return error.TestFailure;
    }
}
