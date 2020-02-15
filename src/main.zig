const std = @import("std");
const win = @import("./rendering_abstraction.zig");
const List = std.SinglyLinkedList;
const ArrayList = std.ArrayList;

const CodeLine = struct {
    code: String,
    height: ?u32, // update whenever height is calculated, such as when rendering text
};
const CodeList = List([]CodeLine);
const String = ArrayList(u8);

pub const ImDataStore = struct {
    // data: Map(key: u128, value: *ImData)
    // get(key, default)
    // tick: finds any data that was not used last frame and deinits it
    //
    //eg: I don't remember the use case
    //
};

pub const ImGlobals = struct {
    // if(click) click = false // stopPropagation
};

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
    fn handleCharacter(this: *ParsingState, char: u8) struct {
        font: HLFont,
        color: HLColor,
    } {
        // if state is multiline code block, ignore probably
        // or other similar things
        if (this.escape) {
            this.escape = false;
            return switch (char) {
                '\\' => {
                    this.commitState();
                    return .{ .color = .text, .font = this.getFont() };
                },
                '*' => {
                    this.commitState();
                    return .{ .color = .text, .font = this.getFont() };
                },
                '`' => {
                    this.commitState();
                    return .{ .color = .text, .font = this.getFont() };
                },
                '#' => {
                    this.commitState();
                    return .{ .color = .text, .font = this.getFont() };
                },
                else => {
                    this.commitState();
                    return .{ .color = .errorc, .font = .normal };
                },
            };
        }
        return switch (char) {
            '\\' => {
                this.escape = true;
                this.commitState();
                return .{ .color = .control, .font = .normal };
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
                return .{ .color = .control, .font = .normal };
            },
            '#' => switch (this.modeProgress) {
                .hashtags => |hashtags| {
                    if (hashtags >= 6) {
                        this.commitState();
                    } else {
                        this.modeProgress = ModeProgress{ .hashtags = hashtags + 1 };
                    }
                    return .{ .color = .control, .font = .normal };
                },
                else => {
                    if (this.lineStart) {
                        this.modeProgress = ModeProgress{ .hashtags = 1 };
                        return .{ .color = .control, .font = .normal };
                    } else {
                        this.commitState();
                        return .{ .color = .text, .font = this.getFont() };
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
                return .{ .color = .text, .font = .normal };
            },
            else => {
                this.commitState();
                return .{ .color = .text, .font = this.getFont() };
            },
        };
    }
};

const DrawCall = struct {
    current: [64:0]u8,
    started: bool,

    index: u8,
    font: HLFont,
    color: HLColor,
    x: c_int,
    y: c_int,
    size: win.TextSize,

    const BlankText = [64:0]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    const Blank = DrawCall{
        .current = BlankText,
        .started = false,

        .index = undefined,
        .font = undefined,
        .color = undefined,
        .x = undefined,
        .y = undefined,
        .size = undefined,
    };

    pub fn init(drawCall: *DrawCall, font: HLFont, color: HLColor, x: c_int, y: c_int, size: win.TextSize) void {
        drawCall.* = .{
            .current = BlankText,
            .started = true,

            .index = 0,
            .font = font,
            .color = color,
            .x = x,
            .y = y,
            .size = size,
        };
    }

    pub fn clear(drawCall: *DrawCall) void {
        drawCall.* = DrawCall.Blank;
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
    };
    delete: Delete,
    pub const MoveCursorLR = struct {
        direction: Direction,
        stop: CharacterStop,
    };
    moveCursorLR: MoveCursorLR,
    pub const MoveCursorUD = struct {
        direction: enum { up, down },
        mode: LineStop,
    };
};

pub const App = struct {
    scrollY: i32, // scrollX is only for individual parts of the UI, such as tables.
    alloc: *std.mem.Allocator,
    style: *const Style,
    cursorLocation: u64,
    text: []u8,
    textLength: u64,
    readOnly: bool,

    fn init(alloc: *std.mem.Allocator, style: *const Style) !App {
        var text = try alloc.alloc(u8, 10000);
        errdefer alloc.free(text);

        var loadErrorText = try alloc.alloc(u8, 16);
        defer alloc.free(loadErrorText);
        std.mem.copy(u8, loadErrorText, "File load error.");

        var readOnly = false;

        var file: []u8 = std.fs.cwd().readFileAlloc(alloc, "README.md", 10000) catch |e| blk: {
            std.debug.warn("File load error: {}", .{e});
            readOnly = true;
            break :blk loadErrorText;
        };
        defer alloc.free(file);

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

    fn expandToFit(app: *App, finalLength: u64) !void {
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

    fn performDrawCall(app: *App, window: *win.Window, drawCall: *DrawCall, pos: *win.Rect) !void {
        var font = app.getFont(drawCall.font);
        var color = app.getColor(drawCall.color);
        if (drawCall.index > 0) {
            try win.renderText(window, font, color, &drawCall.current, drawCall.x + pos.x, drawCall.y + pos.y, drawCall.size);
        }
    }

    fn delete(app: *App, direction: Direction, deleteStop: CharacterStop) void {
        var shiftLength: u64 = switch (deleteStop) {
            .byte => 1,
            else => {
                std.debug.panic("Not supported yet :(", .{});
            },
        };

        switch (direction) {
            .left => {
                if (app.cursorLocation < shiftLength) {
                    shiftLength = app.cursorLocation;
                }
                if (shiftLength == 0) return;

                std.mem.copy(
                    u8,
                    app.text[app.cursorLocation - shiftLength .. app.textLength - shiftLength],
                    app.text[app.cursorLocation..app.textLength],
                );
                app.cursorLocation -= shiftLength;
                app.textLength -= shiftLength;
            },
            .right => {
                if (app.cursorLocation + shiftLength > app.textLength) {
                    shiftLength = app.textLength - app.cursorLocation;
                }
                if (shiftLength == 0) return;

                std.mem.copy(
                    u8,
                    app.text[app.cursorLocation..app.textLength],
                    app.text[app.cursorLocation + shiftLength .. app.textLength + shiftLength],
                );
                app.textLength -= shiftLength;
            },
        }
    }

    fn moveCursor(app: *App, direction: Direction, stop: CharacterStop) void {
        const moveDistance: u64 = switch (stop) {
            .byte => 1,
            else => {
                std.debug.panic("Not supported yet :(", .{});
            },
        };
        switch (direction) {
            .left => if (app.cursorLocation > 0) {
                if (app.cursorLocation > moveDistance) {
                    app.cursorLocation -= moveDistance;
                } else {
                    app.cursorLocation = 0;
                }
            },
            .right => if (app.cursorLocation < app.textLength) {
                if (app.cursorLocation + moveDistance < app.textLength) {
                    app.cursorLocation += moveDistance;
                } else {
                    app.cursorLocation = app.textLength;
                }
            },
        }
    }

    fn render(app: *App, window: *win.Window, event: *win.Event, pos: *win.Rect) !void {
        const style = app.style;
        // loop over app.code
        // check scroll value
        // if the line height hasn't been calculated OR recalculate all is set, calculate it
        // if the recalculation is above the screen, increase the scroll by that number
        // if click and mouse position is within the character, set the cursor either before or after
        // if it fits on screen, render it

        // find maximum line height for all lines
        // render text at the bottom of the line
        // render the cursor the entire line height
        // knowing the line height in advance makes it easier to fill background colors (selected line can have a different bg color)

        try win.renderRect(window, style.colors.background, pos.*);

        var parsingState = ParsingState.default();

        var x: c_int = 0;
        var y: c_int = 0;
        const minimumLineHeight = 8;
        var lineHeight: c_int = minimumLineHeight;

        var drawCall = DrawCall.Blank;

        var characterEndIndex: u64 = 0;

        switch (event.*) {
            .KeyDown => |keyev| switch (keyev.key) {
                // this will be handled by the keybinding resolver in the future.,
                .Left => {
                    app.moveCursor(.left, .byte);
                },
                .Right => {
                    app.moveCursor(.right, .byte);
                },
                .Backspace => {
                    app.delete(.left, .byte);
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
                    app.delete(.right, .byte);
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

        // std.debug.warn("cursorLocation: {}, textLength: {}\n", .{ app.cursorLocation, app.textLength });

        var cursorRect: win.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

        for (app.text) |chara| {
            if (y > pos.h) break;
            characterEndIndex += 1;
            if (characterEndIndex > app.textLength) break;
            var char: [2]u8 = .{ chara, 0 };
            var hl = parsingState.handleCharacter(char[0]);
            var hlColor = hl.color;
            var hlFont = hl.font;
            var charXL: c_int = undefined;
            var charXR: c_int = undefined;
            var charYU: c_int = undefined;
            var charYD: c_int = undefined;

            var font = app.getFont(hlFont);

            if (!drawCall.started and chara != '\n') {
                const size = try win.measureText(font, &char);

                charXL = x;
                charXR = x + size.w;
                charYU = y;
                charYD = y + size.h;

                drawCall.init(hlFont, hlColor, x, y, size);
                drawCall.current[drawCall.index] = char[0];
                drawCall.index += 1;
            } else {
                if (drawCall.font != hlFont or drawCall.color != hlColor or drawCall.index >= 63 or chara == '\n') {
                    x += drawCall.size.w;
                    if (drawCall.size.h > lineHeight) lineHeight = drawCall.size.h;
                    // drawCall();
                    try app.performDrawCall(window, &drawCall, pos);
                    // init();
                    const textSize = try win.measureText(font, &char);

                    if (chara == '\n') {
                        charXL = 0;
                        charXR = 0;
                        charYU = y + lineHeight;
                        charYD = y + lineHeight + minimumLineHeight;

                        y += lineHeight;
                        x = 0;

                        lineHeight = minimumLineHeight;

                        drawCall.clear();
                    } else {
                        charXL = x;
                        charXR = x + textSize.w;
                        charYU = y;
                        charYD = y + textSize.h;

                        drawCall.init(hlFont, hlColor, x, y, textSize);
                        drawCall.current[drawCall.index] = char[0];
                        drawCall.index += 1;
                    }
                } else {
                    // append current
                    drawCall.current[drawCall.index] = char[0];
                    drawCall.index += 1;
                    const textSize = try win.measureText(font, &drawCall.current);

                    if (x + textSize.w > pos.w) {
                        drawCall.index -= 1;
                        drawCall.current[drawCall.index] = 0; // undo
                        try app.performDrawCall(window, &drawCall, pos);

                        if (drawCall.size.h > lineHeight) lineHeight = drawCall.size.h;

                        x = 0;
                        y += lineHeight;
                        lineHeight = minimumLineHeight;

                        const size = try win.measureText(font, &char);

                        charXL = x;
                        charXR = x + size.w;
                        charYU = y;
                        charYD = y + minimumLineHeight;

                        drawCall.init(hlFont, hlColor, x, y, size);
                        drawCall.current[drawCall.index] = char[0];
                        drawCall.index += 1;
                    } else {
                        charXL = x + drawCall.size.w;
                        charXR = x + textSize.w;
                        charYU = y;
                        charYD = y + textSize.h;

                        drawCall.size = textSize;
                    }
                }
            }

            // try win.renderRect(window, style.colors.control, .{
            //     .x = charXR - 1 + pos.x,
            //     .y = charYU + pos.y,
            //     .w = 2,
            //     .h = charYD - charYU,
            // });

            switch (event.*) {
                .MouseDown => |mouse| blk: {
                    if (mouse.y < pos.y or mouse.y > pos.y + pos.h or mouse.x < pos.x or mouse.x > pos.x + pos.w) {
                        break :blk;
                    } else if (mouse.x - pos.x > (charXL + @divFloor((charXR - charXL), 2)) and mouse.y > charYU + pos.y) {
                        app.cursorLocation = characterEndIndex;
                    } else if (characterEndIndex == 1) {
                        app.cursorLocation = 0;
                    }
                },
                else => {},
            }

            if (app.cursorLocation == characterEndIndex) {
                // note: draw cursor above letters (last);
                // drawing:
                // measure all
                // draw highlights
                // draw letters
                // draw cursor
                cursorRect = .{
                    .x = charXR - 1,
                    .y = charYU,
                    .w = 2,
                    .h = charYD - charYU,
                };
            } else if (characterEndIndex == 1 and app.cursorLocation == 0) {
                cursorRect = .{
                    .x = charXL - 1,
                    .y = charYU,
                    .w = 2,
                    .h = charYD - charYU,
                };
            }
        }
        if (drawCall.started) try app.performDrawCall(window, &drawCall, pos);
        // note: SDL_SetTextInputRect
        try win.renderRect(window, style.colors.cursor, .{
            .x = cursorRect.x + pos.x,
            .y = cursorRect.y + pos.y,
            .w = cursorRect.w,
            .h = cursorRect.h,
        });
        // win.setTextInputRect(window, .{})
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
