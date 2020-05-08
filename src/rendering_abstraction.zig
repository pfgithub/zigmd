const c = @import("./c.zig");
const std = @import("std");
const help = @import("./helpers.zig");

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

pub const FontLoader = struct {
    config: *c.FcConfig,
    pub fn init() FontLoader {
        return .{
            .config = c.FcInitLoadConfigAndFonts().?,
        };
    }
    pub fn deinit(loader: *FontLoader) void {
        c.FcConfigDestroy(loader.config);
    }
    pub fn loadFromName(
        loader: *const FontLoader,
        name: []const u8,
        fontSize: u16,
    ) !Font {
        return Font.loadFromName(loader, name, fontSize);
    }
};

pub const Font = struct {
    sdlFont: *c.TTF_Font,
    pub fn init(ttfPath: []const u8, size: u16) !Font {
        var font = c.TTF_OpenFont(ttfPath.ptr, size);
        if (font == null) return ttfError();
        errdefer c.TTF_CloseFont(font);

        return Font{
            .sdlFont = font.?,
        };
    }
    pub fn deinit(font: *Font) void {
        c.TTF_CloseFont(font.sdlFont);
    }
    pub fn loadFromName(
        loader: *const FontLoader,
        name: []const u8,
        fontSize: u16,
    ) !Font {
        var config = loader.config;
        var pattern = c.FcNameParse(name.ptr).?;
        defer c.FcPatternDestroy(pattern);

        // font size
        var v: c.FcValue = .{
            .type = @intToEnum(c.FcType, c.FcTypeInteger),
            .u = .{ .i = fontSize },
        };
        if (c.FcPatternAdd(pattern, c.FC_SIZE, v, c.FcTrue) == c.FcFalse)
            return error.FontConfigError;

        if (c.FcConfigSubstitute(
            config,
            pattern,
            @intToEnum(c.FcMatchKind, c.FcMatchPattern),
        ) == c.FcFalse)
            return error.OutOfMemory;
        c.FcDefaultSubstitute(pattern);

        var result: c.FcResult = undefined;
        if (c.FcFontMatch(config, pattern, &result)) |font| {
            defer c.FcPatternDestroy(font);
            var file: [*c]c.FcChar8 = null;
            if (c.FcPatternGetString(font, c.FC_FILE, 0, &file) ==
                @intToEnum(c.FcResult, c.FcResultMatch))
            {
                var resFont = Font.init(std.mem.span(file), fontSize);
                return resFont;
            }
        }
        return error.NotFound;
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
    w: i64,
    h: i64,
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
    pub fn fromSDL(sdlKey: var) Key {
        return switch (sdlKey) {
            .SDL_SCANCODE_LEFT => .Left,
            .SDL_SCANCODE_RIGHT => .Right,
            .SDL_SCANCODE_BACKSPACE => .Backspace,
            .SDL_SCANCODE_RETURN => .Return,
            .SDL_SCANCODE_DELETE => .Delete,
            .SDL_SCANCODE_S => .S,
            .SDL_SCANCODE_ESCAPE => .Escape,
            else => .Unknown,
        };
    }
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
    KeyUp: KeyEvent,
    pub const MouseEvent = struct {
        pos: Point,
    };
    MouseDown: MouseEvent,
    MouseUp: MouseEvent,
    pub const MouseMotionEvent = struct {
        pos: Point,
    };
    MouseMotion: MouseMotionEvent,
    pub const TextInputEvent = struct {
        text: [100]u8,
        length: u32,
    };
    TextInput: TextInputEvent,
    pub const EmptyEvent = void;
    Empty: EmptyEvent,
    pub const empty = Event{ .Empty = {} };
    fn fromSDL(event: c.SDL_Event) Event {
        return switch (event.type) {
            c.SDL_QUIT => Event{ .Quit = {} },
            c.SDL_KEYDOWN => Event{
                .KeyDown = .{
                    .key = Key.fromSDL(event.key.keysym.scancode),
                },
            },
            c.SDL_KEYUP => Event{
                .KeyUp = .{
                    .key = Key.fromSDL(event.key.keysym.scancode),
                },
            },
            c.SDL_MOUSEBUTTONDOWN => Event{
                .MouseDown = .{
                    .pos = .{
                        .x = event.button.x,
                        .y = event.button.y,
                    },
                },
            },
            c.SDL_MOUSEBUTTONUP => Event{
                .MouseUp = .{
                    .pos = .{
                        .x = event.button.x,
                        .y = event.button.y,
                    },
                },
            },
            c.SDL_MOUSEMOTION => Event{
                .MouseMotion = .{
                    .pos = .{
                        .x = event.motion.x,
                        .y = event.motion.y,
                    },
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

pub const Cursor = enum {
    default,
    pointer,
    ibeam,
};

pub const Window = struct {
    // public
    cursor: Cursor,

    sdlWindow: *c.SDL_Window,
    sdlRenderer: *c.SDL_Renderer,
    clippingRectangles: std.ArrayList(Rect),
    previousCursor: Cursor,
    allCursors: AllCursors,
    const AllCursors = help.EnumArray(Cursor, *c.SDL_Cursor);

    pub fn init(alloc: *std.mem.Allocator) !Window {
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

        var clippingRectangles = std.ArrayList(Rect).init(alloc);
        errdefer clippingRectanges.deinit();

        return Window{
            .sdlWindow = window.?,
            .sdlRenderer = renderer.?,
            .clippingRectangles = clippingRectangles,
            .cursor = .default,
            .previousCursor = .ibeam,
            .allCursors = AllCursors.init(.{
                .default = c.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_ARROW).?,
                .pointer = c.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_HAND).?,
                .ibeam = c.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_IBEAM).?,
            }),
        };
    }
    pub fn deinit(window: *Window) void {
        for (window.allCursors.data) |cursor| {
            c.SDL_FreeCursor(cursor);
            // why does this even exsit
        }

        c.SDL_DestroyRenderer(window.sdlRenderer);
        c.SDL_DestroyWindow(window.sdlWindow);
        window.clippingRectangles.deinit();
    }

    /// defer popClipRect
    pub fn pushClipRect(window: *Window, rect: Rect) !void {
        const resRect = if (window.clippingRectangles.items.len >= 1)
            rect.overlap(window.clippingRectangles.items[window.clippingRectangles.items.len - 1])
        else
            rect;

        try window.clippingRectangles.append(resRect);
        errdefer _ = window.clippingRectangles.pop();
        if (c.SDL_RenderSetClipRect(window.sdlRenderer, &resRect.toSDL()) != 0)
            return sdlError();
    }
    pub fn popClipRect(window: *Window) void {
        _ = window.clippingRectangles.pop();

        _ = if (window.clippingRectangles.items.len >= 1)
            c.SDL_RenderSetClipRect(
                window.sdlRenderer,
                &window.clippingRectangles.pop().toSDL(),
            )
        else
            c.SDL_RenderSetClipRect(window.sdlRenderer, null);
    }

    pub fn waitEvent(window: *Window) !Event {
        var event: c.SDL_Event = undefined;
        if (c.SDL_WaitEvent(&event) != 1) return sdlError();
        return Event.fromSDL(event);
    }
    pub fn pollEvent(window: *Window) !Event {
        var event: c.SDL_Event = undefined;
        if (c.SDL_PollEvent(&event) == 0) return Event.empty;
        return Event.fromSDL(event);
    }

    pub fn clear(window: *Window, color: Color) !void {
        if (c.SDL_SetRenderDrawColor(window.sdlRenderer, color.r, color.g, color.b, color.a) != 0) return sdlError();
        if (c.SDL_RenderClear(window.sdlRenderer) < 0) return sdlError();
    }
    pub fn present(window: *Window) void {
        c.SDL_RenderPresent(window.sdlRenderer);
        if (window.cursor != window.previousCursor) {
            window.previousCursor = window.cursor;
            var cursor = window.allCursors.get(window.cursor);
            c.SDL_SetCursor(cursor);
        }
    }
    pub fn getSize(window: *Window) !WindowSize {
        var screenWidth: c_int = undefined;
        var screenHeight: c_int = undefined;
        if (c.SDL_GetRendererOutputSize(window.sdlRenderer, &screenWidth, &screenHeight) < 0) return sdlError();
        return WindowSize{
            .w = @intCast(i64, screenWidth), // should never fail
            .h = @intCast(i64, screenHeight),
        };
    }
};

pub const TextSize = struct {
    w: i64,
    h: i64,
};

pub const Text = struct {
    texture: *c.SDL_Texture,
    size: TextSize,
    pub fn measure(
        font: *const Font,
        text: []const u8,
    ) !TextSize {
        var w: c_int = undefined;
        var h: c_int = undefined;
        if (c.TTF_SizeUTF8(font.sdlFont, text.ptr, &w, &h) < 0) return ttfError();
        return TextSize{ .w = @intCast(i64, w), .h = @intCast(i64, h) };
    }
    pub fn init(
        font: *const Font,
        color: Color,
        text: []const u8, // 0-terminated
        size: ?TextSize,
        window: *const Window,
    ) !Text {
        var surface = c.TTF_RenderUTF8_Blended(
            font.sdlFont,
            text.ptr,
            color.toSDL(),
        );
        if (surface == null) return sdlError();
        defer c.SDL_FreeSurface(surface);
        var texture = c.SDL_CreateTextureFromSurface(
            window.sdlRenderer,
            surface,
        );
        if (texture == null) return sdlError();
        errdefer c.SDL_DestroyTexture(texture);

        return Text{
            .texture = texture.?,
            .size = if (size) |sz| sz else try Text.measure(font, text),
        };
    }
    pub fn deinit(text: *Text) void {
        c.SDL_DestroyTexture(text.texture);
    }
    pub fn render(text: *Text, window: *const Window, pos: Point) !void {
        var rect = c.SDL_Rect{
            .x = @intCast(c_int, pos.x),
            .y = @intCast(c_int, pos.y),
            .w = @intCast(c_int, text.size.w),
            .h = @intCast(c_int, text.size.h),
        };
        if (c.SDL_RenderCopy(
            window.sdlRenderer,
            text.texture,
            null,
            &rect,
        ) < 0) return sdlError();
    }
};

pub const Point = struct {
    x: i64,
    y: i64,
};
pub const Rect = struct {
    x: i64,
    y: i64,
    w: i64,
    h: i64,
    fn toSDL(rect: Rect) c.SDL_Rect {
        return c.SDL_Rect{
            .x = @intCast(c_int, rect.x),
            .y = @intCast(c_int, rect.y),
            .w = @intCast(c_int, rect.w),
            .h = @intCast(c_int, rect.h),
        };
    }
    pub fn containsPoint(rect: Rect, point: Point) bool {
        return point.x >= rect.x and point.x <= rect.x + rect.w and
            point.y >= rect.y and point.y <= rect.y + rect.h;
    }
    pub fn center(rect: Rect) Point {
        return .{
            .x = rect.x + @divFloor(rect.w, 2),
            .y = rect.y + @divFloor(rect.h, 2),
        };
    }
    fn overlap(one: Rect, two: Rect) Rect {
        var fx = if (one.x > two.x) one.x else two.x;
        var fy = if (one.y > two.y) one.y else two.y;
        var onex2 = one.x + one.w;
        var twox2 = two.x + two.w;
        var oney2 = one.y + one.h;
        var twoy2 = two.y + two.h;
        var fx2 = if (onex2 > twox2) twox2 else onex2;
        var fy2 = if (oney2 > twoy2) twoy2 else oney2;
        return .{
            .x = fx,
            .y = fy,
            .w = fx2 - fx,
            .h = fy2 - fy,
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
