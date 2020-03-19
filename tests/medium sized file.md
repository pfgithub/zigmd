not actual markdown, just a reasonably sized file to test with

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

        const measure = try win.measureText(adc.font, &adc.text);
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

// pub fn Cache(comptime handler: type) {
//     return struct {
//         const ThisCache = @This();
//         pub fn get(hash: [64]u8) !void {
//
//         }
//         pub fn clear() !void {
//
//         }
//     };
// }
//
// test "aa" {
//     const TextCache = Cache(struct {
//         pub fn ()
//     }, win.);
// }
// hashmap = std.AutoHashMap(key type, value type)
// for each item (.hit = false)
// use items (.hit = true)
// for each item (if !.hit, remove)

pub const App = struct {
    scrollY: i32, // scrollX is only for individual parts of the UI, such as tables.
    alloc: *std.mem.Allocator,
    style: *const Style,
    cursorLocation: usize,
    text: []u8,
    textLength: usize,
    readOnly: bool,
    filename: []const u8,

    fn init(alloc: *std.mem.Allocator, style: *const Style, filename: []const u8) !App {
        const loadErrorText = "File load error.";

        var readOnly = false;

        var file: []u8 = std.fs.cwd().readFileAlloc(alloc, filename, 10000) catch |e| blk: {
            std.debug.warn("File load error: {}", .{e});
            readOnly = true;
            break :blk try std.mem.dupe(alloc, u8, loadErrorText);
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
            .filename = filename,
        };
    }
    fn deinit(app: *App) void {
        alloc.free(app.text);
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

        var textInfo = try TextInfo.init(&arena, @intCast(u64, pos.w));
        for (app.text[0..app.textLength]) |char| {
            try textInfo.addCharacter(char, app);
        }
        try textInfo.commit();

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

        // ==== rendering ====

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
                try win.renderText(
                    window,
                    drawCall.font,
                    drawCall.color,
                    &drawCall.text,
                    drawCall.x + pos.x,
                    line.yTop + pos.y + (line.height - drawCall.measure.h),
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
            .linebg = win.Color.hex(0x3f4757),
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

    var appV = try App.init(alloc, &style, "README.md");
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


const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("SDL.h");
    @cInclude("SDL_ttf.h");
});
const std = @import("std");

// usingnamespace c ?

const RenderingError = error{
    SDLError,
    TTFError,
};

fn sdlError() RenderingError {
    _ = c.printf("SDL Method Failed: %s\n", c.SDL_GetError());
    return RenderingError.SDLError;
}

fn ttfError() RenderingError {
    _ = c.printf("TTF Method Failed: %s\n", c.TTF_GetError());
    return RenderingError.TTFError;
}

pub const Font = struct {
    sdlFont: *c.TTF_Font,
    pub fn init(ttfPath: [*c]const u8, size: u16) !Font {
        var font = c.TTF_OpenFont(ttfPath, size);
        if (font == null) return ttfError();
        errdefer c.TTF_CloseFont(font);

        return Font{
            .sdlFont = font.?,
        };
    }
    pub fn deinit(font: *Font) void {
        c.TTF_CloseFont(font.sdlFont);
    }
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return Color.rgba(r, g, b, 255);
    }
    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{ .r = r, .g = g, .b = b, .a = a };
    }
    pub fn hex(comptime color: u24) Color {
        return Color{
            .r = (color >> 16),
            .g = (color >> 8) & 0xFF,
            .b = color & 0xFF,
            .a = 0xFF,
        };
    }
    fn fromSDL(color: c.SDL_Color) Color {
        return Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
    fn toSDL(color: Color) c.SDL_Color {
        return c.SDL_Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
    fn equal(a: Color, b: Color) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
    }
};

pub const WindowSize = struct {
    w: u64,
    h: u64,
};

pub const Key = enum(u64) {
    Left,
    Right,
    Backspace,
    Return,
    Delete,
    Unknown,
    S,
    Escape,
};

pub const Event = union(enum) {
    Quit: void,
    pub const UnknownEvent = struct {
        type: u32,
    };
    Unknown: UnknownEvent,
    pub const KeyEvent = struct {
        key: Key,
    };
    KeyDown: KeyEvent,
    pub const MouseEvent = struct {
        x: i64,
        y: i64,
    };
    MouseDown: MouseEvent,
    MouseUp: MouseEvent,
    pub const MouseMotionEvent = struct {
        x: i64,
        y: i64,
    };
    MouseMotion: MouseMotionEvent,
    pub const TextInputEvent = struct {
        text: [100]u8,
        length: u32,
    };
    TextInput: TextInputEvent,
    fn fromSDL(event: c.SDL_Event) Event {
        return switch (event.type) {
            c.SDL_QUIT => Event{ .Quit = {} },
            c.SDL_KEYDOWN => Event{
                .KeyDown = .{
                    .key = switch (event.key.keysym.scancode) {
                        .SDL_SCANCODE_LEFT => .Left,
                        .SDL_SCANCODE_RIGHT => .Right,
                        .SDL_SCANCODE_BACKSPACE => .Backspace,
                        .SDL_SCANCODE_RETURN => .Return,
                        .SDL_SCANCODE_DELETE => .Delete,
                        .SDL_SCANCODE_S => .S,
                        .SDL_SCANCODE_ESCAPE => .Escape,
                        else => Key.Unknown,
                    },
                },
            },
            c.SDL_MOUSEBUTTONDOWN => Event{
                .MouseDown = .{
                    .x = event.button.x,
                    .y = event.button.y,
                },
            },
            c.SDL_MOUSEBUTTONUP => Event{
                .MouseUp = .{
                    .x = event.button.x,
                    .y = event.button.y,
                },
            },
            c.SDL_MOUSEMOTION => Event{
                .MouseMotion = .{
                    .x = event.motion.x,
                    .y = event.motion.y,
                },
            },
            c.SDL_TEXTINPUT => blk: {
                var text: [100]u8 = undefined;
                std.mem.copy(u8, &text, &event.text.text); // does the event.text.text memory get leaked? what happens to it?
                break :blk Event{
                    .TextInput = .{ .text = text, .length = @intCast(u32, c.strlen(&event.text.text)) },
                };
            },
            else => Event{ .Unknown = UnknownEvent{ .type = event.type } },
        };

        // if (event.type == c.SDL_QUIT) {
        //     break;
        // }
        // if (event.type == c.SDL_MOUSEMOTION) {
        //     try stdout.print("MouseMotion: {}\n", .{event.motion});
        // } else if (event.type == c.SDL_MOUSEWHEEL) {
        //     try stdout.print("MouseWheel: {}\n", .{event.wheel});
        // } else if (event.type == c.SDL_KEYDOWN) {
        //     // use for hotkeys
        //     try stdout.print("KeyDown: {} {}\n", .{ event.key.keysym.sym, event.key.keysym.mod });
        // } else if (event.type == c.SDL_TEXTINPUT) {
        //     // use for typing
        //     try stdout.print("TextInput: {}\n", .{event.text});
        // } else {
        //     try stdout.print("Event: {}\n", .{event.type});
        // }
    }
    pub const Type = @TagType(@This());
};

pub const Window = struct {
    sdlWindow: *c.SDL_Window,
    sdlRenderer: *c.SDL_Renderer,
    pub fn init() !Window {
        var window = c.SDL_CreateWindow(
            "hello_sdl2",
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            640,
            480,
            c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
        );
        if (window == null) return sdlError();
        errdefer c.SDL_DestroyWindow(window);

        var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED);
        if (renderer == null) return sdlError();
        errdefer c.SDL_DestroyRenderer(renderer);

        return Window{
            .sdlWindow = window.?,
            .sdlRenderer = renderer.?,
        };
    }
    pub fn deinit(window: *Window) void {
        c.SDL_DestroyRenderer(window.sdlRenderer);
        c.SDL_DestroyWindow(window.sdlWindow);
    }

    pub fn waitEvent(window: *Window) !Event {
        var event: c.SDL_Event = undefined;
        if (c.SDL_WaitEvent(&event) != 1) return sdlError();
        return Event.fromSDL(event);
    }

    pub fn clear(window: *Window) !void {
        if (c.SDL_SetRenderDrawColor(window.sdlRenderer, 0, 0, 0, 0) != 0) return sdlError();
        if (c.SDL_RenderClear(window.sdlRenderer) < 0) return sdlError();
    }
    pub fn present(window: *Window) void {
        c.SDL_RenderPresent(window.sdlRenderer);
    }
    pub fn getSize(window: *Window) !WindowSize {
        var screenWidth: c_int = undefined;
        var screenHeight: c_int = undefined;
        if (c.SDL_GetRendererOutputSize(window.sdlRenderer, &screenWidth, &screenHeight) < 0) return sdlError();
        return WindowSize{
            .w = @intCast(u64, screenWidth), // should never fail
            .h = @intCast(u64, screenHeight),
        };
    }
};

pub const TextSize = struct {
    w: u64,
    h: u64,
};
pub fn measureText(font: *const Font, text: [*c]const u8) !TextSize {
    var w: c_int = undefined;
    var h: c_int = undefined;
    if (c.TTF_SizeUTF8(font.sdlFont, text, &w, &h) < 0) return ttfError();
    return TextSize{ .w = @intCast(u64, w), .h = @intCast(u64, h) };
}

pub fn renderText(window: *const Window, font: *const Font, color: Color, text: [*c]const u8, x: u64, y: u64, size: TextSize) !void {
    var surface = c.TTF_RenderUTF8_Blended(font.sdlFont, text, color.toSDL());
    defer c.SDL_FreeSurface(surface);
    var texture = c.SDL_CreateTextureFromSurface(window.sdlRenderer, surface);
    defer c.SDL_DestroyTexture(texture);
    var rect = c.SDL_Rect{
        .x = @intCast(c_int, x),
        .y = @intCast(c_int, y),
        .w = @intCast(c_int, size.w),
        .h = @intCast(c_int, size.h),
    };
    if (c.SDL_RenderCopy(window.sdlRenderer, texture, null, &rect) < 0) return sdlError();
}

pub const Text = struct {
    texture: *c.SDL_Texture,
    size: TextSize,
    pub fn init(font: *const Font, color: Color, text: [*c]const u8, size: ?TextSize) !Text {
        var surface = c.TTF_RenderUTF8_Blended(font.sdlFont, text, color.toSDL());
        defer c.SDL_FreeSurface(surface);
        var texture = c.SDL_CreateTextureFromSurface(window.sdlRenderer, surface);
        errdefer c.SDL_DestroyTexture(texture);

        return .{
            .texture = texture,
            .size = if (size) |size| size else try measureText(font, text),
        };
    }
    pub fn deinit(text: *Text) void {
        c.SDL_DestroyTexture(text.texture);
    }
    pub fn render(text: *Text, window: *const Window) !void {
        var rect = c.SDL_Rect{
            .x = @intCast(c_int, x),
            .y = @intCast(c_int, y),
            .w = @intCast(c_int, text.size.w),
            .h = @intCast(c_int, text.size.h),
        };
        if (c.SDL_RenderCopy(window.sdlRenderer, texture, null, &rect) < 0) return sdlError();
    }
};

pub fn createText() !void {
    // create and return texture
}

pub fn renderText(window: *const Window, text: Text) !void {}

pub const Rect = struct {
    x: u64,
    y: u64,
    w: u64,
    h: u64,
    fn toSDL(rect: *const Rect) c.SDL_Rect {
        return c.SDL_Rect{
            .x = @intCast(c_int, rect.x),
            .y = @intCast(c_int, rect.y),
            .w = @intCast(c_int, rect.w),
            .h = @intCast(c_int, rect.h),
        };
    }
};
pub fn renderRect(window: *const Window, color: Color, rect: Rect) !void {
    if (rect.w == 0 or rect.h == 0) return;
    var sdlRect = rect.toSDL();
    if (c.SDL_SetRenderDrawColor(window.sdlRenderer, color.r, color.g, color.b, color.a) != 0) return sdlError();
    if (c.SDL_RenderFillRect(window.sdlRenderer, &sdlRect) != 0) return sdlError();
}

pub fn init() RenderingError!void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) return sdlError();
    errdefer c.SDL_Quit();

    if (c.TTF_Init() < 0) return sdlError();
    errdefer c.TTF_Quit();

    c.SDL_StartTextInput(); // todo
}

pub fn deinit() void {
    c.TTF_Quit();
    c.SDL_Quit();
}
