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
    },
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
        var screenSize = window.getSize();
        var screenWidth: c_int = screenSize.w;
        var screenHeight: c_int = screenSize.h;

        var x: c_int = 0;
        var y: c_int = 0;
        var lineHeight: c_int = 10;
        for ([_](*const [1:0]u8){ "m", "a", "r", "k", "d", "o", "w", "n", " ", "*", "*", "t", "e", "s", "t", "*", "*" }) |char| {
            if (char[0] == '\n') {
                x = 0;
                y += lineHeight;
                lineHeight = 10;
            } else {
                var font = style.fonts.standard;
                var textSize = try win.measureText(window, font, char);
                if (x + textSize.w > screenWidth) {
                    x = 0;
                    y += lineHeight;
                    lineHeight = 10;
                }
                var color = switch (char[0]) {
                    '*' => style.colors.control,
                    '\\' => style.colors.control,
                    else => style.colors.text,
                };
                try win.renderText(window, renderer, font, color.toSDL(), char, x, y, textSize);
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
        },
    };

     // only if mode has raw text input flag set

    // if in foreground, loop pollevent
    // if in background, waitevent
    var event: c.SDL_Event = undefined;
    while (c.SDL_WaitEvent(&event) != 0) {
        if (event.type == c.SDL_QUIT) {
            break;
        }
        if (event.type == c.SDL_MOUSEMOTION) {
            try stdout.print("MouseMotion: {}\n", .{event.motion});
        } else if (event.type == c.SDL_MOUSEWHEEL) {
            try stdout.print("MouseWheel: {}\n", .{event.wheel});
        } else if (event.type == c.SDL_KEYDOWN) {
            // use for hotkeys
            try stdout.print("KeyDown: {} {}\n", .{ event.key.keysym.sym, event.key.keysym.mod });
        } else if (event.type == c.SDL_TEXTINPUT) {
            // use for typing
            try stdout.print("TextInput: {}\n", .{event.text});
        } else {
            try stdout.print("Event: {}\n", .{event.type});
        }

        try window.clear();
        try app.render(window, &style);
        window.present();
    }

    try stdout.print("Quitting!\n", .{});
}
