const gui = @import("gui.zig");
const win = @import("render.zig");

pub fn Component(comptime Data: type) type {
    return struct {
        const Me = @This();
        pub const Props = Data.Props;

        auto: *Auto,
        data: Data,

        pub fn init(imev: *gui.ImEvent) Me {
            return .{ .auto = Auto.init(imev) };
        }
        pub fn deinit() void {
            me.auto.deinit();
        }
        pub fn render(props: Props, me: *Me) !void {
            try me.data.render(props, imev, layout);
        }
    };
}

const DemoComponent = Component(struct {
    pub const Props = struct {};
    const State = @This();

    enabled: bool = false,

    pub fn init() DemoData {
        return .{};
    }
    pub fn deinit() void {}

    pub fn render(state: *State, props: Props, imev: *gui.ImEvent, layout: *Layout) !void {
        win.renderRect(imev.window, layout.all(), win.Color.hex(0xFFFFFF));
    }
});

// which part first?
// start with style?
// sure

// if ast modifying things existed, something like this could exist:
// pub usingnamespace initDeinit(fn() {
//     var a = alloc.create(thing);
//     errdefer alloc.free(a); // all errdefers are put in the deinit fn automatically
// })

pub fn ClickyButton(imev: *ImEvent, auto: *Auto) void {
    var state = auto.state(bool, false);
    var clicked = auto.render(gui.Button, .{ .text = "click", .active = state.* });
    if (clicked) {
        state.* = !state.*;
    }
    auto.layout.gap();
    auto.render(gui.Label, .{ .text = "test" });
    // align auto manages alignment (eg place left, right, ... and also the button gets to say what size it is instead of you)
    // (unless you want to say)
}

// goals:
// hopefully I want making something with this to be easier than making a sitepage
// (easy:) making something with this should be easier than managing the mess of eg qt/gtk

// some notes:
// accessability is pretty simple
// it's like tab indexing really. components check if they are focused and if so, update the accessability label.
// I don't think sdl lets you do that yet though so

// rtl mode might be difficult. switch all layout directions from left to right? seems like it could have lots
// of issues. idk about rtl mode.
