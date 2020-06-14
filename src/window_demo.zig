const std = @import("std");

const main = @import("main.zig");
const help = @import("helpers.zig");
const gui = @import("gui.zig");
const win = @import("render.zig");
const Auto = gui.Auto;

pub const WindowDemo = AutoTest;

pub const Component = struct {
    body: *WindowBody,
    pub fn render(
        self: *Component,
        imev: *gui.ImEvent,
        style: gui.Style,
        pos: win.Rect,
        alloc: *std.mem.Allocator,
    ) void {
        self.body.render(self.body, imev, style, pos, alloc);
    }
    pub fn deinit(self: *Component) void {
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
    auto: Auto,

    pub fn init(
        imev: *gui.ImEvent,
        alloc: *std.mem.Allocator,
    ) WindowTest {
        return Auto.create(WindowTest, imev, alloc, .{
            .windowBody = WindowBody.from(WindowTest, "windowBody"),
        });
    }

    pub fn deinit(body: *WindowTest) void {
        Auto.destroy(body, .{.auto});
    }

    pub fn render(
        body: *WindowTest,
        imev: *gui.ImEvent,
        style: gui.Style,
        pos: win.Rect,
        alloc: *std.mem.Allocator,
    ) void {
        body.auto.new(main.MainPage.init, .{ alloc, imev }).render(imev, style, pos, alloc) catch @panic("error not handled");
    }
};

/// the intent of this is to be a window manager thing
/// eventually I want to be able to have one of those window
/// things where everything is a tab and you can put them anywhere
/// but floating works for now (and is really good as a test of
/// overlapping windows)
pub const AutoTest = struct {
    auto: Auto,
    windows: std.ArrayList(Window),

    const Window = struct {
        auto: Auto,
        title: []const u8,
        body: Component,
        relativePos: win.Rect,
        pub fn deinit(window: *Window) void {
            Auto.destroy(window, .{ .auto, .body });
        }
    };

    pub fn init(
        imev: *gui.ImEvent,
        alloc: *std.mem.Allocator,
    ) AutoTest {
        return Auto.create(AutoTest, imev, alloc, .{
            .windows = std.ArrayList(Window).init(alloc),
        });
    }
    pub fn deinit(view: *AutoTest) void {
        for (view.windows.items) |*w| {
            Auto.destroy(w, .{ .auto, .body });
        }
        view.windows.deinit();
        Auto.destroy(view, .{.auto});
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
            var windowBody = &windowTest.windowBody;
            var component: Component = .{ .body = windowBody };
            view.windows.append(Auto.create(Window, imev, alloc, .{
                .title = "Title",
                .body = component,
                .relativePos = .{ .x = 100, .y = 100, .w = 500, .h = 500 },
            })) catch @panic("oom not handled");
        }
        const msclick = try view.auto.new(
            gui.Button.init,
            .{imev},
        ).render(
            .{ .text = "+ Minesweeper", .font = style.fonts.standard, .active = false, .style = style },
            imev,
            pos.position(.{ .w = 100, .h = 25 }, .left, .top).down(100).right(50),
        );
        if (msclick.click) {
            var windowTest = alloc.create(Minesweeper) catch @panic("oom not handled");
            windowTest.* = Minesweeper.init(imev, alloc);
            var windowBody = &windowTest.windowBody;
            var component: Component = .{ .body = windowBody };
            view.windows.append(Auto.create(Window, imev, alloc, .{
                .title = "Title",
                .body = component,
                .relativePos = .{ .x = 100, .y = 100, .w = 500, .h = 500 },
            })) catch @panic("oom not handled");
        }

        var removeIndex: ?usize = null;
        var bringToFrontIndex: ?usize = null;
        for (view.windows.items) |*w, i| {
            const windowRect = w.relativePos.down(pos.y).right(pos.x);

            try win.renderRect(imev.window, style.colors.background, windowRect);

            // if(imev.tabindex(w.id))
            // that would be interesting
            // tabindex can be based on ordering
            // if tab is pressed on a tabindex call with the current id, increment the tab
            // what do you do if the thing tabbed is closed? where does the tabindex go?

            // if(imev.mouseDown and windowRect.containsPoint(imev.cursor)) {
            //     // bring to front
            //     // can't do this until focus is implemented
            // }

            const titlebarRect = windowRect.height(25);
            const resizeRect = windowRect.position(.{ .w = 25, .h = 25 }, .right, .bottom);
            // obviously I want resize to be a few pixels off the edges eventually
            // 10 px seems to work pretty well for windowsystem.pfg.pw
            // also I want an alt+rmb drag or something
            const resizehc = imev.hover(w.auto.id.next(3), windowRect.inset(-10, -10, -10, -10));
            if (resizehc.hover) {
                imev.window.cursor = .resizeNwSe;
            }
            if (resizehc.click) {
                imev.window.cursor = .resizeNwSe;
                w.relativePos.w += imev.mouseDelta.x;
                w.relativePos.h += imev.mouseDelta.y;
            }
            const hc = imev.hover(w.auto.id, windowRect);
            const scrl = imev.scroll(w.auto.id, windowRect);
            const tbhc = imev.hover(w.auto.id.next(1), titlebarRect);
            if (tbhc.click) {
                w.relativePos.x += imev.mouseDelta.x;
                w.relativePos.y += imev.mouseDelta.y;
                imev.window.cursor = .move;
            }

            const closeBtn = try w.auto.new(gui.Button.init, .{imev}).render(
                .{ .text = "x", .font = style.fonts.standard, .active = false, .style = style },
                imev,
                windowRect.position(.{ .w = 25, .h = 25 }, .right, .top),
            );
            if (closeBtn.click) removeIndex = i;

            const bodyRect = windowRect.inset(25, 1, 1, 1);
            try win.renderRect(imev.window, style.colors.window, bodyRect);

            {
                try imev.window.pushClipRect(bodyRect);
                defer imev.window.popClipRect();
                w.body.render(imev, style, bodyRect, alloc);
            }

            if (imev.key.get(.Alt)) {
                const clickHover = imev.hover(w.auto.id.next(5), windowRect);

                //    if(hover.lmb)
                //        move window
                //    if(hover.rmb)
                //        resize window (auto direction, same that should be used for border drag)
                // todo lmb/rmb distinction in imev
                if (clickHover.click) {
                    // move into fn, this is done too often
                    w.relativePos.x += imev.mouseDelta.x;
                    w.relativePos.y += imev.mouseDelta.y;
                    imev.window.cursor = .move;
                }
            }

            if (i != view.windows.items.len - 1) {
                const finalHC = imev.hoverMode(w.auto.id.next(4), windowRect, .passthrough);
                // passthrough should add an id to a list of ids that will pass unless it is changed.
                // eg if another thing does hover no passthrough, it will win. if it does hover passthrough, it will not.
                if (finalHC.click) {
                    bringToFrontIndex = i;
                }
            }
        }
        if (removeIndex) |ri| {
            view.windows.orderedRemove(ri).deinit();
        }
        if (bringToFrontIndex) |btfi| {
            view.windows.appendAssumeCapacity(view.windows.orderedRemove(btfi));
        }
    }
};

pub const Minesweeper = struct {
    windowBody: WindowBody,
    auto: Auto,

    gameState: GameState,

    const GameState = union(enum) {
        setup: Setup,
        play: Play,
        const Setup = struct {
            boardSizeX: u16,
            boardSizeY: u16,

            auto: Auto,
            const This = @This();
            pub fn init(imev: *gui.ImEvent, alloc: *std.mem.Allocator) This {
                return Auto.create(This, imev, alloc, .{
                    .boardSizeX = 10,
                    .boardSizeY = 10,
                });
            }
        };
        const Play = struct {
            board: []MinesweeperTile,
            width: usize,

            auto: Auto,
            const This = @This();
            // pub const init = Auto.createInitFn(@This())
            // that doesn't allow for anthing custom
            pub fn init(imev: *gui.ImEvent, alloc: *std.mem.Allocator) This {
                return Auto.create(This, imev, alloc, .{
                    .board = alloc.alloc(MinesweeperTile, 10 * 10) catch @panic("oom not handled"),
                    .width = 10,
                });
            }
        };
        fn deinit(gs: *GameState) void {
            switch (gs.*) {
                .setup => |setup| {
                    Auto.destroy(&gs.setup, .{.auto});
                },
                .play => |play| {
                    for (gs.play.board) |*tile| {
                        Auto.destroy(tile, .{.auto});
                    }
                    play.auto.alloc.free(gs.play.board);
                    Auto.destroy(&gs.play, .{.auto});
                },
            }
        }
    };

    const MinesweeperTile = struct {
        view: enum { hidden, flagged, shown },
        number: u64,
        auto: Auto,
    };

    pub fn init(
        imev: *gui.ImEvent,
        alloc: *std.mem.Allocator,
    ) Minesweeper {
        const gameState = GameState{ .setup = GameState.Setup.init(imev, alloc) };
        return Auto.create(Minesweeper, imev, alloc, .{
            .windowBody = WindowBody.from(Minesweeper, "windowBody"),
            .gameState = gameState,
        });
    }

    pub fn deinit(body: *Minesweeper) void {
        body.gameState.deinit();
        Auto.destroy(body, .{.auto});
    }

    pub fn render(
        body: *Minesweeper,
        imev: *gui.ImEvent,
        style: gui.Style,
        pos: win.Rect,
        alloc: *std.mem.Allocator,
    ) void {
        switch (body.gameState) {
            .setup => |setup| {
                // using a frame delay, it might be possible to center eg things with unknown height
                const startBtn = body.auto.new(gui.Button.init, .{imev}).render(
                    .{ .text = "Start", .font = style.fonts.standard, .active = false, .style = style },
                    imev,
                    pos.position(.{ .w = 100, .h = 25 }, .hcenter, .vcenter),
                ) catch @panic("error not handled");
                if (startBtn.click) {
                    body.gameState.deinit();
                    body.gameState = .{ .play = GameState.Play.init(imev, alloc) };
                    // what does this do to setup if it's a *const ptr? seems like an issue
                }
            },
            .play => |play| {
                // todo
                // const startBtn = body.auto.new(gui.Button.init, .{imev}).render(
                //     .{ .text = "Todo", .font = style.fonts.standard, .active = false, .style = style },
                //     imev,
                //     pos.position(.{ .w = 100, .h = 25 }, .hcenter, .vcenter),
                // ) catch @panic("error not handled");
                // if (startBtn.click) {
                //     body.gameState.deinit();
                //     body.gameState = .{ .play = GameState.Play.init(imev, alloc) };
                //     // what does this do to setup if it's a *const ptr? seems like an issue
                // }
            },
        }
    }
};
