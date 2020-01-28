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
    control
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
        return ParsingState {
            .bold = false,
            .italic = false,
            .modeProgress = ModeProgress{.none = {}},
        };
    }
    fn getFont(this: *ParsingState) HLFont {
        if(this.bold and this.italic){
            return HLFont.bolditalic;
        }else if(this.bold){
            return HLFont.bold;
        }else if(this.italic){
            return HLFont.italic;
        }else{
            return HLFont.normal;
        }
    }
    fn commitState(this: *ParsingState) void {
        switch(this.modeProgress) {
            .stars => |stars| {
                if(stars == 1) {
                    this.italic =! this.italic;
                }else if(stars == 2){
                    this.bold =! this.bold;
                }else if(stars == 3){
                    this.italic =! this.italic;
                    this.bold =! this.bold;
                }else{
                    std.debug.warn("[unreachable] Stars: {}", .{stars});
                }
            },
            .backticks => |backticks| {
                // 1 = nothing, 3 = enter multiline code block
                std.debug.warn("[unreachable] Backticks: {}", .{backticks});
            },
            .none => {},
        }
        this.modeProgress = ModeProgress {.none = {}};
    }
    fn handleCharacter(this: *ParsingState, char: u8) HLColor {
        // if state is multiline code block, ignore probably
        // or other similar things
        return switch(char) {
            '*' => {
                switch(this.modeProgress) {
                    .stars => |stars| {
                        if(stars >= 3){
                            this.commitState();
                            this.modeProgress = ModeProgress {.stars = 1};
                        }else{
                            this.modeProgress = ModeProgress {.stars = stars + 1};
                        }
                    },
                    else => {
                        this.commitState();
                        this.modeProgress = ModeProgress {.stars = 1};
                    }
                }
                return HLColor.control;
            },
            else => {
                this.commitState();
                return HLColor.text;
            },
        };
    }
};

pub const App = struct {
    code: CodeList,
    scrollY: i32, // scrollX is only for individual parts of the UI, such as tables.
    alloc: *std.mem.Allocator,
    fn init(alloc: *std.mem.Allocator) App {
        return .{
            .code = CodeList.init(),
            .scrollY = 0,
            .alloc = alloc,
        };
    }
    fn deinit(app: *App) void {}

    fn render(app: *App, window: *win.Window, style: *const Style) !void {
        // loop over app.code
        // check scroll value
        // if the line height hasn't been calculated OR recalculate all is set, calculate it
        // if the recalculation is above the screen, increase the scroll by that number
        // if click and mouse position is within the character, set the cursor either before or after
        // if it fits on screen, render it
        var screenSize = try window.getSize();
        var screenWidth: c_int = screenSize.w;
        var screenHeight: c_int = screenSize.h;

        var parsingState = ParsingState.default();

        var x: c_int = 0;
        var y: c_int = 0;
        var lineHeight: c_int = 10;
        for ([_](*const [1:0]u8){ "m", "a", "r", "k", "d", "o", "w", "n", " ", "*", "*", "t", "e", "s", "t", "*", "*", " ", "*", "i", "t", "a", "l", "i", "c", "*", "*", "b", "o", "l", "d", "i", "t", "a", "l", "i", "c", "*", "b", "o", "l", "d", "*", "*", "." }) |char| {
            if (char[0] == '\n') {
                x = 0;
                y += lineHeight;
                lineHeight = 10;
            } else {
                // the font rendering library knows better than us how to kern things
                // draws should be batched into words, only splitting if the font changes
                // or if the size is too high.
                var hlColor = parsingState.handleCharacter(char[0]);

                var font = if(hlColor == .control) &style.fonts.standard
                else switch(parsingState.getFont()) {
                    .normal => &style.fonts.standard,
                    .bold => &style.fonts.bold,
                    .italic => &style.fonts.italic,
                    .bolditalic => &style.fonts.bolditalic,
                };
                var textSize = try win.measureText(font, char);
                if (x + textSize.w > screenWidth) {
                    x = 0;
                    y += lineHeight;
                    lineHeight = 10;
                }
                var color = switch (hlColor) {
                    .control => style.colors.control,
                    .text => style.colors.text,
                };
                try win.renderText(window, font, color, char, x, y, textSize);
                x += textSize.w;
                if (lineHeight < textSize.h) lineHeight = textSize.h;
            }
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

    var standardFont = try win.Font.init("font/FreeSans.ttf");
    defer standardFont.deinit();
    var boldFont = try win.Font.init("font/FreeSansBold.ttf");
    defer boldFont.deinit();
    var italicFont = try win.Font.init("font/FreeSansOblique.ttf");
    defer italicFont.deinit();
    var boldItalicFont = try win.Font.init("font/FreeSansBoldOblique.ttf");
    defer boldItalicFont.deinit();

    var appV = App.init(alloc);
    var app = &appV;

    var style = Style{
        .colors = .{
            .text = win.Color.rgb(255, 255, 255),
            .control = win.Color.rgb(128, 128, 128),
            .background = win.Color.rgb(0, 0, 0),
        },
        .fonts = .{
            .standard = standardFont,
            .bold = boldFont,
            .italic = italicFont,
            .bolditalic = boldItalicFont,
        },
    };

    defer stdout.print("Quitting!\n", .{}) catch unreachable;

     // only if mode has raw text input flag set

    // if in foreground, loop pollevent
    // if in background, waitevent

    while (true) blk: {
        var event = try window.waitEvent();
        switch(event) {
            .Quit => |event_| {
                try stdout.print("QuitEvent: {}\n", .{event_});
                return;
            },
            .Unknown => |event_| { // !!! zig should allow |event| but doesn't here
                try stdout.print("UnknownEvent: {}\n", .{event_});
            },
        }

        try window.clear();
        try app.render(&window, &style);
        window.present();
    }
}
