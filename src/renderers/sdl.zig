const sdl = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_ttf.h");
    @cInclude("fontconfig/fontconfig.h");
});
const std = @import("std");
const help = @import("../helpers.zig");
pub usingnamespace @import("./common.zig");

const ER = RenderingError;
const ERF = RenderingError || FontLoadError;

test "implements header" {
    comptime {
        @setEvalBranchQuota(10000000);
        const match = @import("../header_match.zig");
        const header = @import("./header.zig");
        match.conformsTo(header, @This());
        // match.is(win, header)?
    }
}

fn sdlError() RenderingError {
    _ = sdl.printf("SDL Method Failed: %s\n", sdl.SDL_GetError());
    return RenderingError.Unrecoverable;
}

fn ttfError() RenderingError {
    _ = sdl.printf("TTF Method Failed: %s\n", sdl.TTF_GetError());
    return RenderingError.Unrecoverable;
}

pub const FontLoader = struct {
    config: *sdl.FcConfig,
    pub fn init() FontLoader {
        return .{
            .config = sdl.FcInitLoadConfigAndFonts().?,
        };
    }
    pub fn deinit(loader: *FontLoader) void {
        sdl.FcConfigDestroy(loader.config);
    }
    pub fn loadFromName(
        loader: *const FontLoader,
        name: []const u8,
        fontSize: u16,
    ) ERF!Font {
        return Font.loadFromName(loader, name, fontSize);
    }
};

pub const Font = struct {
    sdlFont: *sdl.TTF_Font,
    pub fn init(ttfPath: []const u8, size: u16) ER!Font {
        var font = sdl.TTF_OpenFont(ttfPath.ptr, size);
        if (font == null) return ttfError();
        errdefer sdl.TTF_CloseFont(font);

        return Font{
            .sdlFont = font.?,
        };
    }
    pub fn deinit(font: *Font) void {
        sdl.TTF_CloseFont(font.sdlFont);
    }
    pub fn loadFromName(
        loader: *const FontLoader,
        name: []const u8,
        fontSize: u16,
    ) ERF!Font {
        var config = loader.config;
        var pattern = sdl.FcNameParse(name.ptr).?;
        defer sdl.FcPatternDestroy(pattern);

        // font size
        var v: sdl.FcValue = .{
            .type = @intToEnum(sdl.FcType, sdl.FcTypeInteger),
            .u = .{ .i = fontSize },
        };
        if (sdl.FcPatternAdd(pattern, sdl.FC_SIZE, v, sdl.FcTrue) == sdl.FcFalse)
            return ER.Unrecoverable;

        if (sdl.FcConfigSubstitute(
            config,
            pattern,
            @intToEnum(sdl.FcMatchKind, sdl.FcMatchPattern),
        ) == sdl.FcFalse)
            return ER.Unrecoverable;
        sdl.FcDefaultSubstitute(pattern);

        var result: sdl.FcResult = undefined;
        if (sdl.FcFontMatch(config, pattern, &result)) |font| {
            defer sdl.FcPatternDestroy(font);
            var file: [*c]sdl.FcChar8 = null;
            if (sdl.FcPatternGetString(font, sdl.FC_FILE, 0, &file) ==
                @intToEnum(sdl.FcResult, sdl.FcResultMatch))
            {
                var resFont = Font.init(std.mem.span(file), fontSize);
                return resFont;
            }
        }
        return ERF.FontNotFound;
    }
};

fn colorFromSDL(color: sdl.SDL_Color) Color {
    return Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
}
fn colorToSDL(color: Color) sdl.SDL_Color {
    return sdl.SDL_Color{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
}
fn keyFromSDL(sdlKey: var) Key {
    return switch (sdlKey) {
        .SDL_SCANCODE_LEFT => .Left,
        .SDL_SCANCODE_RIGHT => .Right,
        .SDL_SCANCODE_BACKSPACE => .Backspace,
        .SDL_SCANCODE_RETURN => .Return,
        .SDL_SCANCODE_DELETE => .Delete,
        .SDL_SCANCODE_S => .S,
        .SDL_SCANCODE_ESCAPE => .Escape,
        .SDL_SCANCODE_LALT => .Alt,
        .SDL_SCANCODE_RALT => .Alt,
        else => .Unknown,
    };
}

fn eventFromSDL(event: sdl.SDL_Event) Event {
    return switch (event.type) {
        sdl.SDL_QUIT => Event{ .quit = {} },
        sdl.SDL_KEYDOWN => Event{
            .keyDown = .{
                .key = keyFromSDL(event.key.keysym.scancode),
            },
        },
        sdl.SDL_KEYUP => Event{
            .keyUp = .{
                .key = keyFromSDL(event.key.keysym.scancode),
            },
        },
        sdl.SDL_MOUSEBUTTONDOWN => Event{
            .mouseDown = .{
                .pos = .{
                    .x = event.button.x,
                    .y = event.button.y,
                },
            },
        },
        sdl.SDL_MOUSEBUTTONUP => Event{
            .mouseUp = .{
                .pos = .{
                    .x = event.button.x,
                    .y = event.button.y,
                },
            },
        },
        sdl.SDL_MOUSEMOTION => Event{
            .mouseMotion = .{
                .pos = .{
                    .x = event.motion.x,
                    .y = event.motion.y,
                },
            },
        },
        sdl.SDL_TEXTINPUT => blk: {
            var text: [100]u8 = undefined;
            std.mem.copy(u8, &text, &event.text.text);
            break :blk Event{
                .textInput = .{ .text = text, .length = @intCast(u32, sdl.strlen(&event.text.text)) },
            };
        },
        sdl.SDL_MOUSEWHEEL => Event{
            // if these are backwards, try checking event.direction. maybe it will do something.
            .mouseWheel = .{
                // convert random number to number of pixels to scroll
                .x = event.wheel.x * 59,
                .y = event.wheel.y * 50,
            },
        },
        sdl.SDL_WINDOWEVENT => switch (event.window.event) {
            sdl.SDL_WINDOWEVENT_FOCUS_GAINED => Event{ .windowFocus = .{} },
            sdl.SDL_WINDOWEVENT_FOCUS_LOST => Event{ .windowBlur = .{} },
            sdl.SDL_WINDOWEVENT_RESIZED => Event{
                .resize = .{ .w = event.window.data1, .h = event.window.data2 },
            },
            else => Event{ .unknown = .{ .type = event.window.event } },
        },
        else => Event{ .unknown = .{ .type = event.type } },
    };
}

pub const Window = struct {
    // public
    cursor: Cursor,
    debug: struct {
        showClippingRects: bool = false,
    },

    sdlWindow: *sdl.SDL_Window,
    sdlRenderer: *sdl.SDL_Renderer,
    clippingRectangles: std.ArrayList(Rect),
    previousCursor: Cursor,
    allCursors: AllCursors,
    lastFrame: u64,

    destroyTextureList: std.ArrayList(*sdl.SDL_Texture),
    alloc: *std.mem.Allocator,

    const AllCursors = help.EnumArray(Cursor, *sdl.SDL_Cursor);

    pub fn init(alloc: *std.mem.Allocator) ER!Window {
        var window = sdl.SDL_CreateWindow(
            "hello_sdl2",
            sdl.SDL_WINDOWPOS_UNDEFINED,
            sdl.SDL_WINDOWPOS_UNDEFINED,
            640,
            480,
            sdl.SDL_WINDOW_SHOWN | sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_ALLOW_HIGHDPI,
        );
        if (window == null) return sdlError();
        errdefer sdl.SDL_DestroyWindow(window);

        var renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED);
        if (renderer == null) return sdlError();
        errdefer sdl.SDL_DestroyRenderer(renderer);

        // if (sdl.SDL_GL_SetSwapInterval(1) != 0) {
        //     std.debug.warn("VSync Error: {}\n", .{sdlError()});
        // }

        var clippingRectangles = std.ArrayList(Rect).init(alloc);
        errdefer clippingRectanges.deinit();
        var destroyTextureList = std.ArrayList(*sdl.SDL_Texture).init(alloc);
        errdefer destroyTextureList.deinit();

        return Window{
            .sdlWindow = window.?,
            .sdlRenderer = renderer.?,
            .clippingRectangles = clippingRectangles,
            .cursor = .default,
            .debug = .{},
            .previousCursor = .ibeam,
            .allCursors = AllCursors.init(.{
                .default = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_ARROW).?,
                .pointer = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_HAND).?,
                .ibeam = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_IBEAM).?,
                .move = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_SIZEALL).?,
                .resizeNwSe = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_SIZENWSE).?,
                .resizeNeSw = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_SIZENESW).?,
                .resizeNS = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_SIZENS).?,
                .resizeEW = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_SIZEWE).?,
            }),
            .lastFrame = 0,
            .destroyTextureList = destroyTextureList,
            .alloc = alloc,
        };
    }
    pub fn destroyTextures(window: *Window) void {
        for (window.destroyTextureList.items) |destroytex| {
            sdl.SDL_DestroyTexture(destroytex);
        }
        window.destroyTextureList.deinit(); // clears the list
        window.destroyTextureList = std.ArrayList(*sdl.SDL_Texture).init(window.alloc);
    }
    pub fn deinit(window: *Window) void {
        for (window.allCursors.data) |cursor| {
            sdl.SDL_FreeCursor(cursor);
            // why does this even exsit
        }
        window.destroyTextures();
        window.destroyTextureList.deinit();

        sdl.SDL_DestroyRenderer(window.sdlRenderer);
        sdl.SDL_DestroyWindow(window.sdlWindow);
        window.clippingRectangles.deinit();
    }

    // TODO if this returns the previous rect size, there will be
    // no need for an internal arraylist.
    // var popClipRect = pushClipRect();
    // defer popClipRect.pop();
    /// defer popClipRect
    pub fn pushClipRect(window: *Window, rect: Rect) ER!void {
        if (window.debug.showClippingRects) {
            var crcolr = window.clippingRectangles.items.len;
            var crcol = @intCast(u8, std.math.min(crcolr * 8, 255));
            renderRect(
                window,
                Color{ .r = crcol, .g = crcol, .b = crcol, .a = 255 },
                rect,
            ) catch @panic("unhandled");
        }
        const resRect = if (window.clippingRectangles.items.len >= 1)
            rect.overlap(window.clippingRectangles.items[window.clippingRectangles.items.len - 1])
        else
            rect;

        // oom can't be handled very well if the entire rendering library will implode on oom
        window.clippingRectangles.append(resRect) catch return ER.Unrecoverable;
        errdefer _ = window.clippingRectangles.pop();
        if (sdl.SDL_RenderSetClipRect(window.sdlRenderer, &rectToSDL(resRect)) != 0)
            return sdlError();
    }
    pub fn popClipRect(window: *Window) void {
        _ = window.clippingRectangles.pop();

        _ = if (window.clippingRectangles.items.len >= 1)
            sdl.SDL_RenderSetClipRect(
                window.sdlRenderer,
                &rectToSDL(window.clippingRectangles.items[window.clippingRectangles.items.len - 1]),
            )
        else
            sdl.SDL_RenderSetClipRect(window.sdlRenderer, null);
    }

    pub fn clippingRectangle(window: *Window) ?Rect {
        return if (window.clippingRectangles.items.len >= 1)
            window.clippingRectangles.items[window.clippingRectangles.items.len - 1]
            // stdlib really needs a way to get the last item from an arraylist
        else
            null;
    }

    pub fn waitEvent(window: *Window) ER!Event {
        var event: sdl.SDL_Event = undefined;
        if (sdl.SDL_WaitEvent(&event) != 1) return sdlError();
        return eventFromSDL(event);
    }
    pub fn pollEvent(window: *Window) Event {
        var event: sdl.SDL_Event = undefined;
        if (sdl.SDL_PollEvent(&event) == 0) return Event.empty;
        return eventFromSDL(event);
    }

    pub fn clear(window: *Window, color: Color) ER!void {
        if (sdl.SDL_SetRenderDrawColor(window.sdlRenderer, color.r, color.g, color.b, color.a) != 0) return sdlError();
        if (sdl.SDL_RenderClear(window.sdlRenderer) < 0) return sdlError();
    }
    pub fn present(window: *Window) void {
        if (window.cursor != window.previousCursor) {
            window.previousCursor = window.cursor;
            var cursor = window.allCursors.get(window.cursor);
            sdl.SDL_SetCursor(cursor);
        }
        sdl.SDL_RenderPresent(window.sdlRenderer);

        {
            const ctime = time();
            const diff = ctime - window.lastFrame;
            if (diff < 4) {
                sdl.SDL_Delay(@intCast(u32, 4 - diff));
            }
            window.lastFrame = time();
        }

        window.destroyTextures();
    }
    pub fn getSize(window: *Window) ER!WH {
        var screenWidth: c_int = undefined;
        var screenHeight: c_int = undefined;
        if (sdl.SDL_GetRendererOutputSize(window.sdlRenderer, &screenWidth, &screenHeight) < 0) return sdlError();
        return WH{
            .w = @intCast(i64, screenWidth), // should never fail
            .h = @intCast(i64, screenHeight),
        };
    }
};

pub const Text = struct {
    texture: *sdl.SDL_Texture,
    size: TextSize,
    window: *Window,
    pub fn measure(
        font: *const Font,
        text: []const u8,
    ) ER!TextSize {
        const tmpAlloc = std.heap.c_allocator; // eew null termination
        const nullTerminated = std.mem.dupeZ(tmpAlloc, u8, text) catch return error.Unrecoverable;
        defer tmpAlloc.free(nullTerminated); // hot take: null termination < untyped null pointers

        var w: c_int = undefined;
        var h: c_int = undefined;
        if (sdl.TTF_SizeUTF8(font.sdlFont, nullTerminated.ptr, &w, &h) < 0) return ttfError();
        return TextSize{ .w = @intCast(i64, w), .h = @intCast(i64, h) };
    }
    pub fn init(
        font: *const Font,
        color: Color,
        text: []const u8, // 0-terminated
        size: ?TextSize,
        window: *Window,
    ) ER!Text {
        const tmpAlloc = std.heap.c_allocator; // eew null termination
        const nullTerminated = std.mem.dupeZ(tmpAlloc, u8, text) catch return error.Unrecoverable;
        defer tmpAlloc.free(nullTerminated); // hot take: null termination < untyped null pointers

        var surface = sdl.TTF_RenderUTF8_Blended(
            font.sdlFont,
            nullTerminated.ptr,
            colorToSDL(color),
        );
        if (surface == null) return sdlError();
        defer sdl.SDL_FreeSurface(surface);
        var texture = sdl.SDL_CreateTextureFromSurface(
            window.sdlRenderer,
            surface,
        );
        if (texture == null) return sdlError();
        errdefer sdl.SDL_DestroyTexture(texture);

        return Text{
            .texture = texture.?,
            .size = if (size) |sz| sz else try Text.measure(font, text),
            .window = window,
        };
    }
    pub fn deinit(text: *Text) void {
        // must deinit on next frame for mac
        // might be bad for this catch to be here in case eg append ooms and then the texture is destroyed
        // and then it crashes on mac
        text.window.destroyTextureList.append(text.texture) catch sdl.SDL_DestroyTexture(text.texture);
    }
    pub fn render(text: *Text, pos: Point) ER!void {
        var rect = sdl.SDL_Rect{
            .x = @intCast(c_int, pos.x),
            .y = @intCast(c_int, pos.y),
            .w = @intCast(c_int, text.size.w),
            .h = @intCast(c_int, text.size.h),
        };
        if (sdl.SDL_RenderCopy(
            text.window.sdlRenderer,
            text.texture,
            null,
            &rect,
        ) < 0) return sdlError();
    }
};

fn rectToSDL(rect: Rect) sdl.SDL_Rect {
    return sdl.SDL_Rect{
        .x = @intCast(c_int, rect.x),
        .y = @intCast(c_int, rect.y),
        .w = @intCast(c_int, rect.w),
        .h = @intCast(c_int, rect.h),
    };
}
pub fn renderRect(window: *const Window, color: Color, rect: Rect) ER!void {
    if (rect.w == 0 or rect.h == 0) return;
    var sdlRect = rectToSDL(rect);
    if (sdl.SDL_SetRenderDrawColor(window.sdlRenderer, color.r, color.g, color.b, color.a) != 0) return sdlError();
    if (sdl.SDL_RenderFillRect(window.sdlRenderer, &sdlRect) != 0) return sdlError();
}

pub fn init() RenderingError!void {
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_EVENTS) < 0) return sdlError();
    errdefer sdl.SDL_Quit();

    if (sdl.TTF_Init() < 0) return sdlError();
    errdefer sdl.TTF_Quit();

    sdl.SDL_StartTextInput();

    sdl.SDL_EnableScreenSaver(); // allow os to go to screensaver with editor running
    _ = sdl.SDL_EventState(sdl.SDL_DROPFILE, sdl.SDL_ENABLE); // drop file support
    if (@hasDecl(sdl, "SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR")) {
        _ = sdl.SDL_SetHint(sdl.SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0"); // something idk
    }
    if (sdl.SDL_VERSION_ATLEAST(2, 0, 5)) {
        _ = sdl.SDL_SetHint(sdl.SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1"); // when focusing the window with a click, send the click too.
    }
}

pub fn deinit() void {
    sdl.TTF_Quit();
    sdl.SDL_Quit();
}

pub fn time() u64 {
    return sdl.SDL_GetTicks();
}
