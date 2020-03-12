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
    },
    fonts: struct {
        standard: win.Font,
        bold: win.Font,
        italic: win.Font,
        bolditalic: win.Font,
        heading: win.Font,
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
    const ModeProgress = union(enum) {
        stars: u8,
        backticks: u8,
        hashtags: u8,
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
        };
    }
    fn getFont(this: *ParsingState) HLFont {
        if (false) { // if is control character
            return HLFont.normal;
        }
        if (this.heading > 0) {
            return HLFont.heading;
        } else if (this.bold and this.italic) {
            return HLFont.bolditalic;
        } else if (this.bold) {
            return HLFont.bold;
        } else if (this.italic) {
            return HLFont.italic;
        } else {
            return HLFont.normal;
        }
    }
    fn commitState(this: *ParsingState) void {
        switch (this.modeProgress) {
            .stars => |stars| {
                if (stars == 1) {
                    this.italic = !this.italic;
                } else if (stars == 2) {
                    this.bold = !this.bold;
                } else if (stars == 3) {
                    this.italic = !this.italic;
                    this.bold = !this.bold;
                } else {
                    std.debug.panic("[unreachable] Stars: {}", .{stars});
                }
            },
            .backticks => |backticks| {
                // 1 = nothing, 3 = enter multiline code block
                std.debug.panic("[unreachable] Backticks: {}", .{backticks});
            },
            .hashtags => |hashtags| {
                this.heading = hashtags;
            },
            .none => {},
        }
        this.modeProgress = ModeProgress{ .none = {} };
        this.lineStart = false;
    }
    fn handleCharacter(this: *ParsingState, char: u8) union(enum) {
        text: TextHLStyle, flow: enum { newline }
    } {
        // if state is multiline code block, ignore probably
        // or other similar things
        if (this.escape) {
            this.escape = false;
            return switch (char) {
                '\\' => {
                    // if(next is valid)
                    this.commitState();
                    return .{ .text = .{ .color = .text, .font = this.getFont() } };
                },
                '*' => {
                    this.commitState();
                    return .{ .text = .{ .color = .text, .font = this.getFont() } };
                },
                '`' => {
                    this.commitState();
                    return .{ .text = .{ .color = .text, .font = this.getFont() } };
                },
                '#' => {
                    this.commitState();
                    return .{ .text = .{ .color = .text, .font = this.getFont() } };
                },
                '\n' => {
                    this.heading = 0;
                    this.commitState();
                    this.lineStart = true;
                    this.bold = false;
                    this.italic = false;
                    this.escape = false;
                    return .{ .flow = .newline };
                },
                else => {
                    this.commitState();
                    return .{ .text = .{ .color = .errorc, .font = .normal } };
                },
            };
        }
        return switch (char) {
            '\\' => {
                this.escape = true;
                this.commitState();
                return .{ .text = .{ .color = .control, .font = .normal } };
            },
            '*' => {
                switch (this.modeProgress) {
                    .stars => |stars| {
                        if (stars >= 3) {
                            this.commitState();
                            this.modeProgress = ModeProgress{ .stars = 1 };
                        } else {
                            this.modeProgress = ModeProgress{ .stars = stars + 1 };
                        }
                    },
                    else => {
                        this.modeProgress = ModeProgress{ .stars = 1 };
                    },
                }
                return .{ .text = .{ .color = .control, .font = .normal } };
            },
            '#' => switch (this.modeProgress) {
                .hashtags => |hashtags| {
                    if (hashtags >= 6) {
                        this.commitState();
                    } else {
                        this.modeProgress = ModeProgress{ .hashtags = hashtags + 1 };
                    }
                    return .{ .text = .{ .color = .control, .font = .normal } };
                },
                else => {
                    if (this.lineStart) {
                        this.modeProgress = ModeProgress{ .hashtags = 1 };
                        return .{ .text = .{ .color = .control, .font = .normal } };
                    } else {
                        this.commitState();
                        return .{ .text = .{ .color = .text, .font = this.getFont() } };
                    }
                },
            },
            '\n' => {
                this.heading = 0;
                this.commitState();
                this.lineStart = true;
                this.bold = false;
                this.italic = false;
                this.escape = false;
                return .{ .flow = .newline };
            },
            else => {
                this.commitState();
                return .{ .text = .{ .color = .text, .font = this.getFont() } };
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
            .text = [64]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
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
        var characterMeasure = try win.measureText(font, &singleCharacter);
        try ti.appendCharacterPositionMeasure(characterMeasure.w);
    }

    fn appendCharacterPositionMeasure(ti: *TextInfo, width: u64) !void {
        var lineOverX = blk: {
            var latestDrawCall = &ti.progress.activeDrawCall;
            break :blk if (latestDrawCall.*) |ldc| (try win.measureText(ldc.font, &ldc.text)).w else 0;
        };

        try ti.characterPositions.append(.{
            .x = lineOverX + ti.progress.x,
            .w = width,
            .line = &ti.lines.items[ti.lines.len - 1],
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

    fn addCharacter(ti: *TextInfo, char: u8, app: *App) !void {
        var hl = ti.parsingState.handleCharacter(char);

        switch (hl) {
            .flow => |f| switch (f) {
                .newline => {
                    try ti.addNewlineCharacter();
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

        const measure = try win.measureText(latestDrawCall.font, &textCopy);
        if (@intCast(u64, measure.w) + latestDrawCall.x >= ti.maxWidth) {
            // start new line
            // try again
            try ti.addNewlineCharacter();
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

        const measure = try win.measureText(adc.font, &adc.text);
        adc.measure = .{ .w = @intCast(u64, measure.w), .h = @intCast(u64, measure.h) };

        var latestLine = &ti.lines.items[ti.lines.len - 1];
        if (latestLine.height < adc.measure.h) latestLine.height = adc.measure.h;
        try latestLine.drawCalls.append(adc);
        ti.progress.x += @intCast(u64, adc.measure.w);
    }

    /// start a new line
    fn addNewlineCharacter(ti: *TextInfo) !void {
        try ti.commit();

        var latestLine = &ti.lines.items[ti.lines.len - 1];
        var nextLine = LineInfo.init(ti.arena, latestLine.height + latestLine.yTop, 10);
        ti.progress.x = 0;
        try ti.lines.append(nextLine);

        try ti.appendCharacterPositionMeasure(0); // newline has 0 width and is the first character of the line
    }
};

pub const App = struct {
    scrollY: i32, // scrollX is only for individual parts of the UI, such as tables.
    alloc: *std.mem.Allocator,
    style: *const Style,
    cursorLocation: usize,
    text: []u8,
    textLength: usize,
    readOnly: bool,

    fn init(alloc: *std.mem.Allocator, style: *const Style) !App {
        var loadErrorText = try std.mem.dupe(alloc, u8, "File load error.");
        defer alloc.free(loadErrorText);

        var readOnly = false;

        var file: []u8 = std.fs.cwd().readFileAlloc(alloc, "README.md", 10000) catch |e| blk: {
            std.debug.warn("File load error: {}", .{e});
            readOnly = true;
            break :blk loadErrorText;
        };
        defer alloc.free(file);

        var text = try alloc.alloc(u8, file.len * 2);
        errdefer alloc.free(text);

        std.mem.copy(u8, text, file);
        const textLength = file.len;

        // const initialText = "Test! **Bold**.";
        return App{
            .scrollY = 0,
            .alloc = alloc,
            .style = style,
            .cursorLocation = 1,
            .text = text,
            .textLength = textLength,
            .readOnly = readOnly,
        };
    }
    fn deinit(app: *App) void {
        alloc.free(app.text);
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
        const style = app.style;

        var arena = std.heap.ArenaAllocator.init(app.alloc);
        defer arena.deinit();

        var alloc = &arena.allocator;

        try win.renderRect(window, style.colors.background, pos.*);

        switch (event.*) {
            .KeyDown => |keyev| switch (keyev.key) {
                // this will be handled by the keybinding resolver in the future.,
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

        var textInfo = try TextInfo.init(&arena, @intCast(u64, pos.w));
        for (app.text[0..app.textLength]) |char| {
            try textInfo.addCharacter(char, app);
        }
        try textInfo.commit();

        for (textInfo.lines.toSliceConst()) |line| {
            for (line.drawCalls.toSliceConst()) |drawCall| {
                try win.renderText(
                    window,
                    drawCall.font,
                    drawCall.color,
                    &drawCall.text,
                    drawCall.x + pos.x,
                    line.yTop + pos.y + (line.height - drawCall.measure.h), // + (line.height - call.height) // seems we forgot about the height..
                    .{ .w = drawCall.measure.w, .h = drawCall.measure.h },
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
    }
};

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const stdout = &std.io.getStdOut().outStream().stream;
    try stdout.print("Hello, {}!\n", .{"world"});

    try win.init();
    defer win.deinit();

    var window = try win.Window.init();

    var standardFont = try win.Font.init("font/FreeSans.ttf", 16);
    defer standardFont.deinit();
    var boldFont = try win.Font.init("font/FreeSansBold.ttf", 16);
    defer boldFont.deinit();
    var italicFont = try win.Font.init("font/FreeSansOblique.ttf", 16);
    defer italicFont.deinit();
    var boldItalicFont = try win.Font.init("font/FreeSansBoldOblique.ttf", 16);
    defer boldItalicFont.deinit();
    var headingFont = try win.Font.init("font/FreeSansBold.ttf", 24);
    defer headingFont.deinit();

    var style = Style{
        .colors = .{
            .text = win.Color.rgb(255, 255, 255),
            .control = win.Color.rgb(128, 128, 128),
            .background = win.Color.hex(0x2e3440),
            .cursor = win.Color.rgb(128, 128, 255),
            .special = win.Color.rgb(128, 255, 128),
            .errorc = win.Color.rgb(255, 128, 128),
        },
        .fonts = .{
            .standard = standardFont,
            .bold = boldFont,
            .italic = italicFont,
            .bolditalic = boldItalicFont,
            .heading = headingFont,
        },
    };

    std.debug.warn("Style: {}\n", .{style});

    var appV = try App.init(alloc, &style);
    var app = &appV;

    defer stdout.print("Quitting!\n", .{}) catch unreachable;

    // only if mode has raw text input flag sethttps://thetravelers.online/leaderboard

    // if in foreground, loop pollevent
    // if in background, waitevent

    while (true) blk: {
        var event = try window.waitEvent();
        // try std.debug.warn("Event: {}\n", .{event});
        switch (event) {
            .Quit => |event_| {
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
