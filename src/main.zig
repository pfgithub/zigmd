const std = @import("std");
pub const win = @import("./render.zig");
pub const parser = @import("./parser.zig");
pub const gui = @import("./gui.zig");
const List = std.SinglyLinkedList;
const ArrayList = std.ArrayList;

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
    body: []const u8,
    flags: []const u8,
};
pub const CharacterStop = union(enum) {
    byte: void,
    codepoint: void,
    character: void,
    word: void,
    line: void,
    regex: Regex,
    contextAware: void,
};
pub const LineStop = union(enum) {
    screen: void,
    file: void,
};

pub const Action = union(enum) {
    pub const Insert = struct {
        direction: Direction,
        mode: ActionMode,
        text: []const u8,

        fn apply(insert: *const Insert, app: *App) void {
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
    insert: Insert,
    pub const Delete = struct {
        direction: Direction,
        stop: CharacterStop,

        fn apply(delete: *const Delete, app: *App) void {
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
    delete: Delete,
    pub const MoveCursorLR = struct {
        direction: Direction,
        stop: CharacterStop,

        fn apply(moveCursorLR: *const MoveCursorLR, app: *App) void {
            const stopPos = app.findStop(moveCursorLR.stop, moveCursorLR.direction);
            app.cursorLocation = stopPos;
        }
    };
    moveCursorLR: MoveCursorLR,
    pub const MoveCursorUD = struct {
        direction: enum { up, down },
        mode: LineStop,
    };
    save: Save,
    pub const Save = struct {
        fn apply(save: *const Save, app: *App) void {
            app.saveFile();
        }
    };
};

const LineDrawCall = struct {
    text: [64]u8,
    textLength: u8,
    font: *const win.Font,
    color: win.Color,
    bg: ?win.Color, // to allow for rounded corners, backgrounds should probably kept in a sperate BackgroundDrawCall per-line. unfortunately, that means more text measurement because of how text measurement works, so not yet.
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
        try ti.appendCharacterPositionMeasure(0); // uh oh, this means clicking doesn't work properly. it should take the start x position and subtract from the x end position but default to 0 if it goes backwards
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
                try ti.addNewlineCharacter() // how does this work with bg styles? make a drawCall from current pos to eol for the style?
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
                result.kv.value = .{
                    .used = true,
                    .value = item,
                };
            }
            result.kv.value.used = true;
            return &result.kv.value.value;
        }
    };
}

pub const TextRenderInfo = struct {
    font: *const win.Font,
    color: win.Color,
    text: [64]u8,
    size: win.TextSize,
    window: *const win.Window,
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

pub const App = struct {
    scrollY: i32, // scrollX is only for individual parts of the UI, such as tables.
    alloc: *std.mem.Allocator,
    style: *const gui.Style,
    cursorLocation: usize,
    cursorRowCol: parser.RowCol,
    text: std.ArrayList(u8),
    readOnly: bool,
    filename: []const u8,
    tree: parser.Tree,
    textChanged: bool,
    textInfo: ?TextInfo,
    prevPos: ?win.Rect,

    textRenderCache: TextRenderCache,

    fn init(alloc: *std.mem.Allocator, style: *const gui.Style, filename: []const u8) !App {
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

        // const initialText = "Test! **Bold**.";
        return App{
            .scrollY = 0,
            .alloc = alloc,
            .style = style,
            .cursorLocation = 0,
            .cursorRowCol = .{ .row = 0, .col = 0 },
            .text = textList,
            .readOnly = readOnly,
            .filename = filename,
            .textRenderCache = textRenderCache,
            .tree = tree,
            .textChanged = true,
            .textInfo = null,
            .prevPos = null,
        };
    }
    fn deinit(app: *App) void {
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
            else => {
                std.debug.panic("not implemented", .{});
            },
        };
    }

    fn remeasureText(app: *App, pos: win.Rect) !void {
        // this logic took me way too long to figure out, that's why there is an empty if branch instead of if(!(...)) return
        if (app.textChanged or
            app.textInfo == null or
            app.prevPos == null or
            !std.meta.eql(pos, app.prevPos.?))
        {} else return;
        app.prevPos = pos;

        var cursor = parser.TreeCursor.init(app.tree.root());
        defer cursor.deinit();

        if (app.textInfo) |*ti| ti.deinit();
        app.textInfo = try TextInfo.init(app.alloc, pos.w, &cursor);
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
        app.textChanged = false;
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

    fn render(app: *App, window: *win.Window, imev: gui.ImEvent, fullArea: win.Rect) !void {
        try app.textRenderCache.clean();

        const pos: win.Rect = .{
            .x = fullArea.x + 20,
            .y = fullArea.y + 10,
            .w = fullArea.w - 40,
            .h = fullArea.h - 20,
        };

        const style = app.style;

        var arena = std.heap.ArenaAllocator.init(app.alloc);
        defer arena.deinit();

        var alloc = &arena.allocator;

        if (imev.keyDown) |kd| switch (kd) {
            .Left => {
                const action: Action = .{
                    .moveCursorLR = .{ .direction = .left, .stop = .codepoint },
                };
                action.moveCursorLR.apply(app);
            },
            .Right => {
                const action: Action = .{
                    .moveCursorLR = .{ .direction = .right, .stop = .codepoint },
                };
                action.moveCursorLR.apply(app);
            },
            .Backspace => {
                const action: Action = .{
                    .delete = .{ .direction = .left, .stop = .codepoint },
                };
                action.delete.apply(app);
            },
            .Return => {
                const action: Action = .{
                    .insert = .{ .direction = .left, .mode = .raw, .text = "\n" },
                };
                action.insert.apply(app);
            },
            .Delete => {
                const action: Action = .{
                    .delete = .{ .direction = .right, .stop = .codepoint },
                };
                action.delete.apply(app);
            },
            .Escape => {
                const action: Action = .{ .save = .{} };
                action.save.apply(app);
            },
            else => {},
        };
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

        app.tree.reparse(app.text.items);
        app.tree.lock();
        defer app.tree.unlock();

        try app.remeasureText(pos);
        const textInfo = app.textInfo.?;

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

        // ==== rendering ====

        if (fullArea.containsPoint(imev.cursor)) window.cursor = .ibeam;

        try window.pushClipRect(fullArea);
        defer window.popClipRect();

        try win.renderRect(window, style.colors.background, fullArea);

        for (textInfo.lines.items) |line| blk: {
            for (line.drawCalls.items) |drawCall| {
                if (line.yTop > pos.h) break :blk;
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
                if (line.yTop > fullArea.h) break :blk;
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
                try text.text.render(window, .{
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
            try win.renderRect(
                window,
                app.style.colors.cursor,
                .{
                    .x = cursorPosition.x + cursorPosition.w + pos.x,
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
            try text.render(window, .{
                .x = pos.x + pos.w - text.size.w,
                .y = pos.y + pos.h - text.size.h,
            });
        } else {
            // render cursor at position 0
        }
    }
};

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
            .window = win.Color.hex(0x11141a),
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

    var appV = try App.init(alloc, &style, "tests/b.md");
    defer appV.deinit();
    var app = &appV;

    defer std.debug.warn("Quitting!\n", .{});

    // only if mode has raw text input flag sethttps://thetravelers.online/leaderboard

    // if in foreground, loop pollevent
    // if in background, waitevent

    const Substructure = struct {
        four: Four,
        eight: Eight,
        pub const ModeData = struct {
            four: gui.Part(Four),
            eight: gui.Part(Eight),
        };
        const Four = enum { five, six, seven };
        const Eight = enum { nine, ten, eleven };
    };
    const UpdateMode = struct {
        pub const title_update = "Update Mode:";
        pub const title_another = "Another Option:";
        pub const title_three = "Three:";

        update: Update,
        reportFPS: ReportFPS,
        another: Another,
        three: Three,
        substructure: Substructure,
        pub const ModeData = struct {
            update: gui.Part(Update),
            reportFPS: gui.Part(ReportFPS),
            another: gui.Part(Another),
            three: gui.Part(Three),
            substructure: gui.Part(Substructure),
        };

        const Update = enum {
            wait,
            poll,
            pub const title_wait = "Wait for Events";
            pub const title_poll = "Update Constantly";
        };
        const ReportFPS = enum { no, yes };
        const Another = enum { choice1, choice2, choice3 };
        const Three = enum { yes };
    };
    var imedtr = gui.DataEditor(UpdateMode).init();
    defer imedtr.deinit();
    var updateMode: UpdateMode = .{
        .update = .wait,
        .reportFPS = .no,
        .another = .choice1,
        .three = .yes,
        .substructure = .{ .four = .five, .eight = .nine },
    };

    const DisplayMode = enum {
        editor,
        gui,
        pub const title_editor = "Editor";
        pub const title_gui = "GUI Demo";
    };
    var displayMode: DisplayMode = .editor;
    var displayedtr = gui.DataEditor(DisplayMode).init();
    defer displayedtr.deinit();

    var imev: gui.ImEvent = .{};

    var timer = try std.time.Timer.start();
    var frames: u64 = 0;

    while (true) blk: {
        var event = switch (updateMode.update) {
            .poll => try window.pollEvent(),
            .wait => try window.waitEvent(),
        };
        switch (event) {
            .Quit => return,
            else => {},
        }

        imev.rerender();
        while (imev.internal.rerender) {
            imev.apply(event);
            window.cursor = .default;

            try window.clear(style.colors.window);

            if (updateMode.reportFPS == .yes) {
                frames += 1;
                const time = timer.read();
                if (time >= 1000000000) {
                    std.debug.warn("FPS: {d}\n", .{@intToFloat(f32, frames) / (@intToFloat(f32, time) / 1000000000.0)});
                    timer.reset();
                    frames = 0;
                }
            } else {
                frames = 0;
            }

            var windowSize = try window.getSize();

            var yTop: i64 = 10;

            var displayModeOffset = try displayedtr.render(&displayMode, style, &window, &imev, .{ .w = windowSize.w, .x = 0, .y = yTop });
            yTop += displayModeOffset.h;

            var size: win.Rect = .{
                .x = 0,
                .y = yTop,
                .w = windowSize.w,
                .h = windowSize.h - yTop,
            };

            switch (displayMode) {
                .editor => {
                    try app.render(&window, imev, size);
                },
                .gui => {
                    _ = try imedtr.render(
                        &updateMode, // should this update in the return value instead of updating the item directly?
                        style,
                        &window,
                        &imev,
                        .{
                            .x = 40,
                            .y = yTop + gui.seperatorGap,
                            .w = windowSize.w - 80,
                        },
                    );
                },
            }

            event = .{ .Empty = {} };
        }

        window.present();
    }
}

test "" {
    std.meta.refAllDecls(@This());
}
