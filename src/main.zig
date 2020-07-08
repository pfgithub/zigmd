const std = @import("std");
pub const win = @import("./render.zig");
pub const parser = @import("./parser.zig");
pub const gui = @import("./gui.zig");
const help = @import("./helpers.zig");
const editor_core = @import("./editor_core.zig");
const EditorCore = editor_core.EditorCore;
const Measurement = editor_core.Measurement;
const List = std.SinglyLinkedList;
const ArrayList = std.ArrayList;
const Auto = gui.Auto;
const ImEvent = gui.ImEvent;

pub const DefaultMeasurer = struct {
    const Me = @This();

    style: *const gui.Style = undefined,
    imev: *ImEvent = undefined,

    pub const Text = win.Text;
    pub const Style = struct {
        pub fn eql(a: Style, b: Style) bool {
            return std.meta.eql(a, b);
        }
    };

    pub fn findNextSplit(me: *Me, pos: var) EditorCore(Me).NextSplit {
        var distance: usize = 1;
        var cpos = pos;
        while (cpos.char()) |chr| {
            if (chr == '\n') break; // character after the newline. would be useful to split both before and after.
            if (chr == ' ') break; // character after the space
            cpos = cpos.next() orelse break;
            distance += 1;
        }
        return .{ .distance = distance, .style = .{} };
    }
    pub fn render(dm: *Me, text: []const u8, measur: Measurement) !Text {
        if (text.len == 0) return @as(Text, undefined);

        return try win.Text.init(
            dm.style.fonts.standard,
            dm.style.colors.text,
            text,
            win.TextSize{ .w = measur.width, .h = measur.height },
            dm.imev.window,
        );
    }
    pub fn measure(dm: *Me, text: []const u8) !Measurement {
        if (text.len == 0) return Measurement{ .width = 0, .height = 10, .baseline = 0 };

        const msurment = try win.Text.measure(dm.style.fonts.standard, text);
        return Measurement{
            .width = msurment.w,
            .height = msurment.h,
            .baseline = msurment.h,
        };
    }

    pub fn deinit(dm: *Me) void {}
};
pub const MultilineTextEditor = struct {
    const Me = @This();

    core: EditorCore(DefaultMeasurer),
    alloc: *std.mem.Allocator,
    id: gui.ID,

    pub fn init(alloc: *std.mem.Allocator, imev: *ImEvent) !MultilineTextEditor {
        var core = try EditorCore(DefaultMeasurer).init(alloc, .{});
        errdefer core.deinit();

        var file: []u8 = std.fs.cwd().readFileAlloc(imev.alloc, "tests/medium sized file.md", 10000000) catch |e| blk: {
            core.readonly = true;
            break :blk try std.fmt.allocPrint(imev.alloc, "File load error: {}.", .{e});
        };
        defer imev.alloc.free(file);

        try core.insert(core.cursor, file);

        return MultilineTextEditor{
            .core = core,
            .alloc = alloc,
            .id = imev.newID(),
        };
    }
    pub fn deinit(te: *Me) void {
        te.core.deinit();
    }

    pub fn render(te: *Me, fullRect: win.Rect, imev: *ImEvent, style: gui.Style) !void {
        try imev.window.pushClipRect(fullRect);
        defer imev.window.popClipRect();
        try win.renderRect(imev.window, style.colors.background, fullRect);

        const rect = fullRect.inset(20, 20, 20, 20);

        te.core.measurer = .{ .style = &style, .imev = imev };
        defer te.core.measurer = .{};

        if (imev.textInput) |text| {
            try te.core.insert(te.core.cursor, text.slice());
        }
        if (imev.keyDown) |k| switch (k) {
            .Return => try te.core.insert(te.core.cursor, "\n"),
            .Left => te.core.cursor = te.core.addPoint(te.core.cursor, -1),
            .Right => te.core.cursor = te.core.addPoint(te.core.cursor, 1),
            .Backspace => te.core.delete(te.core.addPoint(te.core.cursor, -1), te.core.cursor),
            .Delete => te.core.delete(te.core.cursor, te.core.addPoint(te.core.cursor, 1)),
            else => {},
        };
        const clickState = imev.hover(te.id, fullRect);
        if (clickState.mouseDown) imev.rerender();

        var riter = te.core.render(rect.w, rect.h + 40, 0);
        while (try riter.next(te.alloc)) |*nxt| {
            defer nxt.deinit();

            var cursorX: ?i64 = null;
            const lineRect = rect.down(nxt.y).height(nxt.lineHeight);

            for (nxt.pieces) |*piece, i| {
                if (clickState.mouseDown and lineRect.rightCut(piece.x).containsPoint(imev.cursor)) {
                    te.core.cursor = .{ .text = piece.text, .offset = 0 };
                }
                if (piece.text == te.core.cursor.text) {
                    cursorX = piece.x;
                    if (te.core.cursor.offset != 0) {
                        cursorX.? += piece.measure.characters.items[te.core.cursor.offset - 1].width;
                    }
                }
            }

            if (cursorX != null) {
                try win.renderRect(imev.window, style.colors.linebg, lineRect.inset(0, -20, 0, -20));
            }

            for (nxt.pieces) |*piece, i| {
                if (piece.measure.characters.items.len == 0) continue;
                try piece.measure.data.render(.{
                    .x = rect.x + piece.x,
                    .y = rect.y + piece.y,
                });
            }
            if (cursorX) |crsrX| {
                try win.renderRect(
                    imev.window,
                    style.colors.cursor,
                    lineRect.right(crsrX - 1).width(2),
                );
            }
        }
    }
};

pub const TextHLStyleReal = struct {
    font: *const win.Font,
    color: win.Color,
    bg: ?win.Color = null,
};

pub const Direction = enum {
    left,
    right,
};
pub const ActionMode = enum {
    raw, // typing * inserts *, formatting is visible
    contextAware, // typing * inserts \*, formatting is hidden
};
pub const Regex = struct {
    const T = gui.StructDataHelper(@This());
    body: []const u8,
    flags: []const u8,
    pub const ModeData = struct {
        body: T(.body),
        flags: T(.flags),
    };
};
pub const CharacterStop = union(enum) {
    const Q = gui.UnionDataHelper(@This());

    byte: void,
    codepoint: void,
    character: void,
    word: void,
    line: void,
    regex: Regex,

    lowestLevelNode: void, // context aware move one node right, maximum depth
    node: void, // context aware move one node right. eg might select from (to the end of)

    pub const default_regex = Regex{ .body = "N", .flags = "N" };

    pub const ModeData = union(Q(type)) {
        byte: Q(.byte),
        codepoint: Q(.codepoint),
        character: Q(.character),
        word: Q(.word),
        line: Q(.line),
        regex: Q(.regex),

        lowestLevelNode: Q(.lowestLevelNode),
        node: Q(.node),
    };
};
pub const LineStop = union(enum) {
    const Q = gui.UnionDataHelper(@This());

    screen: void,
    file: void,

    pub const ModeData = union(Q(type)) {
        body: Q(.body),
        flags: Q(.flags),
    };
};

pub const Action = union(enum) {
    const Q = gui.UnionDataHelper(@This());

    none: None,
    insert: Insert,
    delete: Delete,
    moveCursorLR: MoveCursorLR,
    save: Save,

    pub const default_none = None{};
    pub const default_insert = Insert{ .direction = .right, .mode = .raw, .text = "N" };
    pub const default_delete = Delete{ .direction = .left, .stop = .codepoint };
    pub const default_moveCursorLR = MoveCursorLR{ .direction = .right, .stop = .codepoint };
    pub const default_save = Save{};

    pub const ModeData2 = union(Q(type)) {
        none: Q(.none),
        insert: Q(.insert),
        delete: Q(.delete),
        moveCursorLR: Q(.moveCursorLR),
        save: Q(.save),
    };

    pub fn apply(value: Action, app: *App) void {
        return help.unionCallThis("apply", value, .{app});
    }

    pub const None = struct {
        const T = gui.StructDataHelper(@This());
        pub const ModeData = struct {};

        pub fn apply(none: None, app: *App) void {}
    };
    pub const Insert = struct {
        const T = gui.StructDataHelper(@This());

        direction: Direction,
        mode: ActionMode,
        text: []const u8,

        pub const ModeData = struct {
            direction: T(.direction),
            mode: T(.mode),
            text: T(.text),
        };

        pub fn apply(insert: Insert, app: *App) void {
            app.text.insertSlice(app.cursorLocation, insert.text) catch
                return; // rip, text could not be inserted. do nothing, do not move cursor.

            const clpos = app.findCharacterPosition(app.cursorLocation);
            app.tree.edit(
                app.cursorLocation,
                app.cursorLocation,
                insert.text.len,
                clpos,
                clpos,
                app.findCharacterPosition(app.cursorLocation + insert.text.len),
            );
            app.textChanged = true;

            switch (insert.direction) {
                .left => app.cursorLocation += insert.text.len,
                .right => {},
            }
        }
    };
    pub const Delete = struct {
        const T = gui.StructDataHelper(@This());

        direction: Direction,
        stop: CharacterStop,

        pub const ModeData = struct {
            direction: T(.direction),
            stop: T(.stop),
        };

        pub fn apply(delete: Delete, app: *App) void {
            const stopPos = app.findStop(delete.stop, delete.direction);
            const moveDistance = blk: {
                const left = std.math.min(app.cursorLocation, stopPos);
                const right = std.math.max(app.cursorLocation, stopPos);

                std.mem.copy(
                    u8,
                    app.text.items[left..],
                    app.text.items[right..],
                );
                app.text.items.len -= right - left;

                const clpos = app.findCharacterPosition(left);
                app.tree.edit(
                    left,
                    right,
                    left,
                    clpos,
                    app.findCharacterPosition(right),
                    clpos,
                );
                app.textChanged = true;

                break :blk right - left;
            };
            switch (delete.direction) {
                .left => app.cursorLocation -= moveDistance,
                .right => {},
            }
        }
    };
    pub const MoveCursorLR = struct {
        const T = gui.StructDataHelper(@This());

        direction: Direction,
        stop: CharacterStop,

        pub const ModeData = struct {
            direction: T(.direction),
            stop: T(.stop),
        };

        pub fn apply(moveCursorLR: MoveCursorLR, app: *App) void {
            const stopPos = app.findStop(moveCursorLR.stop, moveCursorLR.direction);
            app.cursorLocation = stopPos;
        }
    };
    pub const MoveCursorUD = struct {
        const T = gui.StructDataHelper(@This());

        direction: enum { up, down },
        mode: LineStop,

        pub const ModeData = struct {
            direction: T(.direction),
            mode: T(.mode),
        };
    };
    pub const Save = struct {
        const T = gui.StructDataHelper(@This());

        pub const ModeData = struct {};

        pub fn apply(save: Save, app: *App) void {
            app.saveFile();
        }
    };
};

const LineDrawCall = struct {
    text: [64]u8,
    textLength: u8,
    font: *const win.Font,
    color: win.Color,
    bg: ?win.Color,
    // to allow for rounded corners, backgrounds should probably kept in a sperate
    // BackgroundDrawCall per-line. unfortunately, that means more text measurement
    // because of how text measurement works, so not yet.
    measure: struct { w: i64, h: i64 },
    x: i64, // y is chosen based on line top, line height, and text baseline
    fn differentStyle(ldc: *LineDrawCall, hlStyle: TextHLStyleReal) bool {
        if (ldc.bg) |bg1| {
            if (hlStyle.bg) |bg2| {
                if (!bg1.equal(bg2)) return true;
            } else {
                return true;
            }
        } else if (hlStyle.bg) |bg2| return true;

        return hlStyle.font != ldc.font or !hlStyle.color.equal(ldc.color);
    }
};
const LineInfo = struct {
    yTop: i64,
    height: i64,
    drawCalls: std.ArrayList(LineDrawCall),
    fn init(arena: *std.mem.Allocator, yTop: i64, height: i64) LineInfo {
        const drawCalls = std.ArrayList(LineDrawCall).init(arena);

        return LineInfo{
            .yTop = yTop,
            .height = height,
            .drawCalls = drawCalls,
        };
    }
};
const CharacterPosition = struct {
    x: i64,
    w: i64,
    line: *LineInfo,
    index: u64,
    // y/h are determined by the line.
};
const TextInfo = struct {
    maxWidth: i64,
    lines: std.ArrayList(LineInfo),
    characterPositions: std.ArrayList(CharacterPosition),
    progress: struct {
        activeDrawCall: ?LineDrawCall,
        x: i64,
    },
    rawAlloc: *std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    cursor: *parser.TreeCursor,
    // y/h must be determined by the line when drawing
    fn init(
        rawAlloc: *std.mem.Allocator,
        maxWidth: i64,
        cursor: *parser.TreeCursor,
    ) !TextInfo {
        // I didn't really want to do this but I don't see a way around it
        var arena = try rawAlloc.create(std.heap.ArenaAllocator);
        errdefer rawAlloc.destroy(arena);
        arena.* = std.heap.ArenaAllocator.init(rawAlloc);
        errdefer arena.deinit();

        var alloc = &arena.allocator;
        var lines = std.ArrayList(LineInfo).init(alloc);

        const characterPositions = std.ArrayList(CharacterPosition).init(alloc);

        try lines.append(LineInfo.init(alloc, 0, 10));

        return TextInfo{
            .maxWidth = maxWidth,
            .lines = lines,
            .characterPositions = characterPositions,
            .progress = .{
                .activeDrawCall = null,
                .x = 0,
            },
            .arena = arena,
            .rawAlloc = rawAlloc,
            .cursor = cursor,
        };
    }
    fn deinit(ti: *TextInfo) void {
        ti.arena.deinit();
        ti.rawAlloc.destroy(ti.arena);
    }

    /// start a new draw call and append a new character
    fn startNewDrawCall(ti: *TextInfo, char: u8, hlStyle: TextHLStyleReal) !void {
        try ti.commit();

        const text = [_]u8{ char, 0 };
        var font = hlStyle.font;
        var color = hlStyle.color;

        try ti.appendCharacterPosition(char, font, color);

        var latestDrawCall = &ti.progress.activeDrawCall;
        latestDrawCall.* = .{
            .text = [64]u8{
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            },
            .textLength = 1,
            .font = font,
            .color = color,
            .bg = hlStyle.bg,
            .measure = .{ .w = 0, .h = 0 },
            .x = ti.progress.x, // lineStart
        };
        std.mem.copy(u8, &latestDrawCall.*.?.text, &text);
    }

    // append the character position from the active draw call
    fn appendCharacterPosition(ti: *TextInfo, char: u8, font: *const win.Font, color: win.Color) !void {
        var singleCharacter = [_]u8{ char, 0 };
        var characterMeasure = try win.Text.measure(font, &singleCharacter);
        try ti.appendCharacterPositionMeasure(characterMeasure.w);
    }

    fn appendCharacterPositionMeasure(ti: *TextInfo, width: i64) !void {
        var lineOverX = blk: {
            var latestDrawCall = &ti.progress.activeDrawCall;
            break :blk if (latestDrawCall.*) |ldc| (try win.Text.measure(ldc.font, &ldc.text)).w else 0;
        };

        try ti.characterPositions.append(.{
            .x = lineOverX + ti.progress.x,
            .w = width,
            .line = &ti.lines.items[ti.lines.items.len - 1],
            .index = ti.characterPositions.items.len,
        });
    }

    /// append a new character to the existing draw call
    /// activeDrawCall must exist
    fn extendDrawCall(ti: *TextInfo, char: u8) !void {
        var latestDrawCall = &ti.progress.activeDrawCall.?;

        try ti.appendCharacterPosition(char, latestDrawCall.font, latestDrawCall.color);

        latestDrawCall.text[latestDrawCall.textLength] = char;
        latestDrawCall.textLength += 1;
        latestDrawCall.text[latestDrawCall.textLength] = 0;
    }

    fn addFakeCharacter(ti: *TextInfo, char: []const u8, hlStyle: TextHLStyleReal) !void {
        for (char) |byte| {
            try ti.addRenderedCharacter(byte, hlStyle);
            _ = ti.characterPositions.pop();
        }
        try ti.appendCharacterPositionMeasure(0);
        // uh oh, this means clicking doesn't work properly. it should take the start
        // x position and subtract from the x end position but default to 0 if it goes backwards
    }
    fn addCharacter(ti: *TextInfo, char: u8, charIndex: u64, app: *App) !void {
        var index = ti.characterPositions.items.len;
        var renderNode = parser.getNodeAtPosition(index, ti.cursor);
        var renderStyle = renderNode.createClassesStruct(charIndex).renderStyle();

        var style = app.getStyle(renderStyle);

        switch (renderStyle) {
            .showInvisibles => |sinvis| {
                if (char == '\n')
                    return switch (sinvis) {
                        .all => try ti.addFakeCharacter("⏎", style),
                        .inlin_ => try ti.addNewlineCharacter(),
                    };
                switch (char) {
                    ' ' => try ti.addFakeCharacter("·", style),
                    '\t' => try ti.addFakeCharacter("⭲   ", style),
                    else => try ti.addRenderedCharacter(char, style),
                }
            },
            else => if (char == '\n')
                try ti.addNewlineCharacter()
                // how does this work with bg styles?
                // make a drawCall from current pos to eol for the style?
            else
                try ti.addRenderedCharacter(char, style),
        }
    }

    /// append a new character
    fn addRenderedCharacter(ti: *TextInfo, char: u8, hlStyle: TextHLStyleReal) !void {
        // check if character is the end of a unicode codepoint, else ignore. or something like that.
        var latestDrawCallOpt = &ti.progress.activeDrawCall;
        if (latestDrawCallOpt.* == null or
            latestDrawCallOpt.*.?.differentStyle(hlStyle) or
            latestDrawCallOpt.*.?.textLength >= 63)
        {
            try ti.startNewDrawCall(char, hlStyle);
            return;
        }
        var latestDrawCall = &latestDrawCallOpt.*.?;
        var textCopy = latestDrawCall.text;
        var lenCopy = latestDrawCall.textLength;
        textCopy[lenCopy] = char;
        lenCopy += 1;
        textCopy[lenCopy] = 0;

        const measure = try win.Text.measure(latestDrawCall.font, &textCopy);
        if (@intCast(i64, measure.w) + latestDrawCall.x >= ti.maxWidth) {
            // start new line
            // try again
            try ti.addNewline();
            try ti.startNewDrawCall(char, hlStyle);
            return;
        }

        // extend line
        try ti.extendDrawCall(char);
        return;
    }

    /// if a draw call is active, finish it and append it
    fn commit(ti: *TextInfo) !void {
        if (ti.progress.activeDrawCall == null) return;
        var adc = ti.progress.activeDrawCall.?;
        defer ti.progress.activeDrawCall = null;

        const measure = try win.Text.measure(adc.font, &adc.text);
        adc.measure = .{ .w = @intCast(i64, measure.w), .h = @intCast(i64, measure.h) };

        var latestLine = &ti.lines.items[ti.lines.items.len - 1];
        if (latestLine.height < adc.measure.h) latestLine.height = adc.measure.h;
        try latestLine.drawCalls.append(adc);
        ti.progress.x += @intCast(i64, adc.measure.w);
    }

    /// start a new line
    fn addNewlineCharacter(ti: *TextInfo) !void {
        try ti.addNewline();

        try ti.appendCharacterPositionMeasure(0);
        // newline has 0 width and is the first character of the line
    }
    fn addNewline(ti: *TextInfo) !void {
        try ti.commit();

        var latestLine = &ti.lines.items[ti.lines.items.len - 1];
        var nextLine = LineInfo.init(
            &ti.arena.allocator,
            latestLine.height + latestLine.yTop,
            10,
        );
        ti.progress.x = 0;
        try ti.lines.append(nextLine);
    }
};

pub fn Cache(comptime Key: type, comptime Value: type) type {
    const Hashmap = std.AutoHashMap(
        Key,
        struct { used: bool, value: Value },
    );

    return struct {
        const ThisCache = @This();

        hashmap: Hashmap,
        alloc: *std.mem.Allocator,

        pub fn init(alloc: *std.mem.Allocator) ThisCache {
            var map = Hashmap.init(alloc);
            return .{
                .hashmap = map,
                .alloc = alloc,
            };
        }
        pub fn deinit(cache: *ThisCache) void {
            var it = cache.hashmap.iterator();
            while (it.next()) |next| {
                next.value.value.deinit();
            }
            cache.hashmap.deinit();
        }

        pub fn clean(cache: *ThisCache) !void {
            var toRemove = std.ArrayList(Key).init(cache.alloc);
            defer toRemove.deinit();

            var it = cache.hashmap.iterator();
            while (it.next()) |next| {
                if (!next.value.used)
                    try toRemove.append(next.key);
                next.value.used = false;
            }

            for (toRemove.items) |key| {
                var removed = cache.hashmap.remove(key).?;
                removed.value.value.deinit();
            }
        }
        pub fn getOrCreate(cache: *ThisCache, key: Key) !*Value {
            var result = try cache.hashmap.getOrPut(key);
            if (!result.found_existing) {
                var item = try Value.init(key);
                result.entry.value = .{
                    .used = true,
                    .value = item,
                };
            }
            result.entry.value.used = true;
            return &result.entry.value.value;
        }
    };
}

pub const TextRenderInfo = struct {
    font: *const win.Font,
    color: win.Color,
    text: [64]u8,
    size: win.TextSize,
    window: *win.Window,
};
pub const TextRenderData = struct {
    text: win.Text,
    pub fn init(tri: TextRenderInfo) !TextRenderData {
        return TextRenderData{
            .text = try win.Text.init(
                tri.font,
                tri.color,
                &tri.text,
                tri.size,
                tri.window,
            ),
        };
    }
    pub fn deinit(trd: *TextRenderData) void {
        trd.text.deinit();
    }
};
pub const TextRenderCache = Cache(TextRenderInfo, TextRenderData);

const CursorPoint = struct {
    byte: usize,
    rowCol: parser.RowCol,
};
pub const App = struct {
    scrollY: i64,
    scrollYAnim: gui.PosInterpolation,
    alloc: *std.mem.Allocator,
    style: *const gui.Style,

    cursorLocation: usize,
    cursorRowCol: parser.RowCol,

    // in the future, this might become std.ArrayList(cursorSelection)
    // but that seems needlessly complicated for now
    selection: struct {
        start: CursorPoint, // selection start
        end: CursorPoint,
        center: CursorPoint, // where the cursor is
    },
    text: std.ArrayList(u8),
    readOnly: bool,
    filename: []const u8,
    tree: parser.Tree,
    textChanged: bool,
    textInfo: ?TextInfo,
    prevWidth: ?i64,
    cursorBlinkTime: u64,
    id: gui.ID,

    textRenderCache: TextRenderCache,

    pub fn init(alloc: *std.mem.Allocator, filename: []const u8, ev: *ImEvent) !App {
        var readOnly = false;
        var file: []u8 = std.fs.cwd().readFileAlloc(alloc, filename, 10000000) catch |e| blk: {
            readOnly = true;
            break :blk try std.fmt.allocPrint(alloc, "File load error: {}.", .{e});
        };
        defer alloc.free(file);

        var textList = try std.ArrayList(u8).initCapacity(alloc, file.len);
        textList.appendSlice(file) catch unreachable;
        errdefer textList.deinit();

        var textRenderCache = TextRenderCache.init(alloc);
        errdefer textRenderCache.deinit();

        var tree = try parser.Tree.init(textList.items);
        errdefer tree.deinit();

        return App{
            .scrollY = 0,
            .scrollYAnim = gui.PosInterpolation.init(200),
            .alloc = alloc,
            .style = &ev.data.settings.style,
            .cursorLocation = 0,
            .cursorRowCol = .{ .row = 0, .col = 0 },
            .selection = .{
                .start = .{ .byte = 0, .rowCol = .{ .row = 0, .col = 0 } },
                .end = .{ .byte = 0, .rowCol = .{ .row = 0, .col = 0 } },
                .center = .{ .byte = 0, .rowCol = .{ .row = 0, .col = 0 } },
            },
            .text = textList,
            .readOnly = readOnly,
            .filename = filename,
            .textRenderCache = textRenderCache,
            .tree = tree,
            .textChanged = true,
            .textInfo = null,
            .prevWidth = null,
            .cursorBlinkTime = 0,
            .id = ev.newID(),
        };
    }
    pub fn deinit(app: *App) void {
        if (app.textInfo) |*ti| ti.deinit();
        app.text.deinit();
        app.textRenderCache.deinit();
        app.tree.deinit();
    }
    fn saveFile(app: *App) void {
        std.debug.warn("Save {}...", .{app.filename});
        std.fs.cwd().writeFile(app.filename, app.text.items) catch |e| {
            std.debug.warn("Save failed: {}", .{e});
            return;
        };
        std.debug.warn(" Saved\n", .{});
    }
    fn findCharacterPosition(app: *App, pos: usize) parser.RowCol {
        // go backwards until \n or start of file
        // uh oh uuh that's not enough, it also needs to know what the line number is
        // uuh... for now loop from the beginning of the file to find the character ok perfect great
        var finalPos: parser.RowCol = .{ .row = 0, .col = 0 };
        for (app.text.items) |char, i| {
            if (i == pos) return finalPos;
            if (char == '\n') {
                finalPos.row += 1;
                finalPos.col = 0;
            } else {
                finalPos.col += 1;
            }
        }
        return finalPos;
    }

    // this should probably accept the starting location as an argument
    fn findStop(app: *App, stop: CharacterStop, direction: Direction) usize {
        return switch (stop) {
            .byte => switch (direction) {
                .left => blk: {
                    if (app.cursorLocation > 0) {
                        break :blk app.cursorLocation - 1;
                    } else {
                        break :blk 0;
                    }
                },
                .right => blk: {
                    if (app.cursorLocation + 1 < app.text.items.len) {
                        break :blk app.cursorLocation + 1;
                    } else {
                        break :blk app.text.items.len;
                    }
                },
            },
            .codepoint => switch (direction) {
                .left => blk: {
                    var i = app.cursorLocation;
                    while (i > 0) {
                        i -= 1;
                        var char = app.text.items[i];
                        if (char <= 0b01111111) break;
                        if (char & 0b01000000 != 0) break;
                    }
                    break :blk i;
                },
                .right => blk: {
                    var i = app.cursorLocation;
                    while (i < app.text.items.len - 1) {
                        i += 1;
                        var char = app.text.items[i];
                        if (char <= 0b01111111) break;
                        if (char & 0b01000000 != 0) break;
                    }
                    break :blk i;
                },
            },
            .lowestLevelNode => switch (direction) {
                .left => @panic("niy"),
                .right => blk: {
                    var i = app.cursorLocation;
                    // find last node ending <= i
                    // move one node right, go to max depth
                    // if node start == this start, return node end
                    // else return node start
                    if (app.textChanged) unreachable;
                    var cursor = parser.TreeCursor.init(app.tree.root());
                    defer cursor.deinit();
                    var node = parser.getNodeAtPosition(i, &cursor);
                    // this is an issue because it means findnode cannot be used after text has been edited
                    var pos = node.position();
                    if (pos.to > i) return pos.to;

                    var nxt = node;
                    while (nxt.next()) |envy| {
                        nxt = envy;
                        var nxtp = nxt.position();
                        if (nxtp.from > i) return nxtp.from;
                        if (nxtp.to > i) return nxtp.to;
                    }
                    return app.text.items.len;
                },
            },
            else => {
                std.debug.panic("not implemented", .{});
            },
        };
    }

    /// measure a single line. do not mesaure if the line has not changed.
    fn measureLine(app: *App, width: i64) !void {}
    fn remeasureText(app: *App, width: i64) !void {
        if (app.textChanged or
            app.textInfo == null or
            app.prevWidth == null or
            width != app.prevWidth.?)
        {} else return;
        app.prevWidth = width;

        // TODO: only update the lines that need to be changed
        // take given edit positions, search back until the first true line break
        // (= the node class says so), reparse that line until the next true line break
        // we can keep our own edit data to know what needs changing, and find each line,
        // trash the data, parse again. also, character positions will now be stored in
        // the lines instead of globally so that we don't have to do lots of inserts in
        // the middle. lines will still be an arraylist though, which will obviously be
        // a problem in the future.
        // if the width changes, that is the worst case. everything has to be remeasured.
        // it is probably possible to optimize it so that things out of screen are not
        // remeasured but flagged as wrong so when they need to be seen they are
        // remeasured (or eg if the cursor needs to move up/down or something)

        var cursor = parser.TreeCursor.init(app.tree.root());
        defer cursor.deinit();

        if (app.textInfo) |*ti| ti.deinit();
        app.textInfo = try TextInfo.init(app.alloc, width, &cursor);
        // typescript would be better here, it would know that textInfo is not null
        // not sure if that could even work in this language
        for (app.text.items) |char, index| {
            try app.textInfo.?.addCharacter(
                char,
                index,
                app,
            );
        }
        try app.textInfo.?.commit();
    }

    fn getStyle(app: *App, renderStyle: parser.RenderStyle) TextHLStyleReal {
        const style = app.style;
        const colors = &style.colors;
        const fonts = &style.fonts;
        return switch (renderStyle) {
            .control => .{
                .font = fonts.monospace,
                .color = colors.control,
            },
            .text => |txt| switch (txt) {
                .bolditalic => TextHLStyleReal{
                    .font = fonts.bolditalic,
                    .color = colors.text,
                },
                .bold => TextHLStyleReal{
                    .font = fonts.bold,
                    .color = colors.text,
                },
                .italic => TextHLStyleReal{
                    .font = fonts.italic,
                    .color = colors.text,
                },
                .normal => TextHLStyleReal{
                    .font = fonts.standard,
                    .color = colors.text,
                },
            },
            .heading => .{
                .font = fonts.heading,
                .color = colors.text,
            },
            .codeLanguage => .{
                .font = fonts.standard,
                .color = colors.inlineCode,
            },
            .code => .{
                .font = fonts.monospace,
                .color = colors.text,
            },
            .inlineCode => .{
                .font = fonts.monospace,
                .color = colors.inlineCode,
                .bg = colors.codeBackground,
            },
            .showInvisibles => .{
                .font = fonts.monospace,
                .color = colors.control,
            },
            .errort => .{
                .font = fonts.monospace,
                .color = colors.errorc,
            },
        };
    }

    fn render(app: *App, imev: *ImEvent, showPerformance: bool, fullArea: win.Rect) !void {
        var timer = if (showPerformance) try std.time.Timer.start() else undefined;

        const window = imev.window;

        const hover = imev.hover(app.id, fullArea).hover;
        if (hover) {
            window.cursor = .ibeam;
        }
        app.scrollY += -imev.scroll(app.id, fullArea).y;

        app.scrollYAnim.set(imev, app.scrollY, gui.timing.EaseIn, .reverse);
        const scrollY = app.scrollYAnim.get(imev); // app.scrollAnimationEnabled ? scrollYAnim.get : app.scrollY

        if (app.scrollY < 0) {
            app.scrollY = 0;
            if (!imev.animationEnabled) imev.rerender();
        }

        const pos = fullArea.noHeight().addWidth(-40).rightCut(20).down(10 + -scrollY);

        const startCursorLocation = app.cursorLocation;

        const style = app.style;

        var arena = std.heap.ArenaAllocator.init(app.alloc);
        defer arena.deinit();

        var alloc = &arena.allocator;

        if (imev.keyDown) |kd| blk: {
            const action: Action = switch (kd) {
                .Left => .{
                    .moveCursorLR = .{ .direction = .left, .stop = .codepoint },
                },
                .Right => .{
                    .moveCursorLR = .{ .direction = .right, .stop = .lowestLevelNode },
                },
                .Backspace => .{
                    .delete = .{ .direction = .left, .stop = .codepoint },
                },
                .Return => .{
                    .insert = .{ .direction = .left, .mode = .raw, .text = "\n" },
                },
                .Delete => .{
                    .delete = .{ .direction = .right, .stop = .codepoint },
                },
                .Escape => .{ .save = .{} },
                else => break :blk,
            };
            action.apply(app);
        }
        if (imev.textInput) |textin| {
            const action: Action = .{
                .insert = .{
                    .direction = .left,
                    .mode = .raw,
                    .text = textin.text[0..textin.length],
                },
            };
            action.insert.apply(app);
        }

        if (showPerformance) std.debug.warn("{} : Input\n", .{timer.lap()});

        if (app.textChanged) app.tree.reparse(app.text.items);
        app.tree.lock();
        defer app.tree.unlock();

        if (showPerformance) std.debug.warn("{} : Reparse\n", .{timer.lap()});

        try app.remeasureText(pos.w);
        const textInfo = app.textInfo.?;

        if (showPerformance) std.debug.warn("{} : Remeasure\n", .{timer.lap()});

        const lastLine = textInfo.lines.items[textInfo.lines.items.len - 1];
        const maxScrollY = lastLine.yTop + lastLine.height - 20;
        if (app.scrollY > maxScrollY) {
            app.scrollY = maxScrollY;
            if (!imev.animationEnabled) imev.rerender();
        }

        if (imev.mouseDown) blk: {
            const mpos = imev.cursor;
            if (!fullArea.containsPoint(mpos))
                break :blk; // ignored,  out of area
            for (textInfo.characterPositions.items) |cp| {
                if ((mpos.x - @intCast(i64, pos.x) > (cp.x + @divFloor((cp.w), 2)) and
                    mpos.y > cp.line.yTop + pos.y) or
                    mpos.y > (cp.line.yTop + cp.line.height) + pos.y)
                    app.cursorLocation = cp.index + 1;
            }
        }

        if (showPerformance) std.debug.warn("{} : Scroll and Click\n", .{timer.lap()});

        if (app.textChanged or app.cursorLocation != startCursorLocation)
            app.cursorBlinkTime = imev.time;

        app.textChanged = false;

        // ==== rendering ====

        if (!imev.render) return;

        // this isn't necessary right now
        // also it wastes time making and deleting things when you scroll
        // (showing and hiding texts so they get deleted and recreated)
        // try app.textRenderCache.clean();
        // if (showPerformance) std.debug.warn("{} : Text Rendercache Clean\n", .{timer.lap()});

        try window.pushClipRect(fullArea);
        defer window.popClipRect();

        try win.renderRect(window, style.colors.background, fullArea);

        for (textInfo.lines.items) |line| blk: {
            for (line.drawCalls.items) |drawCall| {
                if (line.yTop + line.height - scrollY < 0) continue;
                if (line.yTop - scrollY > fullArea.h) break :blk;
                if (drawCall.bg) |bg| {
                    try win.renderRect(
                        window,
                        bg,
                        .{
                            .x = drawCall.x + pos.x,
                            .y = line.yTop + pos.y,
                            .w = drawCall.measure.w,
                            .h = line.height,
                        },
                    );
                }
            }
        }

        if (app.cursorLocation > 0) {
            const cursorPosition = textInfo.characterPositions.items[app.cursorLocation - 1];
            try win.renderRect(
                window,
                app.style.colors.linebg,
                .{
                    .x = fullArea.x,
                    .y = cursorPosition.line.yTop + pos.y,
                    .w = fullArea.w,
                    .h = cursorPosition.line.height,
                },
            );
        } else {
            // render line at position 0
        }

        for (textInfo.lines.items) |line| blk: {
            for (line.drawCalls.items) |drawCall| {
                if (line.yTop + line.height - scrollY < 0) continue;
                if (line.yTop - scrollY > fullArea.h) break :blk;
                const text = try app.textRenderCache.getOrCreate(.{
                    .font = drawCall.font,
                    .color = drawCall.color,
                    .text = drawCall.text,
                    .size = .{
                        .w = drawCall.measure.w,
                        .h = drawCall.measure.h,
                    },
                    .window = window,
                });
                try text.text.render(.{
                    .x = drawCall.x + pos.x,
                    .y = line.yTop +
                        pos.y +
                        (line.height - drawCall.measure.h),
                });
            }
        }

        if (app.cursorLocation > 0) {
            const charIndex = app.cursorLocation - 1;
            const cursorPosition = textInfo.characterPositions.items[charIndex];
            if (!imev.animationEnabled or @rem(imev.time - app.cursorBlinkTime, 1000) < 500)
                try win.renderRect(
                    window,
                    app.style.colors.cursor,
                    .{
                        .x = cursorPosition.x + cursorPosition.w + pos.x - 1,
                        .y = cursorPosition.line.yTop + pos.y,
                        .w = 2,
                        .h = cursorPosition.line.height,
                    },
                );

            var cursor2 = parser.TreeCursor.init(app.tree.root());
            defer cursor2.deinit();
            var styleBeforeCursor = parser.getNodeAtPosition(
                charIndex,
                &cursor2,
            );

            // var classesText = std.ArrayList(u8).init(alloc);
            // try styleBeforeCursor.printClasses(&classesText);

            var resText = try std.fmt.allocPrint0(alloc, "Classes: {} ({})", .{
                styleBeforeCursor.createClassesStruct(charIndex),
                app.findCharacterPosition(charIndex),
            });
            defer alloc.free(resText);

            var text = try win.Text.init(
                style.fonts.standard,
                style.colors.text,
                resText,
                null,
                window,
            );
            defer text.deinit();
            if (std.builtin.os.tag != .macosx)
                try text.render(.{
                    .x = fullArea.x + fullArea.w - text.size.w,
                    .y = fullArea.y + fullArea.h - text.size.h,
                });
        } else {
            // render cursor at position 0
        }

        if (showPerformance) std.debug.warn("{} : All Render\n", .{timer.lap()});
    }
};
const Eleven = union(enum) {
    const T = gui.UnionDataHelper(@This());

    eleven: [1]u8,
    twelve: enum { thirteen, fourteen, fifteen },
    thirteen: void,

    pub const default_eleven: [1]u8 = [_]u8{'A'};
    pub const default_twelve: help.FieldType(@This(), "twelve") = .thirteen;
    pub const default_thirteen = {};

    pub const ModeData = union(T(type)) {
        eleven: T(.eleven),
        twelve: T(.twelve),
        thirteen: T(.thirteen),
    };
};
const PointlessButtons = struct {
    const T = gui.StructDataHelper(@This());

    actionDemo: Action = Action{ .none = Action.default_none },
    one: enum { two, three, four, five, six } = .two,
    seven: enum { eight, nine } = .eight,
    ten: Eleven = .{ .eleven = Eleven.default_eleven },
    toggleSwitch: bool = false,

    pub const ModeData = struct {
        actionDemo: T(.actionDemo),
        one: T(.one),
        seven: T(.seven),
        ten: T(.ten),
        toggleSwitch: T(.toggleSwitch),
    };
};
const Poll = struct {
    const T = gui.StructDataHelper(@This());

    reportFPS: bool = false,
    animations: bool = true,

    pub const ModeData = struct {
        reportFPS: T(.reportFPS),
        animations: T(.animations),
    };
};
const Update = union(enum) {
    const T = gui.UnionDataHelper(@This());
    wait: void,
    poll: Poll,
    pub const default_wait = {};
    pub const default_poll = Poll{};

    pub const ModeData = union(T(type)) {
        wait: T(.wait),
        poll: T(.poll),
    };
};
pub const UpdateMode = struct {
    const T = gui.StructDataHelper(@This());

    update: Update = .{ .poll = Update.default_poll },
    guiDisplay: enum { single, double } = .single,
    showRenderCount: bool = false,
    showPerformance: bool = false,
    showClippingRects: bool = false,
    resizePin: enum { top, center, bottom } = .top,

    pointlessButtons: PointlessButtons = PointlessButtons{},
    textField: [100]u8 = [_]u8{0} ** 100,

    pub const ModeData = struct {
        update: T(.update),
        guiDisplay: T(.guiDisplay),
        showRenderCount: T(.showRenderCount),
        showPerformance: T(.showPerformance),
        showClippingRects: T(.showClippingRects),
        resizePin: T(.resizePin),

        pointlessButtons: T(.pointlessButtons),
        textField: T(.textField),
    };
};

const DisplayMode = enum {
    editor,
    gui,
    window,
    mte,
    pub const title_editor = "Editor";
    pub const title_gui = "GUI Demo";
    pub const title_window = "Window Demo";
    pub const title_mte = "Multiline Text Editor";
};

const WindowDemo = @import("window_demo.zig").WindowDemo;

pub const MainPage = struct {
    pub fn init(alloc: *std.mem.Allocator, imev: *ImEvent) MainPage {
        return Auto.create(MainPage, imev, alloc, .{
            .app = App.init(alloc, "tests/medium sized file.md", imev) catch
                @panic("oom not handled"),
            .mte = MultilineTextEditor.init(alloc, imev) catch @panic("oom not handled"),
        });
    }
    pub fn deinit(page: *MainPage) void {
        Auto.destroy(page, .{ .imedtrscrll, .imedtr2, .app, .displayedtr, .mte });
    }

    auto: Auto,

    imedtrscrll: gui.ScrollView(gui.DataEditor(UpdateMode)),
    imedtr2: gui.DataEditor(UpdateMode),
    app: App,
    mte: MultilineTextEditor,
    displayedtr: gui.DataEditor(DisplayMode),
    windowDemo: WindowDemo,

    displayMode: DisplayMode = .gui,

    pub fn render(page: *MainPage, imev: *ImEvent, style: gui.Style, pos: win.Rect, alloc: *std.mem.Allocator) !void {
        var currentPos: win.TopRect = pos.noHeight().down(5);
        var updateMode: *UpdateMode = &imev.data.settings.updateMode;

        var imedtrscrll = &page.imedtrscrll;
        var imedtr2 = &page.imedtr2;
        var app = &page.app;
        var displayedtr = &page.displayedtr;

        currentPos.y += (try displayedtr.render(&page.displayMode, style, imev, currentPos)).h;
        const contentRect = currentPos.setY2(pos.y2());

        switch (page.displayMode) {
            .editor => {
                try app.render(imev, updateMode.showPerformance, contentRect);
            },
            .gui => {
                currentPos.y += gui.seperatorGap;
                const guiPos = currentPos.addWidth(-40).rightCut(40);
                switch (updateMode.guiDisplay) {
                    .double => {
                        const cx = currentPos.centerX();
                        _ = try imedtrscrll.render(.{updateMode}, style, imev, guiPos.setX2(cx - 20).setY2(pos.y2()));
                        _ = try imedtr2.render(updateMode, style, imev, guiPos.setX1(cx + 20));
                    },
                    .single => {
                        _ = try imedtrscrll.render(.{updateMode}, style, imev, guiPos.setY2(pos.y2()));
                    },
                }
            },
            .window => {
                try page.windowDemo.render(imev, style, currentPos.setY2(pos.y2()), alloc);
            },
            .mte => {
                try page.mte.render(contentRect, imev, style);
            },
        }
    }
};
// const id = imev.getID(MainPage);
// imev.getData(id, DataType, comptime defaultValue)
// "react-style" single function components
// would be nicer to use because they don't require explicit init/deinit
// it has the downside that stored data has to be allocated and ids have to and unrefreshed ids could have their state data deleted
// also any loops require annoying explicit id setting stuff so data doesn't get given to the wrong renderer
// also many other issues
// but in lots of ways it's nicer
// oh, initialization is a bit annoying to do right
// imev.getData(id, DataType, fn() {return someValue}  ) and that's with anon fn init syntax.
// react chooses to go the anti-performance route and recreates the initial value every time unless you memoize it

pub fn main() !void {
    const alloc = std.heap.c_allocator;

    try win.init();
    defer win.deinit();

    var loader = win.FontLoader.init();
    defer loader.deinit();

    var standardFont = try loader.loadFromName("Arial", 16);
    defer standardFont.deinit();
    var boldFont = try loader.loadFromName("Arial:weight=200", 16);
    defer boldFont.deinit();
    var italicFont = try loader.loadFromName("Arial:slant=100", 16);
    defer italicFont.deinit();
    var boldItalicFont = try loader.loadFromName("Arial:weight=200:slant=100", 16);
    defer boldItalicFont.deinit();
    var headingFont = try loader.loadFromName("Arial:weight=200", 24);
    defer headingFont.deinit();
    var monospaceFont = try loader.loadFromName("Consolas", 16);
    defer monospaceFont.deinit();

    var window = try win.Window.init(alloc);
    defer window.deinit();

    var style: gui.Style = .{
        .colors = .{
            .text = win.Color.rgb(255, 255, 255),
            .control = win.Color.hex(0x727885),
            .special = win.Color.rgb(128, 255, 128),
            .errorc = win.Color.rgb(255, 128, 128),
            .inlineCode = win.Color.hex(0x8fbcbb),

            .background = win.Color.hex(0x2e3440),
            .window = win.Color.hex(0x161a21),
            .codeBackground = win.Color.hex(0x21252f),
            .linebg = win.Color.hex(0x3f4757),

            .cursor = win.Color.rgb(128, 128, 255),
        },
        .gui = .{
            .text = win.Color.hex(0xFFFFFF),
            .button = .{
                .base = .{
                    .inactive = win.Color.hex(0x3f4757),
                    .active = win.Color.hex(0x2c4a44),
                },
                .hover = .{
                    .inactive = win.Color.hex(0x565f73),
                    .active = win.Color.hex(0x385c55),
                },
                .shadow = .{
                    .inactive = win.Color.hex(0x1c2029),
                    .active = win.Color.hex(0x142927),
                },
            },
            .hole = .{
                .floor = win.Color.hex(0x0a0b0f),
                .wall = win.Color.hex(0x101117),
            },
        },
        .fonts = .{
            .standard = &standardFont,
            .bold = &boldFont,
            .italic = &italicFont,
            .bolditalic = &boldItalicFont,
            .heading = &headingFont,
            .monospace = &monospaceFont,
        },
    };

    defer std.debug.warn("Quitting!\n", .{});

    // only if mode has raw text input flag set

    // if in foreground, loop pollevent
    // if in background, waitevent

    var imev = ImEvent.init(.{
        .settings = .{
            .style = style,
            .updateMode = UpdateMode{},
        },
    }, alloc);
    defer imev.deinit();

    var event: win.Event = .empty;
    var windowInFocus: bool = true;
    var evc: u64 = 0;

    var mainPage = MainPage.init(alloc, &imev);
    defer mainPage.deinit();

    const updateMode = &imev.data.settings.updateMode;

    var renderCount: u64 = 0;
    while (true) {
        if (event == .empty and !imev.internal.rerender and !imev.render) {
            event = if (windowInFocus) switch (updateMode.update) {
                .wait => try window.waitEvent(),
                .poll => window.pollEvent(),
            } else try window.waitEvent();
        }
        evc += 1;
        switch (event) {
            .quit => return,
            .windowFocus => windowInFocus = true,
            .windowBlur => windowInFocus = false,
            else => {},
        }

        if (windowInFocus and updateMode.update == .poll and updateMode.update.poll.reportFPS) {
            // todo report fps
        }

        // === RENDER
        imev.animationEnabled = switch (updateMode.update) {
            .poll => |p| windowInFocus and p.animations,
            .wait => false,
        };

        imev.apply(event, &window);
        renderCount += 1;
        event = .empty;

        window.cursor = .default;
        if (imev.render) try window.clear(style.colors.window);

        var windowSize = try window.getSize();
        // ===

        window.debug.showClippingRects = updateMode.showClippingRects;

        try mainPage.render(&imev, style, windowSize.xy(0, 0), alloc);
        if (window.clippingRectangle()) |cr| @panic("Not supposed to have a clip rect.");

        // if (imev.internal.rerender) continue;
        // new events should not be pushed after a requested rerender.
        // is this necessary? is there any reason not to push new events after a rerender?
        event = window.pollEvent();
        if (event != .empty or imev.internal.rerender) continue;

        // do final render
        if (!imev.render) {
            imev.render = true;
            continue;
        }
        imev.render = false;

        if (updateMode.showRenderCount) {
            const msg = try std.fmt.allocPrint0(alloc, "{}", .{renderCount});
            defer alloc.free(msg);
            var renderText = try win.Text.init(style.fonts.standard, style.gui.text, msg, null, &window);
            defer renderText.deinit();
            try renderText.render(.{ .x = 0, .y = 0 });
            renderCount = 0;
        }
        window.present();
    }
}

test "" {
    std.meta.refAllDecls(@This());
}
