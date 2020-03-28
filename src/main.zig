const std = @import("std");
pub const win = @import("./rendering_abstraction.zig");
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

pub const HLColor = enum {
    text,
    control,
    special,
    errorc,
};

pub const HLFont = enum {
    normal,
    bold,
    italic,
    bolditalic,
    heading,
    monospace,
};
pub const TextHLStyle = struct {
    font: HLFont,
    color: HLColor,
};
pub const TextHLStyleReal = struct {
    font: *const win.Font,
    color: win.Color,
};

pub const ParsingState = struct {
    bold: bool,
    italic: bool,
    heading: u8,
    lineStart: bool,
    escape: bool,
    inlineCode: bool,
    multilineCode: bool,
    nextError: bool,

    const ModeProgress = union(enum) {
        stars: u8,
        backticks: u8,
        hashtags: u8,
        newlines: bool,
        none: void,
        pub const Type = @TagType(@This());
    };
    modeProgress: ModeProgress,
    fn default() ParsingState {
        return ParsingState{
            .bold = false,
            .italic = false,
            .heading = 0,
            .lineStart = true,
            .escape = false,
            .modeProgress = ModeProgress{ .none = {} },
            .inlineCode = false,
            .multilineCode = false,
            .nextError = false,
        };
    }
    fn getFont(ps: *ParsingState) HLFont {
        return if (ps.multilineCode)
            HLFont.monospace
        else if (ps.inlineCode)
            HLFont.monospace
        else if (ps.heading > 0)
            HLFont.heading
        else if (ps.bold and ps.italic)
            HLFont.bolditalic
        else if (ps.bold)
            HLFont.bold
        else if (ps.italic)
            HLFont.italic
        else
            HLFont.normal;
    }
    fn commitState(state: *ParsingState) void {
        switch (state.modeProgress) {
            .stars => |stars| {
                if (stars == 1) {
                    state.italic = !state.italic;
                } else if (stars == 2) {
                    state.bold = !state.bold;
                } else if (stars == 3) {
                    state.italic = !state.italic;
                    state.bold = !state.bold;
                } else {
                    std.debug.panic("[unreachable] Stars: {}", .{stars});
                }
            },
            .backticks => |backticks| {
                if (backticks == 1) {
                    state.inlineCode = !state.inlineCode;
                } else if (backticks == 2) {
                    state.nextError = true;
                } else if (backticks == 3) {
                    state.nextError = true;
                    //state.multilineCode = !state.multilineCode;
                } else {
                    state.nextError = true;
                }
            },
            .hashtags => |hashtags| {
                state.heading = hashtags;
            },
            .newlines => |nl| {
                // do nothing
            },
            .none => {},
        }
        state.modeProgress = ModeProgress{ .none = {} };
        state.lineStart = false;
    }
    fn handleCharacter(state: *ParsingState, char: u8, next: ?u8) union(enum) {
        text: TextHLStyle, flow: enum { newline, nonewline }
    } {
        if (char == '\n') {
            if (next != null and next.? == '\n') {
                state.modeProgress = ModeProgress{ .newlines = true };
            } else {
                if (state.modeProgress != .newlines) state.commitState();
            }
            state.heading = 0;
            state.lineStart = true;
            state.bold = false;
            state.italic = false;
            state.escape = false;
            state.inlineCode = false;
            return if (state.modeProgress == .newlines) .{ .flow = .newline } else .{ .flow = .nonewline };
        }
        if (state.nextError) {
            state.nextError = false;
            return .{ .text = .{ .color = .errorc, .font = .normal } };
        }
        if (state.inlineCode) {
            state.commitState();
            if (char == '`') {
                state.modeProgress = .{ .backticks = 1 };
                return .{ .text = .{ .color = .control, .font = .normal } };
            }
            return .{ .text = .{ .color = .text, .font = state.getFont() } };
        }
        if (state.escape) {
            state.escape = false;
            return switch (char) {
                '\\' => {
                    // if(next is valid)
                    state.commitState();
                    return .{ .text = .{ .color = .text, .font = state.getFont() } };
                },
                '*' => {
                    state.commitState();
                    return .{ .text = .{ .color = .text, .font = state.getFont() } };
                },
                '`' => {
                    state.commitState();
                    return .{ .text = .{ .color = .text, .font = state.getFont() } };
                },
                '#' => {
                    state.commitState();
                    return .{ .text = .{ .color = .text, .font = state.getFont() } };
                },
                else => {
                    state.commitState();
                    return .{ .text = .{ .color = .errorc, .font = .normal } };
                },
            };
        }
        return switch (char) {
            '`' => {
                switch (state.modeProgress) {
                    .backticks => |backticks| {
                        state.modeProgress = ModeProgress{ .backticks = backticks + 1 };
                    },
                    else => {
                        state.modeProgress = ModeProgress{ .backticks = 1 };
                    },
                }
                return .{ .text = .{ .color = .control, .font = .normal } };
            },
            '\\' => {
                state.escape = true;
                state.commitState();
                return .{ .text = .{ .color = .control, .font = .normal } };
            },
            '*' => {
                switch (state.modeProgress) {
                    .stars => |stars| {
                        if (stars >= 3) {
                            state.commitState();
                            state.modeProgress = ModeProgress{ .stars = 1 };
                        } else {
                            state.modeProgress = ModeProgress{ .stars = stars + 1 };
                        }
                    },
                    else => {
                        state.modeProgress = ModeProgress{ .stars = 1 };
                    },
                }
                return .{ .text = .{ .color = .control, .font = .normal } };
            },
            '#' => switch (state.modeProgress) {
                .hashtags => |hashtags| {
                    if (hashtags >= 6) {
                        state.commitState();
                    } else {
                        state.modeProgress = ModeProgress{ .hashtags = hashtags + 1 };
                    }
                    return .{ .text = .{ .color = .control, .font = .normal } };
                },
                else => {
                    if (state.lineStart) {
                        state.modeProgress = ModeProgress{ .hashtags = 1 };
                        return .{ .text = .{ .color = .control, .font = .normal } };
                    } else {
                        state.commitState();
                        return .{ .text = .{ .color = .text, .font = state.getFont() } };
                    }
                },
            },
            else => {
                state.commitState();
                return .{ .text = .{ .color = .text, .font = state.getFont() } };
            },
        };
    }
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
    parsingState: ParsingState,
    // y/h must be determined by the line when drawing
    fn init(arena: *std.heap.ArenaAllocator, maxWidth: u64) !TextInfo {
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
            .parsingState = ParsingState.default(),
            .arena = arena,
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

    fn addCharacter(ti: *TextInfo, char: u8, next: ?u8, app: *App) !void {
        var hl = ti.parsingState.handleCharacter(char, next);

        switch (hl) {
            .flow => |f| switch (f) {
                .newline => {
                    try ti.addNewlineCharacter();
                },
                .nonewline => {
                    for ("⏎") |byte| {
                        try ti.addRenderedCharacter(byte, .{
                            .font = app.getFont(.normal),
                            .color = app.getColor(.control),
                            // .exists = false,
                        });
                        _ = ti.characterPositions.pop();
                    }
                    try ti.appendCharacterPositionMeasure(0); // uh oh, this means clicking doesn't work properly. it should take the start x position and subtract from the x end position but default to 0 if it goes backwards
                },
            },
            .text => |txt| {
                try ti.addRenderedCharacter(char, .{
                    .font = app.getFont(txt.font),
                    .color = app.getColor(txt.color),
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
        }

        pub fn clean(cache: *ThisCache) !void {
            var it = cache.hashmap.iterator();
            var toRemove = std.ArrayList(Key).init(cache.alloc);
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

    fn getFont(app: *App, font: HLFont) *const win.Font {
        const style = app.style;
        return switch (font) {
            .normal => &style.fonts.standard,
            .bold => &style.fonts.bold,
            .italic => &style.fonts.italic,
            .bolditalic => &style.fonts.bolditalic,
            .heading => &style.fonts.heading,
            .monospace => &style.fonts.monospace,
        };
    }
    fn getColor(app: *App, color: HLColor) win.Color {
        const style = app.style;
        return switch (color) {
            .control => style.colors.control,
            .text => style.colors.text,
            .special => style.colors.special,
            .errorc => style.colors.errorc,
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

        var textInfo = try TextInfo.init(&arena, pos.w);
        var i: usize = 0;
        for (app.text[0..app.textLength]) |char| {
            try textInfo.addCharacter(char, if (app.textLength > i + 1) app.text[i + 1] else null, app);
            i += 1;
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
