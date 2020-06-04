const std = @import("std");

const help = @import("helpers.zig");
const gui = @import("gui.zig");
const win = @import("render.zig");

pub const WindowDemo = AutoTest;

/// now we're just making react but in zig
pub const Auto = struct {
    alloc: *std.mem.Allocator,
    items: ItemsMap,

    const ItemsMap = std.AutoHashMap(u64, struct { value: help.AnyPtr, deinit: DeinitFn });
    const DeinitFn = fn (value: help.AnyPtr) void;

    pub fn init(alloc: *std.mem.Allocator) Auto {
        return .{
            .alloc = alloc,
            .items = ItemsMap.init(alloc),
        };
    }

    pub fn deinit(auto: *Auto) void {
        var it = auto.items.iterator();
        while (it.next()) |next| {
            next.value.deinit(next.value.value);
            // since value is not comptime known, it needs a deinit fn
        }
        auto.items.deinit();
    }

    /// something must be a unique type every time otherwise the wrong id will be made!
    /// don't use this in a loop (todo support loops)
    pub fn new(auto: *Auto, initmethod: var, args: var) *@typeInfo(@TypeOf(initmethod)).Fn.return_type.? {
        const Type = @typeInfo(@TypeOf(initmethod)).Fn.return_type.?;
        const uniqueID = help.AnyPtr.typeID(struct {});
        if (auto.items.getValue(uniqueID)) |v| return v.value.readAs(Type);
        const allocated = auto.alloc.create(Type) catch @panic("oom not handled");
        const deinitfn: DeinitFn = struct {
            fn f(value: help.AnyPtr) void {
                value.readAs(Type).deinit();
            }
        }.f;
        allocated.* = @call(.{}, initmethod, args);
        if (auto.items.put(
            uniqueID,
            .{ .deinit = deinitfn, .value = help.AnyPtr.fromPtr(allocated) },
        ) catch @panic("oom not handled")) |_| @panic("duplicate insert (never)");
        return allocated;
    }

    // pub fn memo() yeah this is just react
};

pub const Component = struct {
    body: *WindowBody,
    fn render(
        self: *Component,
        imev: *gui.ImEvent,
        style: gui.Style,
        pos: win.Rect,
        alloc: *std.mem.Allocator,
    ) void {
        self.body.render(self.body, imev, style, pos, alloc);
    }
    fn deinit(self: *Component) void {
        self.body.deinit(self.body);
    }
};

pub const WindowBody = struct {
    render: fn (self: *WindowBody, imev: *gui.ImEvent, style: gui.Style, pos: win.Rect, alloc: *std.mem.Allocator) void,
    deinit: fn (self: *WindowBody) void,
    pub fn from(comptime Type: type, comptime fieldName: []const u8) WindowBody {
        const Fns = struct {
            fn render(
                ptr: *WindowBody,
                imev: *gui.ImEvent,
                style: gui.Style,
                pos: win.Rect,
                alloc: *std.mem.Allocator,
            ) void {
                return Type.render(@fieldParentPtr(Type, fieldName, ptr), imev, style, pos, alloc);
            }
            fn deinit(
                ptr: *WindowBody,
            ) void {
                return Type.deinit(@fieldParentPtr(Type, fieldName, ptr));
            }
        };
        return .{
            .render = Fns.render,
            .deinit = Fns.deinit,
        };
    }
};

pub const WindowTest = struct {
    windowBody: WindowBody,

    id: u64,
    auto: Auto,

    pub fn init(
        imev: *gui.ImEvent,
        alloc: *std.mem.Allocator,
    ) WindowTest {
        return .{
            .windowBody = WindowBody.from(WindowTest, "windowBody"),
            .id = imev.newID(),
            .auto = Auto.init(alloc),
        };
    }

    pub fn deinit(body: *WindowTest) void {
        body.auto.deinit();
    }

    pub fn render(
        body: *WindowTest,
        imev: *gui.ImEvent,
        style: gui.Style,
        pos: win.Rect,
        alloc: *std.mem.Allocator,
    ) void {
        const clicked = body.auto.new(
            gui.Button.init,
            .{imev},
        ).render(
            .{ .text = "Test", .font = style.fonts.standard, .active = false, .style = style },
            imev,
            pos.position(.{ .w = 100, .h = 25 }, .hcenter, .vcenter),
        ) catch @panic("not handled");
        if (clicked.click) {
            std.debug.warn("demo {}\n", .{body.id});
        }
    }
};

/// the intent of this is to be a window manager thing
/// eventually I want to be able to have one of those window
/// things where everything is a tab and you can put them anywhere
/// but floating works for now (and is really good as a test of
/// overlapping windows)
pub const AutoTest = struct {
    id: u64,
    auto: Auto, // each auto call can make its own unique id
    // it would probably be possible to make some kind of comptime
    // auto that stores things without heap allocation
    // not doing that yet.

    windows: std.ArrayList(Window),

    const Window = struct {
        auto: Auto,
        title: []const u8,
        body: Component,
        relativePos: win.Rect,
        dragging: bool = false,
    };

    pub fn init(
        imev: *gui.ImEvent,
        alloc: *std.mem.Allocator,
    ) AutoTest {
        return .{
            .id = imev.newID(),
            .auto = Auto.init(alloc),

            .windows = std.ArrayList(Window).init(alloc),
        };
    }
    pub fn deinit(view: *AutoTest) void {
        for (view.windows) |*w| {
            w.auto.deinit();
            w.body.deinit();
        }
        view.windows.deinit();
        view.auto.deinit();
        view.* = undefined; // is this a thing that can be done?
    }

    pub fn render(
        view: *AutoTest,
        imev: *gui.ImEvent,
        style: gui.Style,
        pos: win.Rect,
        alloc: *std.mem.Allocator,
    ) !void {
        // could have discarding options
        const clicked = try view.auto.new(
            gui.Button.init,
            .{imev},
        ).render(
            .{ .text = "+ Window", .font = style.fonts.standard, .active = false, .style = style },
            imev,
            pos.position(.{ .w = 100, .h = 25 }, .left, .top).down(50).right(50),
        );
        if (clicked.click) {
            var windowTest = alloc.create(WindowTest) catch @panic("oom not handled");
            windowTest.* = WindowTest.init(imev, alloc);
            view.windows.append(.{
                .auto = Auto.init(alloc),
                .title = "Title",
                .body = .{ .body = &windowTest.windowBody },
                .relativePos = .{ .x = 100, .y = 100, .w = 500, .h = 500 },
            }) catch @panic("oom not handled");
        }
        for (view.windows.items) |*w| {
            const windowRect = w.relativePos.down(pos.x).right(pos.y);

            try win.renderRect(imev.window, style.colors.background, windowRect);

            // if(imev.mouseDown and windowRect.containsPoint(imev.cursor)) {
            //     // bring to front
            //     // can't do this until focus is implemented
            // }

            const titlebarRect = windowRect.height(25);
            if (imev.mouseDown and titlebarRect.containsPoint(imev.cursor)) {
                imev.takeMouseDown(); // temporary until real id-based focus
                w.dragging = true;
            }
            if (w.dragging and imev.mouseUp) {
                w.dragging = false;
            }
            if (w.dragging) {
                w.relativePos.x += imev.mouseDelta.x;
                w.relativePos.y += imev.mouseDelta.y;
            }

            const bodyRect = windowRect.inset(25, 1, 1, 1);

            try win.renderRect(imev.window, style.colors.window, bodyRect);

            w.body.render(imev, style, bodyRect.inset(4, 4, 4, 4), alloc);
            // handle mod+drag after ("capturing")
            // before = bubbling, after = capturing
        }
    }
};

pub const Minesweeper = struct {
    id: u64,

    gameState: GameState,

    const GameState = union(enum) {
        setup: struct {
            const BoardSize = enum { @"5" = 5, @"6" = 6, @"7" = 7, @"8" = 8, @"9" = 9 }; // good place for a textarea + dropdown combo or a slider or something"
            boardSizeX: BoardSize,
            boardSizeY: BoardSize,

            initButton: gui.Button,
            // this shouldn't have to be here
            // this is one of the things imgui tries to solve
            // at least it isn't full oop gui but this shouldn't be here
        }
    };

    const BoardItem = struct {
        view: enum { hidden, flagged, shown },
        number: u64,
    };

    pub fn init(imev: *gui.ImEvent, style: *gui.Style) Minesweeper {
        return .{
            .id = imev.newID(),
        };
    }
};
