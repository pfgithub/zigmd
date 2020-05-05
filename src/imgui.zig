const std = @import("std");
const win = @import("./rendering_abstraction.zig");

pub const ImEvent = struct {
    internal: struct {
        mouseDown: bool,
        click: bool,
    },
    click: bool,
    mouseDown: bool,
    mouseUp: bool,
    mousePos: win.Point,

    fn loadEvent(imev: *ImEvent, ev: win.Event) void {
        // clear instantanious flags (mouseDown, mouseUp)
        if (imev.internal.mouseDown) {
            imev.internal.mouseDown = false;
        }
        imev.mouseUp = false;

        // apply event
        switch (ev) {
            .MouseMotion => |mmv| {
                imev.mousePos = mmv.pos;
            },
            .MouseDown => |clk| {
                imev.internal.mouseDown = true;
                imev.mousePos = clk.pos;
                imev.internal.click = true;
            },
            .MouseUp => |clk| {
                imev.mouseUp = true;
                imev.mousePos = clk.pos;
                imev.internal.click = false;
            },
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

pub const ToggleButton = struct {
    clickStarted: bool,

    pub fn render(
        btn: *ToggleButton,
        settings: struct { text: []const u8 },
        window: *win.Window,
        ev: *ImEvent,
        pos: win.Rect,
    ) !void {
        try window.pushClipRect(pos);
        defer window.popClipRect();

        if (ev.mouseDown and win.Rect.pointWithin(pos, ev.cursor)) {
            ev.takeMouseDown();
            btn.clickStarted = true;
        }
        const hover = pos.containsPoint(ev.cursor);
        if (btn.clickStarted and ev.mouseUp) {
            btn.clickStarted = false;
            if (hover) {
                // button clicked!
                std.debug.warn("button clicked\n", .{});
            } else {
                // nvm
                std.debug.warn("button click cancelled\n", .{});
            }
        }

        const center = pos.center();

        // render
        {
            win.renderRect(
                window,
                if (btn.clickStarted)
                    if (hover)
                        win.Color.hex(0x550000)
                    else
                        win.Color.hex(0x555500)
                else if (hover)
                    win.Color.hex(0x000055)
                else
                    win.Color.hex(0x005500),
                pos,
            );

            // in the future, the text and text size could be cached
            var measure = try win.Text.measure(settings.font, settings.text);
            var text = win.Text.init(
                settings.font,
                win.Color.hex(0xFFFFFF),
                settings.text,
                measure,
                window,
            );
            defer text.deinit();

            try text.render(
                window,
                center.x - measure.w / 2,
                center.y - measure.h / 2,
            );
        }

        renderText(settings.text);
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
