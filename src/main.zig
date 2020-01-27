const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("SDL.h");
    @cInclude("SDL_ttf.h");
});

const std = @import("std");
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

const TextSize = struct {
    w: c_int,
    h: c_int,
};

pub fn measureText(font: *c.TTF_Font, text: [*c]const u8) !TextSize {
    var w: c_int = undefined;
    var h: c_int = undefined;
    if (c.TTF_SizeUTF8(font, text, &w, &h) < 0) return ttfError();
    return TextSize{ .w = w, .h = h };
}

const Font = struct {
    fn init(ttfPath: []const u8) {}
    fn deinit() {}
};

const Init = struct {
    fn init(){
        
    }
    fn deinit(init: *Init){
        
    }
};

const Window = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    fn init(){
        
    }
    fn deinit(window: *Window) {
        
    }
    fn renderText(window: *Window, font: Font, color: Color, text: []const u8) {
        
    }
};

pub fn renderText(renderer: *c.SDL_Renderer, font: *c.TTF_Font, color: c.SDL_Color, text: [*c]const u8, x: c_int, y: c_int, size: TextSize) !void {
    var surface = c.TTF_RenderUTF8_Solid(font, text, color);
    defer c.SDL_FreeSurface(surface);
    var texture = c.SDL_CreateTextureFromSurface(renderer, surface);
    defer c.SDL_DestroyTexture(texture);
    var rect = c.SDL_Rect{
        .x = x,
        .y = y,
        .w = size.w,
        .h = size.h,
    };
    if (c.SDL_RenderCopy(renderer, texture, null, &rect) < 0) return sdlError();
}

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
    fn rgb(r: u8, g: u8, b: u8) Color {
        return Color.rgba(r, g, b, 255);
    }
    fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{ .r = r, .g = g, .b = b, .a = a };
    }
    fn fromSDL(color: c.SDL_Color) Color {
        return Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
    fn toSDL(color: Color) c.SDL_Color {
        return c.SDL_Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
};

pub const Style = struct {
    colors: struct {
        text: Color,
        control: Color,
        background: Color,
    },
    fonts: struct {
        standard: *c.TTF_Font,
        bold: *c.TTF_Font,
    },
};

pub const App = struct {
    code: CodeList,
    scrollY: i32, // scrollX is only for individual parts of the UI, such as tables.
    fn init() App {
        return .{
            .code = CodeList.init(),
            .scrollY = 0,
        };
    }
    fn deinit(app: *App) void {}

    fn render(app: *App, renderer: *c.SDL_Renderer, style: *const Style) !void {
        // loop over app.code
        // check scroll value
        // if the line height hasn't been calculated OR recalculate all is set, calculate it
        // if the recalculation is above the screen, increase the scroll by that number
        // if click and mouse position is within the character, set the cursor either before or after
        // if it fits on screen, render it
        var screenWidth: c_int = 0;
        var screenHeight: c_int = 0;
        
        // var renderAllocator = arena allocator
        // defer renderAllocator.deinit();
        // unfortunately we can't do this because sdl is written in c and uses malloc and free

        if (c.SDL_GetRendererOutputSize(renderer, &screenWidth, &screenHeight) < 0) return sdlError();

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
                var textSize = try measureText(font, char);
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
                try renderText(renderer, font, color.toSDL(), char, x, y, textSize);
                x += textSize.w;
                if (lineHeight < textSize.h) lineHeight = textSize.h;
            }
        }
    }
};

const SDLErrors = error{
    SDLError,
    TTFError,
};

fn sdlError() SDLErrors {
    _ = c.printf("SDL Method Failed: %s\n", c.SDL_GetError());
    return SDLErrors.SDLError;
}

fn ttfError() SDLErrors {
    _ = c.printf("TTF Method Failed: %s\n", c.TTF_GetError());
    return SDLErrors.TTFError;
}

pub fn main() !void {
    const stdout = &std.io.getStdOut().outStream().stream;
    try stdout.print("Hello, {}!\n", .{"world"});

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) return sdlError();
    defer c.SDL_Quit();

    if (c.TTF_Init() < 0) return sdlError();
    defer c.TTF_Quit();

    var window = c.SDL_CreateWindow("hello_sdl2", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 480, c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE);
    if (window == null) return sdlError();
    defer c.SDL_DestroyWindow(window);
    var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED);
    if (renderer == null) return sdlError();
    defer c.SDL_DestroyRenderer(renderer);

    var font = c.TTF_OpenFont("font/FreeSans.ttf", 24);
    if (font == null) return ttfError();
    var fontbold = c.TTF_OpenFont("font/FreeSans.ttf", 24);
    if (fontbold == null) return ttfError();

    var appV = App.init();
    var app = &appV;

    var style = Style{
        .colors = .{
            .text = Color.rgb(255, 255, 255),
            .control = Color.rgb(128, 128, 128),
            .background = Color.rgb(0, 0, 0),
        },
        .fonts = .{
            .standard = font.?,
            .bold = fontbold.?,
        },
    };

    c.SDL_StartTextInput();

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

        if (c.SDL_RenderClear(renderer) < 0) return sdlError();
        try app.render(renderer.?, &style);
        c.SDL_RenderPresent(renderer);
    }

    try stdout.print("Quitting!\n", .{});
}
