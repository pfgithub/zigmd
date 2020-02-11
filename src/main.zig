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
    },
    fonts: struct {
        standard: win.Font,
        bold: win.Font,
        italic: win.Font,
        bolditalic: win.Font,
    },
};

pub const HLColor = enum {
    text,
    control,
};

pub const HLFont = enum {
    normal,
    bold,
    italic,
    bolditalic,
};

pub const ParsingState = struct {
    bold: bool,
    italic: bool,
    const ModeProgress = union(enum) {
        stars: u8,
        backticks: u8,
        none: void,
        pub const Type = @TagType(@This());
    };
    modeProgress: ModeProgress,
    fn default() ParsingState {
        return ParsingState{
            .bold = false,
            .italic = false,
            .modeProgress = ModeProgress{ .none = {} },
        };
    }
    fn getFont(this: *ParsingState) HLFont {
        if (false) { // if is control character
            return HLFont.normal;
        }
        if (this.bold and this.italic) {
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
                    std.debug.warn("[unreachable] Stars: {}", .{stars});
                }
            },
            .backticks => |backticks| {
                // 1 = nothing, 3 = enter multiline code block
                std.debug.warn("[unreachable] Backticks: {}", .{backticks});
            },
            .none => {},
        }
        this.modeProgress = ModeProgress{ .none = {} };
    }
    fn handleCharacter(this: *ParsingState, char: u8) struct {
        font: HLFont,
        color: HLColor,
    } {
        // if state is multiline code block, ignore probably
        // or other similar things
        return switch (char) {
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
                        this.commitState();
                        this.modeProgress = ModeProgress{ .stars = 1 };
                    },
                }
                return .{ .color = .control, .font = .normal };
            },
            else => {
                this.commitState();
                return .{ .color = .text, .font = this.getFont() };
            },
        };
    }
};

const DrawCall = struct {
    current: [64:0]u8, // <rename this to text once refactor is available
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

pub const App = struct {
    scrollY: i32, // scrollX is only for individual parts of the UI, such as tables.
    alloc: *std.mem.Allocator,
    style: *const Style,
    cursorLocation: u64,
    text: []u8,
    textLength: u64,

    fn init(alloc: *std.mem.Allocator, style: *const Style) !App {
        var text = try alloc.alloc(u8, 100);
        errdefer alloc.deinit(text);
        const initialText = "Test! **Bold**.";
        std.mem.copy(u8, text, initialText);
        return App{
            .scrollY = 0,
            .alloc = alloc,
            .style = style,
            .cursorLocation = 1,
            .text = text,
            .textLength = initialText.len,
        };
    }
    fn deinit(app: *App) void {
        alloc.free(app.text);
    }

    fn getFont(app: *App, font: HLFont) *const win.Font {
        const style = app.style;
        return switch (font) {
            .normal => &style.fonts.standard,
            .bold => &style.fonts.bold,
            .italic => &style.fonts.italic,
            .bolditalic => &style.fonts.bolditalic,
        };
    }
    fn getColor(app: *App, color: HLColor) win.Color {
        const style = app.style;
        return switch (color) {
            .control => style.colors.control,
            .text => style.colors.text,
        };
    }

    fn performDrawCall(app: *App, window: *win.Window, drawCall: *DrawCall, pos: *win.Rect) !void {
        var font = app.getFont(drawCall.font);
        var color = app.getColor(drawCall.color);
        if (drawCall.index > 0) {
            try win.renderText(window, font, color, &drawCall.current, drawCall.x + pos.x, drawCall.y + pos.y, drawCall.size);
        }
    }

    fn backspace(app: *App, deleteStop: enum {
        Byte,
        Codepoint,
        Character,
        Word,
        Line,
    }) void {
        if (app.cursorLocation == 0) return;
        std.mem.copy(
            u8,
            app.text[app.cursorLocation - 1 .. app.textLength - 1],
            app.text[app.cursorLocation..app.textLength],
        );
        app.cursorLocation -= 1;
        app.textLength -= 1;
    }
    fn insert(app: *App, text: []const u8) void {
        if (app.textLength + text.len >= app.text.len) {
            var newText = app.alloc.realloc(app.text, app.text.len * 2) catch |e| switch (e) {
                std.mem.Allocator.Error.OutOfMemory => return, // could not insert text, out of memory. in the future, this could display an error on screen or reduce the memory usage of the text.
            };
            app.text = newText;
        }
        std.mem.copyBackwards(
            u8,
            app.text[app.cursorLocation + text.len .. app.textLength + text.len],
            app.text[app.cursorLocation..app.textLength],
        );
        std.mem.copy(u8, app.text[app.cursorLocation .. app.cursorLocation + text.len], text);
        app.cursorLocation += text.len;
        app.textLength += text.len;
    }

    fn render(app: *App, window: *win.Window, event: *win.Event, pos: *win.Rect) !void {
        const style = app.style;
        // loop over app.code
        // check scroll value
        // if the line height hasn't been calculated OR recalculate all is set, calculate it
        // if the recalculation is above the screen, increase the scroll by that number
        // if click and mouse position is within the character, set the cursor either before or after
        // if it fits on screen, render it

        try win.renderRect(window, style.colors.background, pos.*);

        var parsingState = ParsingState.default();

        var x: c_int = 0;
        var y: c_int = 0;
        var lineHeight: c_int = 10;

        var drawCall = DrawCall.Blank;

        var characterIndex: u64 = 0;

        switch (event.*) {
            .KeyDown => |keyev| switch (keyev.key) {
                // this will be handled by the keybinding resolver in the future.,
                .Left => {
                    // if (app.cursorLocation > 0) app.cursorLocation -= 1;
                    app.insert("(*text*)");
                },
                .Right => {
                    if (app.cursorLocation < 10000) app.cursorLocation += 1;
                },
                .Backspace => {
                    app.backspace(.Byte);
                },
                else => {},
            },
            else => {},
        }

        std.debug.warn("cursorLocation: {}, textLength: {}\n", .{ app.cursorLocation, app.textLength });

        var cursorRect: win.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

        for (app.text) |chara| {
            characterIndex += 1;
            if (characterIndex > app.textLength) break;
            var char: [2]u8 = .{ chara, 0 };
            var hl = parsingState.handleCharacter(char[0]);
            var hlColor = hl.color;
            var hlFont = hl.font;
            var charXL: c_int = undefined;
            var charXR: c_int = undefined;
            var charYU: c_int = undefined;
            var charYD: c_int = undefined;

            var font = app.getFont(hlFont);

            if (!drawCall.started) {
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
                    if (lineHeight < drawCall.size.h) lineHeight = drawCall.size.h;
                    // drawCall();
                    try app.performDrawCall(window, &drawCall, pos);
                    // init();
                    const textSize = try win.measureText(font, &char);

                    if (chara == '\n') {
                        charXL = 0;
                        charXR = 0;
                        charYU = y + lineHeight;
                        charYD = y + lineHeight + textSize.h;

                        y += lineHeight;
                        x = pos.x;
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

                        x = 0;
                        y += lineHeight;
                        lineHeight = 0;

                        const size = try win.measureText(font, &char);

                        charXL = x;
                        charXR = x + textSize.w;
                        charYU = y;
                        charYD = y + textSize.h;

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

            switch (event.*) {
                .MouseDown => |mouse| {
                    if (mouse.x > charXL and mouse.y > charYU) {
                        app.cursorLocation = characterIndex;
                    }
                },
                else => {},
            }

            if (app.cursorLocation == characterIndex) {
                // note: draw cursor above letters (last);
                // drawing:
                // measure all
                // draw highlights
                // draw letters
                // draw cursor
                // note: SDL_SetTextInputRect
                cursorRect = .{
                    .x = charXR - 1,
                    .y = charYU,
                    .w = 2,
                    .h = charYD - charYU,
                };
            }
        }
        if (drawCall.started) try app.performDrawCall(window, &drawCall, pos);
        try win.renderRect(window, style.colors.cursor, .{
            .x = cursorRect.x + pos.x,
            .y = cursorRect.y + pos.y,
            .w = cursorRect.w,
            .h = cursorRect.h,
        });
    }
};

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const stdout = &std.io.getStdOut().outStream().stream;
    try stdout.print("Hello, {}!\n", .{"world"});

    try win.init();
    defer win.deinit();

    var window = try win.Window.init();

    var standardFont = try win.Font.init("font/FreeSans.ttf");
    defer standardFont.deinit();
    var boldFont = try win.Font.init("font/FreeSansBold.ttf");
    defer boldFont.deinit();
    var italicFont = try win.Font.init("font/FreeSansOblique.ttf");
    defer italicFont.deinit();
    var boldItalicFont = try win.Font.init("font/FreeSansBoldOblique.ttf");
    defer boldItalicFont.deinit();

    var style = Style{
        .colors = .{
            .text = win.Color.rgb(255, 255, 255),
            .control = win.Color.rgb(128, 128, 128),
            .background = win.Color.hex(0x2e3440),
            .cursor = win.Color.rgb(128, 128, 255),
        },
        .fonts = .{
            .standard = standardFont,
            .bold = boldFont,
            .italic = italicFont,
            .bolditalic = boldItalicFont,
        },
    };

    std.debug.warn("Style: {}\n", .{style});

    var appV = try App.init(alloc, &style);
    var app = &appV;

    defer stdout.print("Quitting!\n", .{}) catch unreachable;

    // only if mode has raw text input flag set

    // if in foreground, loop pollevent
    // if in background, waitevent

    while (true) blk: {
        var event = try window.waitEvent();
        try stdout.print("Event: {}\n", .{event});
        switch (event) {
            .Quit => |event_| {
                return;
            },
            else => {},
        }

        try window.clear();
        var windowSize = try window.getSize();
        var size: win.Rect = .{
            .w = windowSize.w - 20,
            .h = windowSize.h - 20,
            .x = 10,
            .y = 10,
        };
        try app.render(&window, &event, &size);
        window.present();
    }
}
