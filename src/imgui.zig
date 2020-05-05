const std = @import("std");
const win = @import("./rendering_abstraction.zig");

pub const ImEvent = struct {
    const Internal = struct {
        mouseDown: bool = false,
        click: bool = false,
    };
    internal: Internal = Internal{},
    click: bool = false,
    mouseDown: bool = false,
    mouseUp: bool = false,
    cursor: win.Point = win.Point{ .x = 0, .y = 0 },

    fn apply(imev: *ImEvent, ev: win.Event) void {
        // clear instantanious flags (mouseDown, mouseUp)
        if (imev.internal.mouseDown) {
            imev.internal.mouseDown = false;
        }
        imev.mouseUp = false;

        // apply event
        switch (ev) {
            .MouseMotion => |mmv| {
                imev.cursor = mmv.pos;
            },
            .MouseDown => |clk| {
                imev.internal.mouseDown = true;
                imev.cursor = clk.pos;
                imev.internal.click = true;
            },
            .MouseUp => |clk| {
                imev.mouseUp = true;
                imev.cursor = clk.pos;
                imev.internal.click = false;
            },
            else => {},
        }

        // transfer internal to ev itself
        imev.mouseDown = imev.internal.mouseDown;
        imev.click = imev.internal.click;
    }
    fn takeMouseDown(imev: *ImEvent) void {
        if (!imev.mouseDown) unreachable;
        imev.mouseDown = false;
    }
    fn takeMouseUp(imev: *ImEvent) void {
        if (!imev.mouseUp) unreachable;
        imev.mouseUp = false;
    }
};

pub const Button = struct {
    clickStarted: bool,

    pub fn init() Button {
        return .{ .clickStarted = false };
    }
    pub fn deinit(btn: *Button) void {}

    pub fn render(
        btn: *Button,
        settings: struct {
            text: []const u8,
            font: *win.Font,
            active: bool = false,
        },
        window: *win.Window,
        ev: *ImEvent,
        pos: win.Rect,
    ) !bool {
        try window.pushClipRect(pos);
        defer window.popClipRect();

        var result: bool = false;

        if (ev.mouseDown and win.Rect.containsPoint(pos, ev.cursor)) {
            ev.takeMouseDown();
            btn.clickStarted = true;
        }
        const hover = pos.containsPoint(ev.cursor);
        if (btn.clickStarted and ev.mouseUp) {
            btn.clickStarted = false;
            if (hover) {
                result = true;
            }
        }

        const center = pos.center();

        // render
        {
            try win.renderRect(
                window,
                if (btn.clickStarted or result)
                    if (hover)
                        win.Color.hex(0x70798c)
                    else
                        win.Color.hex(0x565f73)
                else if (hover)
                    if (settings.active)
                        win.Color.hex(0x648c84)
                    else
                        win.Color.hex(0x565f73)
                else if (settings.active)
                    win.Color.hex(0x4d756d)
                else
                    win.Color.hex(0x3f4757),
                pos,
            );

            // in the future, the text and text size could be cached
            // (that would require a deinit method to clear allocated text data)
            var measure = try win.Text.measure(settings.font, settings.text);
            var text = try win.Text.init(
                settings.font,
                win.Color.hex(0xFFFFFF),
                settings.text,
                measure,
                window,
            );
            defer text.deinit();

            try text.render(
                window,
                .{
                    .x = center.x - @divFloor(measure.w, 2),
                    .y = center.y - @divFloor(measure.h, 2),
                },
            );
        }

        return result;
    }
};

pub fn EnumEditor(comptime Enum: type) type {
    const typeInfo = @typeInfo(Enum).Enum;
    const choices = comptime blk: {
        var choices: [][]const u8 = [_]u8{};
        for (typeInfo.fields) |field| {
            choices = choices ++ [_]u8{field.name};
            // would be nice to have a comptime map or something
        }
        break :blk choices;
    };
    return struct {
        buttonData: [choices.len]ToggleButton,
        pub fn render(
            window: *win.Window,
            event: win.Event,
            pos: win.Rect,
            out: *Enum,
        ) !void {
            try window.pushClipRect(pos);
            defer window.popClipRect();
            // draw each button

            const choiceWidth = pos.w / choices.len;
            inline for (choices) |choice, i| {
                const choiceHOffset = choiceWidth * i;
                var btn = &editor.buttonData[i];
                ToggleButton.render(btn.dat, false, choice);
            }
        }
    };
}

// unioneditor is more difficult
// tabs at the top
// needs to keep data for each tab if you switch tabs and switch back

pub fn DataEditor(comptime Data: type) type {
    return switch (@typeInfo(Data)) {
        .Struct => StructEditor(Data),
        .Enum => EnumEditor(Data),
        else => @compileLog("must be struct or enum"),
    };
}

// eg StructEditor(enum {One, Two}) shows a select switch for one or two
