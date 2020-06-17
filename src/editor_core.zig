const std = @import("std");
const Alloc = std.mem.Allocator;
const help = @import("helpers.zig");

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

pub const MeasureCache = struct {
    lineMeasurements: std.ArrayList(u1),

    pub fn init(alloc: *Alloc) MeasureCache {
        return .{
            .lineMeasurements = std.ArrayList(u1).init(alloc),
        };
    }
};

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

pub const EditorCore = struct {
    alloc: *Alloc,

    cursorPos: CursorPos,
    text: std.ArrayList(u8),
    undoStack: Stack(Action), // for undo. why is this even a stack, I'm using it like an arraylist
    undoPoint: usize,
    measureCache: MeasureCache,

    pub fn init(alloc: *Alloc) EditorCore {
        return .{
            .alloc = alloc,

            .cursorPos = .{ .byte = 0 },
            .text = std.ArrayList(u8).init(alloc),
            .measureCache = MeasureCache.init(alloc),
            .undoStack = Stack(Action).init(alloc),
            .undoPoint = 0,
        };
    }

    pub fn deinit(me: *EditorCore) void {
        me.text.deinit();
        for (me.undoStack.al.items) |*item| {
            item.deinit(me.alloc);
        }
        me.undoStack.deinit();
        me.* = undefined;
    }

    // calling this from within an action should add it as part of the action somehow idk
    // like some kind of tree of actions
    // so if you undo in one layer of action, it undoes on that layer
    // so that means it needs to be a stack of {thisAction: Action, subActions: Stack(@This())}
    // not yet though tbd.
    pub fn applyAction(me: *EditorCore, action: Action) !void {
        // if(action == .undo) ...
        // if(action == .redo) ...
        // some actions like insertText might want to merge with actions
        // before them if it has not been too much time.
        // consider?
        // these actions could adjust the previous item in the undostack:
        // move thisAction to the end of subActions,
        // set thisAction to action.
        try action.redo(me);
        {
            // why is there no built in c style for loop
            // who thought two indents was a good idea
            var i: usize = me.undoStack.al.items.len - me.undoPoint;
            while (i > 0) : (i -= 1) {
                me.undoStack.pop().?.deinit(me.alloc);
            }
        }
        try me.undoStack.push(action);
        me.undoPoint += 1;
    }
    pub fn undo(me: *EditorCore) !void {
        if (me.undoPoint == 0) return;
        me.undoPoint -= 1;
        try me.undoStack.al.items[me.undoPoint].undo(me);
    }
    pub fn redo(me: *EditorCore) !void {
        if (me.undoStack.al.items.len > me.undoPoint) {
            try me.undoStack.al.items[me.undoPoint].redo(me);
            me.undoPoint += 1;
        }
    }
};

test "editor core" {
    const alloc = std.testing.allocator;
    var core = EditorCore.init(alloc); // , struct {fn measureText()} {};
    defer core.deinit();

    help.expectEqualStrings(core.text.items, "");
    try core.applyAction(try Action.Insert.initCopy("Hi!", core.cursorPos, alloc));
    help.expectEqualStrings(core.text.items, "Hi!");
    try core.applyAction(try Action.Insert.initCopy("Interesting:?", core.cursorPos, alloc));
    help.expectEqualStrings(core.text.items, "Interesting:?Hi!");
    try core.undo();
    help.expectEqualStrings(core.text.items, "Hi!");
    try core.redo();
    help.expectEqualStrings(core.text.items, "Interesting:?Hi!");
    try core.redo();
    help.expectEqualStrings(core.text.items, "Interesting:?Hi!");
}
