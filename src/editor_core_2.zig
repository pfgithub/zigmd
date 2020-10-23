// https://code.visualstudio.com/blogs/2018/03/23/text-buffer-reimplementation

const std = @import("std");
const header_match = @import("header_match.zig");

test "demo tree" {
    const Data = struct {
        const Data = @This();
        number: usize,
        pub fn deinit(data: *Data) void {}
    };
    const ComputedProperty = struct {
        const ComputedProperty = @This();
        index: usize,
        total: usize,
        pub const zero = ComputedProperty{ .index = 0, .total = 0 };
        pub fn compute(data: Data) ComputedProperty {
            return .{ .index = 1, .total = data.number + 1 };
        }
        pub fn add(lhs: ComputedProperty, rhs: ComputedProperty) ComputedProperty {
            return .{ .index = lhs.index + rhs.index, .total = lhs.total + rhs.total };
        }
        pub fn sub(lhs: ComputedProperty, rhs: ComputedProperty) ComputedProperty {
            return .{ .index = lhs.index - rhs.index, .total = lhs.total - rhs.total };
        }
    };
    const Tree = CreateTree(Data, ComputedProperty);
    const alloc = std.testing.allocator;

    var header = try Tree.Header.create(alloc);
    defer header.destroy();
    header.setChildNode(try header.createNode(.{ .number = 25 }));

    std.testing.expectEqual(ComputedProperty{ .index = 1, .total = 26 }, header.total());

    const findIndexEqual = struct {
        fn imfn(value: ComputedProperty, expected: usize) Tree.Compare {
            // std.debug.warn("Index: {}, Data: {}\n", .{ value.index, expected });
            if (expected < value.index) return .left;
            if (expected > value.index) return .right;
            return .equal;
        }
    }.imfn;

    printTree(header);

    if (header.find(findIndexEqual, 0)) |found| std.testing.expect(25 == found.data.number) else @panic("Did not find");
    if (header.find(findIndexEqual, 1)) |_| @panic("Was supposed to not find");

    {
        const new_node = try header.createNode(.{ .number = 15 });
        (header.find(findIndexEqual, 0) orelse @panic("Did not find")).insert(.left, new_node);
    }

    printTree(header);

    {
        const new_node = try header.createNode(.{ .number = 35 });
        const found_node = header.find(findIndexEqual, 1) orelse @panic("Did not find");
        found_node.insert(.right, new_node);
    }

    printTree(header);

    if (header.find(findIndexEqual, 0)) |found| std.testing.expect(15 == found.data.number) else @panic("Did not find");
    if (header.find(findIndexEqual, 1)) |found| std.testing.expect(25 == found.data.number) else @panic("Did not find");
    if (header.find(findIndexEqual, 2)) |found| std.testing.expect(35 == found.data.number) else @panic("Did not find");
    if (header.find(findIndexEqual, 3)) |_| @panic("Was supposed to not find");

    printTreeRecursive(header);

    // balancing test

    const node_count_to_add = 1_000; // 100_000 takes too long to insert. I should profile this and see if it's memory allocation or if it's a real issue
    var timer = std.time.Timer.start() catch @panic("bad");
    for (range(node_count_to_add)) |_, i| {
        const new_node = try header.createNode(.{ .number = i });
        (header.find(findIndexEqual, i) orelse @panic("Did not find")).insert(.left, new_node);
        if (header.find(findIndexEqual, i)) |found| std.testing.expect(i == found.data.number) else @panic("Did not find");

        if (i % 100_000 == 0) {
            const time = timer.read();
            std.debug.warn("{},{d:.6}\n", .{ i, @intToFloat(f64, time) / std.time.ns_per_ms / 10_000 });
            timer.reset();
        }
    }
    // the time it takes to insert things seems to grow linearly when it should grow not linearly

    std.debug.warn("done inserting\n", .{});

    for (range(node_count_to_add)) |_, i| {
        if (header.find(findIndexEqual, i)) |found| std.testing.expect(i == found.data.number) else @panic("Did not find");
    }

    std.debug.warn("done comparing\n", .{});

    const array_len = node_count_to_add + 3;
    std.testing.expect(header.total().index == array_len);

    const expected_height = std.math.log2_int(usize, array_len) + 3;
    std.debug.warn("array len is: {}\n", .{array_len});
    std.debug.warn("expected height is: {}\n", .{expected_height});
    std.testing.expect(header.treetop.?.height <= expected_height);

    for (range(node_count_to_add)) |_, i| {
        (header.find(findIndexEqual, node_count_to_add - i - 1) orelse @panic("Did not find")).unseat().destroySelf(header.alloc);
    }
    printTree(header);
    // printTree(header);
    // printTreeRecursive(header);

    if (header.find(findIndexEqual, 0)) |found| std.testing.expect(15 == found.data.number) else @panic("Did not find");
    if (header.find(findIndexEqual, 1)) |found| std.testing.expect(25 == found.data.number) else @panic("Did not find");
    if (header.find(findIndexEqual, 2)) |found| std.testing.expect(35 == found.data.number) else @panic("Did not find");
    if (header.find(findIndexEqual, 3)) |_| @panic("Was supposed to not find");
}

fn range(max: usize) []const void {
    return @as([]const void, &[_]void{}).ptr[0..max];
}

fn printTreeRecursive(header: anytype) void {
    std.debug.warn("Depth: {}, Tree: ", .{header.treetop.?.height});
    printTreeRecursiveInternal(header.treetop.?);
    std.debug.warn("\n", .{});
}

fn printTreeRecursiveInternal(node: anytype) void {
    std.debug.warn("[", .{});
    if (node.left) |left| printTreeRecursiveInternal(left) //
    else std.debug.warn("∅", .{});
    std.debug.warn(", {}, ", .{node.data.number});
    if (node.right) |right| printTreeRecursiveInternal(right) //
    else std.debug.warn("∅", .{});
    std.debug.warn("]", .{});
}

fn printTree(header: anytype) void {
    std.debug.warn("Printing Tree!\n", .{});
    std.debug.warn("Tree: […]", .{});
    // a real iterator would keep track of the absolute value for you rather
    // than requiring a worst case O(log n) for each item in the list
    var iter = header.firstNode() orelse @panic("No start node");
    std.debug.warn("\x1b[D\x1b[D", .{});
    var first = true;
    var i: usize = 0;
    while (true) {
        iter.validate();
        if (!first) std.debug.warn("\x1b[K", .{});
        first = false;
        if (iter.computeAbsolute().index != i) @panic("Index mismatch");
        std.debug.warn("{}, …]\x1b[D\x1b[D", .{iter.data.number});
        iter = iter.next() orelse break;
        i += 1;
    }
    std.debug.warn("\x1b[D\x1b[D\x1b[K]\n", .{});
}

// must be defined out here to avoid shadowing rules
// also it makes more sense for it to be defined out here
// imo decl shadowing should just require qualified access
// eg Direction.next instead of next if there are two possible
// decls that could be accessed with the same name
const Direction = enum(u1) {
    left,
    right,
    const all = [_]Direction{ .left, .right };
    fn next(comptime dir: Direction) Direction {
        comptime return switch (dir) {
            .left => .right,
            .right => .left,
        };
    }
    fn name(comptime dir: Direction) []const u8 {
        comptime return @tagName(dir);
    }
};

const ComputedPropertyHeader = struct {
    pub const __h_ALLOW_EXTRA: void = {};
    pub const zero: ComputedPropertyHeader = undefined;
    pub fn add(lhs: ComputedPropertyHeader, rhs: ComputedPropertyHeader) ComputedPropertyHeader {
        return undefined;
    }
    pub fn sub(lhs: ComputedPropertyHeader, rhs: ComputedPropertyHeader) ComputedPropertyHeader {
        return undefined;
    }
    pub fn compute(data: DataHeader) ComputedPropertyHeader {
        return undefined;
    }
};
const DataHeader = struct {
    pub const __h_ALLOW_EXTRA: void = {};
    pub fn deinit(me: *DataHeader) void {}
};

// note the avl balancing is not correct

/// an avl auto-balancing binary tree
///
/// Data must match DataHeader, ComputedProperty must match ComputedPropertyHeader
fn CreateTree(comptime Data: type, comptime ComputedProperty: type) type {
    // Unreachable at /deps/zig/src/stage1/analyze.cpp:6004 in type_requires_comptime.
    // uncomment this to check if types match eachother, recomment after that error.
    // {
    //     @setEvalBranchQuota(5000);
    //     header_match.conformsTo(ComputedPropertyHeader, ComputedProperty);
    //     header_match.conformsTo(DataHeader, Data);
    // }
    return struct {
        const Node = @This();
        const Parent = union(enum) {
            none,
            header: *Header,
            node: *Node,
            pub fn as(value: Parent, comptime tag: @TagType(Parent)) ?std.meta.fieldInfo(Parent, @tagName(tag)).field_type {
                comptime const Expres = std.meta.fieldInfo(Parent, @tagName(tag)).field_type;
                switch (value) {
                    @field(Parent, @tagName(tag)) => return @as(Expres, @field(value, @tagName(tag))),
                    else => return @as(?Expres, null),
                }
            }
            pub fn replaceChild(parent: Parent, prev_child: *Node, new_child: ?*Node) void {
                if (new_child) |newch| if (newch.parent != .none) unreachable; // expected unseated new_child
                // subtract prev child value so it can be unlinked without issues
                prev_child.propagate(.sub, prev_child.total());
                // link parent ⭤ new_child
                switch (parent) {
                    .none => {},
                    .header => |header| {
                        if (header.treetop != prev_child) unreachable;
                        header.treetop = null;
                        header.setChildNode(new_child);
                    },
                    .node => |pnode| {
                        if (pnode.left == prev_child) {
                            pnode.left = null;
                            pnode.insertInternal(.left, new_child);
                        } else if (pnode.right == prev_child) {
                            pnode.right = null;
                            pnode.insertInternal(.right, new_child);
                        } else unreachable; // broken node oops
                    },
                }
                // disconnect prev_child → parent
                prev_child.parent = .none;
            }
        };
        // would be nice if ends could have empty "node slots" rather than being null. I guess I can do union(enum) rather than ?*Node for that.
        // mostly so you could do node.left.fill(…) eg
        parent: Parent = .none,
        left: ?*Node = null,
        right: ?*Node = null,
        left_computed: ComputedProperty = ComputedProperty.zero,
        height: isize = 1, // = max(left.height, right.height)
        data: Data,

        const Header = struct {
            treetop: ?*Node = null,
            alloc: *std.mem.Allocator,

            pub fn create(alloc: *std.mem.Allocator) !*Header {
                const header = try alloc.create(Header);
                header.* = .{ .alloc = alloc };
                return header;
            }
            pub fn destroy(header: *Header) void {
                if (header.treetop) |top| top.unseatTree().destroySubtree(header.alloc);

                const ha = header.alloc;
                ha.destroy(header);
            }
            pub fn createNode(header: *Header, data: Data) !*Node {
                return Node.create(header.alloc, data);
            }
            pub fn setChildNode(header: *Header, child_node: ?*Node) void {
                if (header.treetop != null) unreachable; // this function can only be used if the header has no child node
                header.treetop = child_node;
                if (child_node) |chn| chn.parent = .{ .header = header };
            }
            pub fn total(header: *const Header) ComputedProperty {
                return if (header.treetop) |top| top.total() else ComputedProperty.zero;
            }
            pub fn find(header: *const Header, comptime findfn: anytype, data: FindFnDataArg(findfn)) ?*Node {
                if (header.treetop) |top| return top.find(ComputedProperty.zero, findfn, data) //
                else return null;
            }
            pub fn firstNode(header: *Header) ?*Node {
                if (header.treetop) |top| return top.firstNode() //
                else return null;
            }
            pub fn lastNode(header: *Header) ?*Node {
                if (header.treetop) |top| return top.lastNode() //
                else return null;
            }
        };

        const Compare = enum { left, right, equal };
        fn FindFnDataArg(comptime findfn: anytype) type {
            // header match fn(a: computed, data: header_match.any) Compare {return undefined}
            return @typeInfo(@TypeOf(findfn)).Fn.args[1].arg_type.?;
        }

        /// node.find(ComputedProperty.zero,
        ///     fn(v: ComputedProperty, data: usize) Tree.Compare {
        ///         if (lhs.index < rhs.index) return .lt;
        ///         if (lhs.index > rhs.index) return .gt;
        ///         return .eq;
        ///     }, 1);
        ///
        /// note that the type of the second arg to the find function is used as the third arg in find
        pub fn find(node: *Node, base: ComputedProperty, comptime findfn: anytype, data: FindFnDataArg(findfn)) ?*Node {
            // eg to find the node with index: 1
            // check base + lhs_computed
            // if <, enter lhs
            // if =, return node
            // if >, enter rhs + ComputedProperty.copute(node.data)
            const computed = base.add(node.left_computed);
            switch (findfn(computed, data)) {
                .left => if (node.left) |left| {
                    // TODO this should be able to tail but f
                    // return @call(.{ .modifier = .always_tail }, find, .{ node, base, findfn, data });
                    return find(left, base, findfn, data);
                } else return null,
                .equal => return node,
                .right => if (node.right) |right| {
                    // return @call(.{ .modifier = .always_tail }, find, .{ node, computed, findfn, data });
                    return find(right, computed.add(ComputedProperty.compute(node.data)), findfn, data);
                } else return null,
            }
        }

        /// set the data of this node
        fn setData(node: *Node, data: Data) void {
            node.propagate(.sub, ComputedProperty.compute(node.data));
            node.data = data;
            node.propagate(.add, ComputedProperty.compute(node.data));
        }

        /// create a new node. insert this into a tree with node.insert(.left/right, newnode)
        fn create(alloc: *std.mem.Allocator, data: Data) !*Node {
            const mem = try alloc.create(Node);
            mem.* = .{
                .data = data,
            };
            return mem;
        }

        const AddSub = enum { add, sub };
        /// propagate a change in size up from this node to parent nodes' left_computed field (if applicable)
        fn propagate(start: *Node, comptime add_sub: AddSub, total_: ComputedProperty) void {
            var current: *Node = start;
            while (true) {
                const parent = current.parent.as(.node) orelse break;
                defer current = parent;
                if (current == parent.right) continue; // I think
                if (current != parent.left) unreachable;

                parent.left_computed = switch (add_sub) {
                    .add => parent.left_computed.add(total_),
                    .sub => parent.left_computed.sub(total_),
                };
            }
        }

        /// free this single node. it must have no children and be unseated (no parent)
        fn destroySelf(node: *Node, alloc: *std.mem.Allocator) void {
            if (node.parent != .none) unreachable; // Node must be unseated before destroying
            if (node.left) |left| unreachable;
            if (node.right) |right| unreachable;
            node.data.deinit();
            alloc.destroy(node);
        }

        /// free this tree. it must be unseated (no parent)
        fn destroySubtree(node: *Node, alloc: *std.mem.Allocator) void {
            if (node.left) |left| left.unseatTree().destroySubtree(alloc);
            if (node.right) |right| right.unseatTree().destroySubtree(alloc);
            node.destroySelf(alloc);
        }

        /// compute the total computed property of this tree. O(log n)
        fn total(node: *const Node) ComputedProperty {
            var total_ = ComputedProperty.zero; // wow these shadowing rules are bad
            var deepest_right: ?*const Node = node;
            while (deepest_right) |right| {
                total_ = total_.add(right.left_computed).add(ComputedProperty.compute(right.data));
                deepest_right = right.right;
            }
            return total_;
        }

        /// compute the absolute property before this node
        fn computeAbsolute(node: *const Node) ComputedProperty {
            var current = node.left_computed;
            var highest = node;
            while (true) {
                const parent = highest.parent.as(.node) orelse break;
                defer highest = parent;
                if (highest == parent.right) current = current.add(parent.left_computed).add(ComputedProperty.compute(parent.data)) //
                else if (highest == parent.left) {} //
                else unreachable;
            }
            return current;
        }

        /// unseat this tree to move it elsewhere
        fn unseatTree(node: *Node) *Node {
            return node.unseatSwap(null);
        }

        /// unseat this tree and put replacement in its place
        fn unseatSwap(node: *Node, replacement: ?*Node) *Node {
            if (replacement) |r| if (r.parent != .none) unreachable; // replacement node must be unseated
            // connect parent ↔ replacement and disconnect node from parent
            node.parent.replaceChild(node, replacement);
            return node;
        }

        /// unlink this node and link replacement in its place, without modifying the rest of the tree
        fn unseatSwapOne(node: *Node, replacement: *Node) *Node {
            const left = if (node.left) |left| left.unseatSwap(null) else null;
            const right = if (node.right) |right| right.unseatSwap(null) else null;
            replacement.insertInternal(.left, left);
            replacement.insertInternal(.right, right);
            node.parent.replaceChild(node, replacement);
            return node;
        }

        /// unseat this node and reconfigure the tree to still be valid
        fn unseat(node: *Node) *Node {
            if (node.left != null and node.right != null) {
                const next_ = node.next() orelse unreachable;
                if (next_.right) |right| {
                    return node.unseatSwapOne(next_.unseatSwap(right.unseatTree()));
                } else {
                    return node.unseatSwapOne(next_.unseatTree());
                }
            } else {
                const not_null_node = if (node.left) |n| n.unseatTree() else if (node.right) |r| r.unseatTree() else null;
                return node.unseatSwap(not_null_node);
            }
        }

        /// rotate node in the specified direction. must have a child node
        /// in the opposite of direction.
        fn rotate(node: *Node, comptime direction: Direction) void {
            // code written for right rotation
            comptime const right = direction;
            comptime const left = direction.next();

            //   node    |  node               |   x_tree           |  x_tree            |  x_tree      //
            //    …      |  …                  |    …               |    …               |    …         //
            //     \     |   \       x_tree    |     \      y_tree  |     \       t2     |     \        //
            //      y    |    y                |      x             |      x             |      x       //
            //     / \   |     \        x      |     / \       y    |     / \       T2   |     / \      //
            //    x  T3  →     T3  ,   / \     →    T1 T2  ,    \   →    T1  y  ,        →    T1  y     //
            //   / \     |            T1 T2    |                T3  |         \          |       / \    //
            //  T1 T2    |                     |                    |          T3        |      T2  T3  //

            if (node.c(left) == null) unreachable; // this operation is not allowed without a vaild tree to operate on
            const x_tree = node.c(left).?.unseatTree();
            const y_tree = node.unseatSwap(x_tree);
            const t2 = x_tree.swapChild(right, y_tree);
            y_tree.insertInternal(left, t2);
        }

        fn updateHeight(node: *Node) void {
            var current = node;
            while (true) {
                current.height = std.math.max(if (current.left) |l| l.height else 0, if (current.right) |r| r.height else 0) + 1;
                current = current.parent.as(.node) orelse break;
            }
        }

        fn swapChild(parent: *Node, comptime direction: Direction, new: ?*Node) ?*Node {
            comptime const right = direction;
            if (parent.c(right)) |right_child| {
                return right_child.unseatSwap(new);
            } else {
                parent.insertInternal(right, new);
                return null;
            }
        }

        /// set node.[direction] to new and propagate compute and update height
        fn insertInternal(parent: *Node, comptime direction: Direction, new: ?*Node) void {
            // code written for setting left field
            comptime const left = direction;

            if (parent.c(left) != null) unreachable; // error, trying to overwrite an existing tree. use unseatSwap instead.
            parent.s(left).* = new;

            if (new) |nw| {
                if (nw.parent != .none) unreachable; // new node is already parented. it must be unseated before insertion.

                nw.parent = .{ .node = parent };
                nw.propagate(.add, nw.total());
            }
            parent.updateHeight();
        }

        // insert new to the left or right of this node.
        // what's fun is you can even insert while an iterator is running. neat.
        fn insert(parent: *Node, comptime direction: Direction, new: *Node) void {
            comptime const left = direction;
            if (new.left != null or new.right != null) unreachable; // new node is not an orphan

            if (parent.c(left)) |prev_left| {
                const old_left = prev_left.unseatSwap(new);
                new.insertInternal(left, old_left);
            } else {
                parent.insertInternal(left, new);
            }

            var current = parent;
            while (true) {
                const bal_fac = (if (current.left) |l| l.height else 0) - (if (current.right) |r| r.height else 0);
                if (bal_fac > 0) {
                    // left left or left right
                    // std.debug.warn("rotate ←.\n", .{});
                    current.rotate(.right); // should rotate be called on the pivot rather than here? maybe idk
                    current = current.parent.as(.node) orelse break;
                } else if (bal_fac < 0) {
                    // right right or right left
                    // std.debug.warn("rotate →.\n", .{});
                    // To check whether it is left left case or not, compare the newly inserted key with the key in left subtree root.
                    // uuh?? I don't have that
                    current.rotate(.left);
                    current = current.parent.as(.node) orelse break;
                }
                current = current.parent.as(.node) orelse break;
            }

            // go up until the first unbalanced node
            // rotate
            // oh it looks like node heights have to be stored
            // I'll store it with the other computed properties so it just auto updates when using the placement primitives (unseatSwap and insertInternal)
        }

        fn edge(node: *Node, comptime direction: Direction) *Node {
            comptime const left = direction;

            var deepest = node.c(left) orelse return node;
            while (true) deepest = deepest.c(left) orelse return deepest;
        }
        fn firstNode(node: *Node) *Node {
            return node.edge(.left);
        }
        fn lastNode(node: *Node) *Node {
            return node.edge(.right);
        }

        fn validateChild(node: *Node, comptime direction: Direction) void {
            comptime const left = direction;

            if (node.c(left)) |left_child| {
                switch (left_child.parent) {
                    .none => unreachable, // error: child does not have parent
                    .header => unreachable, // error: child's parent is header when it should be node
                    .node => |child_parent| if (child_parent != node) unreachable, // error: child's parent is the wrong onde
                }
            }
        }

        /// assert that connections are ok
        fn validate(node: *Node) void {
            // inline for is crashing f
            node.validateChild(.left);
            node.validateChild(.right);
            switch (node.parent) {
                .none => {}, // OK
                .header => |header| if (header.treetop != node) unreachable, // error: header's child is not this node
                .node => |parent_node| if (parent_node.left != node and parent_node.right != node) unreachable, // error: neither of this node's parent's children are this node
            }
            // TODO confirm left_comptued == left.total()?
        }

        /// sequential node left or right
        fn sequential(node: *Node, comptime direction: Direction) ?*Node {
            comptime const right = direction;
            comptime const left = direction.next();

            var deepest = node.c(right) orelse {
                // go up to the nearest parent where this is the left child
                var deepest = node;
                while (deepest.parent.as(.node)) |parent| {
                    if (parent.c(left) == deepest) return parent;
                    if (parent.c(right) == deepest) {
                        deepest = parent;
                        continue;
                    }
                    unreachable; // bad tree
                }
                return null;
            };
            while (true) deepest = deepest.c(left) orelse return deepest;
        }

        /// sequential next line
        fn next(node: *Node) ?*Node {
            return sequential(node, .right);
        }
        /// sequential previous line
        fn prev(node: *Node) ?*Node {
            return sequential(node, .left);
        }

        fn c(node: *Node, comptime direction: Direction) ?*Node {
            return node.s(direction).*;
        }
        fn s(node: *Node, comptime direction: Direction) *?*Node {
            switch (direction) {
                .left => return &node.left,
                .right => return &node.right,
            }
        }

        // fn replaceRange(start: usize, end: usize, text: []const u8)
        //   update parent
    };
}

const TextBuffer = struct {
    const Line = struct {
        id: usize,
        update: usize = 0,
        text: std.ArrayList(u8),
    };
    // TODO this could be made generic if there were "computed properties"
    const Node = struct {
        fn print(node: Node, os: anytype) @TypeOf(os).Error!void {
            if (node.left) |left| try node.left.print(os);
            try os.writeAll(line);
            try os.writeAll("\n");
            if (node.right) |right| try node.right.print(os);
        }
    };
    const IDCount = struct {
        id: usize = 0,
        fn next(idc: *IDCount) usize {
            idc.id += 1;
            return idc.id;
        }
    };

    lines: ?*Node,
    alloc: *std.mem.Allocator,
    id: IDCount,

    pub fn init(alloc: *std.mem.Allocator) TextBuffer {
        var idc: IDCount = .{};
        const top_node = alloc.create(Node) catch @panic("oom");
        top_node.initialize(null, &idc);
        return .{
            .lines = top_node,
            .alloc = alloc,
            .id = idc,
        };
    }

    fn print(tb: *const TextBuffer, os: anytype) !void {
        if (tb.lines) |lines| try lines.print(os);
    }

    fn readRangeAlloc(tb: *TextBuffer, start: RowCol, end: RowCol, alloc: *std.mem.Allocator) []const u8 {}

    fn replaceRange(tb: *TextBuffer, start: RowCol, end: RowCol, text: []const u8) void {
        // search tree to find start line
        // search tree to find end line
        // delete any nodes between the two
    }
};

test "" {
    // const alloc = std.testing.allocator;
    // const tb = TextBuffer.init(alloc);
    // tb.replaceRange(.{ .lyn = 0, .col = 0 }, .{ .lyn = 0, .col = 0 }, "Hello!");
}
