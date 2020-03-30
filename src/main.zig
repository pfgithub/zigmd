const std = @import("std");
pub const win = @import("./rendering_abstraction.zig");
pub const parser = @import("./parser.zig");
const List = std.SinglyLinkedList;
const ArrayList = std.ArrayList;

pub const Style = struct {
    colors: struct {
        text: win.Color,
        control: win.Color,
        background: win.Color,
        cursor: win.Color,
        special: win.Color,
        errorc: win.Color,
        linebg: win.Color,
    },
    fonts: struct {
        standard: win.Font,
        bold: win.Font,
        italic: win.Font,
        bolditalic: win.Font,
        heading: win.Font,
        monospace: win.Font,
    },
};
pub const TextHLStyleReal = struct {
    font: *const win.Font,
    color: win.Color,
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
            // direction only affects where the cursor ends up
            // mode is not supported
            // copy text to the right
            {
                const newLength = app.textLength + insert.text.len;
                app.expandToFit(newLength) catch |e| switch (e) {
                    std.mem.Allocator.Error.OutOfMemory => return,
                };
                std.mem.copyBackwards(
                    u8,
                    app.text[app.cursorLocation + insert.text.len .. app.textLength + insert.text.len],
                    app.text[app.cursorLocation..app.textLength],
                );
                app.textLength = newLength;
            }

            {
                std.mem.copy(u8, app.text[app.cursorLocation .. app.cursorLocation + insert.text.len], insert.text);
            }

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

                const newLength = app.textLength - (right - left);
                std.mem.copy(u8, app.text[left..app.textLength], app.text[right..app.textLength]);
                app.textLength = newLength;

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
    measure: struct { w: u64, h: u64 },
    x: u64, // y is chosen based on line top, line height, and text baseline
    fn differentStyle(ldc: *LineDrawCall, hlStyle: TextHLStyleReal) bool {
        return hlStyle.font != ldc.font or !hlStyle.color.equal(ldc.color);
    }
};
const LineInfo = struct {
    yTop: u64,
    height: u64,
    drawCalls: std.ArrayList(LineDrawCall),
    fn init(arena: *std.heap.ArenaAllocator, yTop: u64, height: u64) LineInfo {
        var alloc = &arena.allocator;
        const drawCalls = std.ArrayList(LineDrawCall).init(alloc);

        return LineInfo{
            .yTop = yTop,
            .height = height,
            .drawCalls = drawCalls,
        };
    }
};
const CharacterPosition = struct {
    x: u64,
    w: u64,
    line: *LineInfo,
    index: u64,
    // y/h are determined by the line.
};
const TextInfo = struct {
    maxWidth: u64,
    lines: std.ArrayList(LineInfo),
    characterPositions: std.ArrayList(CharacterPosition),
    progress: struct {
        activeDrawCall: ?LineDrawCall,
        x: u64,
    },
    arena: *std.heap.ArenaAllocator,
    rootNode: parser.Node,
    // y/h must be determined by the line when drawing
    fn init(
        arena: *std.heap.ArenaAllocator,
        maxWidth: u64,
        rootNode: parser.Node,
    ) !TextInfo {
        var alloc = &arena.allocator;
        var lines = std.ArrayList(LineInfo).init(alloc);

        const characterPositions = std.ArrayList(CharacterPosition).init(alloc);

        try lines.append(LineInfo.init(arena, 0, 10));

        return TextInfo{
            .maxWidth = maxWidth,
            .lines = lines,
            .characterPositions = characterPositions,
            .progress = .{
                .activeDrawCall = null,
                .x = 0,
            },
            .arena = arena,
            .rootNode = rootNode,
        };
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

    fn appendCharacterPositionMeasure(ti: *TextInfo, width: u64) !void {
        var lineOverX = blk: {
            var latestDrawCall = &ti.progress.activeDrawCall;
            break :blk if (latestDrawCall.*) |ldc| (try win.Text.measure(ldc.font, &ldc.text)).w else 0;
        };

        try ti.characterPositions.append(.{
            .x = lineOverX + ti.progress.x,
            .w = width,
            .line = &ti.lines.items[ti.lines.len - 1],
            .index = ti.characterPositions.len,
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
        for ("·") |byte| {
            try ti.addRenderedCharacter(byte, hlStyle);
            _ = ti.characterPositions.pop();
        }
        try ti.appendCharacterPositionMeasure(0); // uh oh, this means clicking doesn't work properly. it should take the start x position and subtract from the x end position but default to 0 if it goes backwards
    }
    fn addCharacter(ti: *TextInfo, char: u8, app: *App) !void {
        var index = ti.characterPositions.len; // if this is not equal to the current character index, there are bigger issues.
        var renderStyle = parser.getNodeAtPosition(index, ti.rootNode).createClassesStruct().renderStyle();

        if (char == '\n') {
            try ti.addNewlineCharacter();
            return;
        }

        var style = app.getStyle(renderStyle);
        switch (renderStyle) {
            .display => |f| switch (f) {
                .eolSpace => {
                    try ti.addFakeCharacter("·", .{
                        .font = style.font,
                        .color = style.color,
                    });
                },
                .newline => {
                    try ti.addFakeCharacter("⏎", .{
                        .font = style.font,
                        .color = style.color,
                    });
                },
            },
            else => {
                try ti.addRenderedCharacter(char, .{
                    .font = style.font,
                    .color = style.color,
                });
            },
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
        if (@intCast(u64, measure.w) + latestDrawCall.x >= ti.maxWidth) {
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
        adc.measure = .{ .w = @intCast(u64, measure.w), .h = @intCast(u64, measure.h) };

        var latestLine = &ti.lines.items[ti.lines.len - 1];
        if (latestLine.height < adc.measure.h) latestLine.height = adc.measure.h;
        try latestLine.drawCalls.append(adc);
        ti.progress.x += @intCast(u64, adc.measure.w);
    }

    /// start a new line
    fn addNewlineCharacter(ti: *TextInfo) !void {
        try ti.addNewline();

        try ti.appendCharacterPositionMeasure(0);
        // newline has 0 width and is the first character of the line
    }
    fn addNewline(ti: *TextInfo) !void {
        try ti.commit();

        var latestLine = &ti.lines.items[ti.lines.len - 1];
        var nextLine = LineInfo.init(ti.arena, latestLine.height + latestLine.yTop, 10);
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
        pub fn deinit(cache: *ThisCache) ThisCache {
            while (it.next()) |next| {
                next.value.value.deinit();
            }
            cache.map.deinit();
            // uuh, this never gets called.
        }

        pub fn clean(cache: *ThisCache) !void {
            var toRemove = std.ArrayList(Key).init(cache.alloc);

            var it = cache.hashmap.iterator();
            while (it.next()) |next| {
                if (!next.value.used)
                    try toRemove.append(next.key);
                next.value.used = false;
            }

            for (toRemove.toSliceConst()) |key| {
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
    style: *const Style,
    cursorLocation: usize,
    text: []u8,
    textLength: usize,
    readOnly: bool,
    filename: []const u8,

    textRenderCache: TextRenderCache,

    fn init(alloc: *std.mem.Allocator, style: *const Style, filename: []const u8) !App {
        const loadErrorText = "File load error.";

        var readOnly = false;

        var file: []u8 = std.fs.cwd().readFileAlloc(alloc, filename, 10000000) catch |e| blk: {
            std.debug.warn("File load error: {}", .{e});
            readOnly = true;
            break :blk try std.mem.dupe(alloc, u8, loadErrorText);
        };
        defer alloc.free(file);

        var text = try alloc.alloc(u8, file.len * 2);
        errdefer alloc.free(text);

        std.mem.copy(u8, text, file);
        const textLength = file.len;

        const textRenderCache = TextRenderCache.init(alloc);
        errdefer textRenderCache.deinit();

        // const initialText = "Test! **Bold**.";
        return App{
            .scrollY = 0,
            .alloc = alloc,
            .style = style,
            .cursorLocation = 1,
            .text = text,
            .textLength = textLength,
            .readOnly = readOnly,
            .filename = filename,
            .textRenderCache = textRenderCache,
        };
    }
    fn deinit(app: *App) void {
        alloc.free(app.text);
        app.textRenderCache.deinit();
    }
    fn saveFile(app: *App) void {
        std.debug.warn("Save {}...", .{app.filename});
        std.fs.cwd().writeFile(app.filename, app.textSlice()) catch |e| @panic("not handled");
        std.debug.warn(" Saved\n", .{});
    }
    fn textSlice(app: *App) []const u8 {
        return app.text[0..app.textLength];
    }

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
                    if (app.cursorLocation + 1 < app.textLength) {
                        break :blk app.cursorLocation + 1;
                    } else {
                        break :blk app.textLength - 1;
                    }
                },
            },
            else => {
                std.debug.panic("not implemented", .{});
            },
        };
    }

    fn expandToFit(app: *App, finalLength: usize) !void {
        while (app.textLength + finalLength >= app.text.len) {
            var newText = try app.alloc.realloc(app.text, app.text.len * 2);
            app.text = newText;
        }
    }

    fn getStyle(app: *App, renderStyle: parser.RenderStyle) TextHLStyleReal {
        const style = app.style;
        const colors = &style.colors;
        const fonts = &style.fonts;
        return switch (renderStyle) {
            .control => .{
                .font = &fonts.monospace,
                .color = colors.control,
            },
            .text => |txt| switch (txt) {
                .bolditalic => TextHLStyleReal{
                    .font = &fonts.bolditalic,
                    .color = colors.text,
                },
                .bold => TextHLStyleReal{
                    .font = &fonts.bold,
                    .color = colors.text,
                },
                .italic => TextHLStyleReal{
                    .font = &fonts.italic,
                    .color = colors.text,
                },
                .normal => TextHLStyleReal{
                    .font = &fonts.standard,
                    .color = colors.text,
                },
            },
            .heading => .{
                .font = &style.fonts.heading,
                .color = colors.text,
            },
            .display => .{
                .font = &fonts.monospace,
                .color = colors.control,
            },
            .errort => .{
                .font = &fonts.monospace,
                .color = colors.errorc,
            },
        };
    }

    fn render(app: *App, window: *win.Window, event: *win.Event, pos: *win.Rect) !void {
        try app.textRenderCache.clean();

        var timer = try std.time.Timer.start();

        const style = app.style;

        var arena = std.heap.ArenaAllocator.init(app.alloc);
        defer arena.deinit();

        var alloc = &arena.allocator;

        switch (event.*) {
            .KeyDown => |keyev| switch (keyev.key) {
                .Left => {
                    const action: Action = .{
                        .moveCursorLR = .{
                            .direction = .left,
                            .stop = .byte,
                        },
                    };
                    action.moveCursorLR.apply(app);
                },
                .Right => {
                    const action: Action = .{
                        .moveCursorLR = .{
                            .direction = .right,
                            .stop = .byte,
                        },
                    };
                    action.moveCursorLR.apply(app);
                },
                .Backspace => {
                    const action: Action = .{
                        .delete = .{
                            .direction = .left,
                            .stop = .byte,
                        },
                    };
                    action.delete.apply(app);
                },
                .Return => {
                    const action: Action = .{
                        .insert = .{
                            .direction = .left,
                            .mode = .raw,
                            .text = "\n",
                        },
                    };
                    action.insert.apply(app);
                },
                .Delete => {
                    const action: Action = .{
                        .delete = .{
                            .direction = .right,
                            .stop = .byte,
                        },
                    };
                    action.delete.apply(app);
                },
                .Escape => {
                    const action: Action = .{
                        .save = .{},
                    };
                    action.save.apply(app);
                },
                else => {},
            },
            .TextInput => |textin| {
                const action: Action = .{
                    .insert = .{
                        .direction = .left,
                        .mode = .raw,
                        .text = textin.text[0..textin.length],
                    },
                };
                action.insert.apply(app);
            },
            else => {},
        }
        std.debug.warn("Handling took {}.\n", .{timer.read()});
        timer.reset();

        var tree = try parser.Tree.init(app.text);
        defer tree.deinit();

        var textInfo = try TextInfo.init(&arena, pos.w, tree.root());
        for (app.text[0..app.textLength]) |char| {
            try textInfo.addCharacter(
                char,
                app,
            );
        }
        try textInfo.commit();

        std.debug.warn("Measuring took {}.\n", .{timer.read()});
        timer.reset();

        switch (event.*) {
            .MouseDown => |mouse| blk: {
                if (mouse.y < pos.y or mouse.y > pos.y + pos.h or
                    mouse.x < pos.x or mouse.x > pos.x + pos.w)
                {
                    break :blk; // ignored,  out of area
                }
                for (textInfo.characterPositions.toSliceConst()) |cp| {
                    if (mouse.x - @intCast(i64, pos.x) > (cp.x + @divFloor((cp.w), 2)) and
                        mouse.y > cp.line.yTop + pos.y)
                    {
                        app.cursorLocation = cp.index + 1;
                    } else {}
                }
            },
            else => {},
        }

        std.debug.warn("Click handling took {}.\n", .{timer.read()});
        timer.reset();

        // ==== rendering ====

        try win.renderRect(window, style.colors.background, pos.*);

        if (app.cursorLocation > 0) {
            const cursorPosition = textInfo.characterPositions.items[app.cursorLocation - 1];
            try win.renderRect(
                window,
                app.style.colors.linebg,
                .{
                    .x = pos.x,
                    .y = cursorPosition.line.yTop + pos.y,
                    .w = pos.w,
                    .h = cursorPosition.line.height,
                },
            );
        } else {
            // render cursor at position 0
        }

        for (textInfo.lines.toSliceConst()) |line| blk: {
            for (line.drawCalls.toSliceConst()) |drawCall| {
                if (line.yTop > pos.h) break :blk;
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
                try text.text.render(
                    window,
                    drawCall.x + pos.x,
                    line.yTop +
                        pos.y +
                        (line.height - drawCall.measure.h),
                );
            }
        }

        if (app.cursorLocation > 0) {
            const cursorPosition = textInfo.characterPositions.items[app.cursorLocation - 1];
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
        } else {
            // render cursor at position 0
        }

        std.debug.warn("Rendering took {}.\n", .{timer.read()});
        timer.reset();
    }
};

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const loader = win.FontLoader.init();

    const stdout = &std.io.getStdOut().outStream().stream;
    try stdout.print("Hello, {}!\n", .{"world"});

    try win.init();
    defer win.deinit();

    var window = try win.Window.init();

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

    var style = Style{
        .colors = .{
            .text = win.Color.rgb(255, 255, 255),
            .control = win.Color.rgb(128, 128, 128),
            .background = win.Color.hex(0x2e3440),
            .cursor = win.Color.rgb(128, 128, 255),
            .special = win.Color.rgb(128, 255, 128),
            .errorc = win.Color.rgb(255, 128, 128),
            .linebg = win.Color.hex(0x3f4757),
        },
        .fonts = .{
            .standard = standardFont,
            .bold = boldFont,
            .italic = italicFont,
            .bolditalic = boldItalicFont,
            .heading = headingFont,
            .monospace = monospaceFont,
        },
    };

    std.debug.warn("Style: {}\n", .{style});

    var appV = try App.init(alloc, &style, "tests/demo file.md");
    var app = &appV;

    defer stdout.print("Quitting!\n", .{}) catch unreachable;

    // only if mode has raw text input flag sethttps://thetravelers.online/leaderboard

    // if in foreground, loop pollevent
    // if in background, waitevent

    while (true) blk: {
        var event = try window.waitEvent();
        // try std.debug.warn("Event: {}\n", .{event});
        switch (event) {
            .Quit => {
                return;
            },
            else => {},
        }

        try window.clear();
        var windowSize = try window.getSize();
        var size: win.Rect = .{
            .w = windowSize.w - 80,
            .h = windowSize.h - 80,
            .x = 40,
            .y = 40,
        };
        try app.render(&window, &event, &size);
        window.present();
    }
}

test "" {
    std.meta.refAllDecls(@This());
}
