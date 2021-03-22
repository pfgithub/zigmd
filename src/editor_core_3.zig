const std = @import("std");

fn oom() void {
    @panic("oom");
}

// stores text
const EditorCore = struct {
    const Point = struct {
        lyn: usize,
        col: usize,
        byt: usize,
    };
    const Mark = struct {
        start: Point,
        end: Point,
        point: Point,
        kind: enum { cursor },
    };
    lines: std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8)),
    alloc: *std.mem.Allocator,
    marks: std.ArrayListUnmanaged(Mark),
    pub fn init(alloc: *std.mem.Allocator) EditorCore {
        var lines = std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8)){};
        errdefer lines.deinit(alloc);

        var marks = std.ArrayListUnmanaged(Mark){};
        errdefer marks.deinit(alloc);

        const zero_pt = Point{ .lyn = 0, .col = 0, .byt = 0 };
        marks.append(alloc, .{ .start = zero_pt, .end = zero_pt, .point = zero_pt, .kind = .cursor }) catch oom();

        return EditorCore{
            .lines = lines,
            .marks = marks,
            .alloc = alloc,
        };
    }
    pub fn deinit(core: *EditorCore, alloc: *std.mem.Allocator) void {
        for (core.lines.items) |line| line.deinit(core.alloc);
        core.lines.deinit(core.alloc);
        core.marks.deinit(core.alloc);
        core.* = undefined;
    }
    pub fn replaceRange(core: *EditorCore, start: Point, end: Point, text: []const u8) void {
        var current: Point = start;
        var text_pos: usize = 0;
        while (current.byt < end.byt) {
            const this_line = &core.lines.items[current.lyn];
            const remaining_text = text[text_pos..];
            const text_until_newline = remaining_text[0 .. std.mem.indexOf(u8, remaining_text, "\n") orelse remaining_text.len];
            this_line.replaceRange(current.col, this_line.items.len - current.col, text_until_newline);
            text_pos += text_until_newline.len + 1;
            if (text_pos > text.len) text_pos = text.len;
            // TODO update text_pos
        }
        if (text_pos < text.len) {
            // TODO insert new lines to reach this point
            // uuh that's complicated oops
            // what I need to do is in the while loop, check if this is the last item
            // if it is, then do stuff I guess
            // or instead of this I can cheat and use []u8 instead of [][]u8 for now
        }

        // 1: delete range
        // 2: insert
        // 3: update marks
    }
};

// caches render information for lines
// regenerates when the line is edited
// also determines where stuff is and measures and stuff
const RenderHelper = struct {};
