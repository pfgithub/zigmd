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
    const DeinitFn = *const fn (value: help.AnyPtr) void;

    pub fn init(alloc: *std.mem.Allocator) Auto {
        return .{
            .alloc = alloc,
            .items = ItemsMap.init(alloc),
        };
    }

    pub fn deinit(auto: *Auto) void {
        var it = auto.items.iterator();
        while (it.next()) |next| {
            next.value.deinit();
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
        const deinitfn: DeinitFn = &struct {
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

pub const AutoTest = struct {
    id: u64,
    auto: Auto, // each auto call can make its own unique id
    // it would probably be possible to make some kind of comptime
    // auto that stores things without heap allocation
    // not doing that yet.

    active: bool = false,

    pub fn init(
        imev: *gui.ImEvent,
        alloc: *std.mem.Allocator,
    ) AutoTest {
        return .{
            .id = imev.newID(),
            .auto = Auto.init(alloc),
        };
    }
    pub fn deinit(view: *AutoTest) void {
        view.auto.deinit();
    }

    pub fn render(
        view: *AutoTest,
        imev: *gui.ImEvent,
        style: gui.Style,
        pos: win.Rect,
    ) !void {
        // could have discarding options
        const clicked = try view.auto.new(
            gui.Button.init,
            .{imev},
        ).render(
            .{ .text = "a", .font = style.fonts.standard, .active = view.active, .style = style },
            imev,
            pos.position(.{ .w = 20, .h = 20 }, .hcenter, .vcenter),
        );
        if (clicked.click) {
            view.active = !view.active;
            imev.rerender();
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
