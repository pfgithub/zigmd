const std = @import("std");
const win = @import("./rendering_abstraction.zig");

pub const ImEvent = struct {
    const Internal = struct {
        mouseDown: bool = false,
        click: bool = false,
        rerender: bool = false,
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
        imev.internal.rerender = false;

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
    fn rerender(imev: *ImEvent) void {
        imev.internal.rerender = true;
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
                        win.Color.hex(0x70798c)
                else if (hover and !ev.click)
                    if (settings.active)
                        win.Color.hex(0x385c55)
                    else
                        win.Color.hex(0x565f73)
                else if (settings.active)
                    win.Color.hex(0x2c4a44)
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
    if (typeInfo.fields.len == 0) unreachable;
    return struct {
        const Editor = @This();
        buttonData: [typeInfo.fields.len]Button,
        pub fn init() Editor {
            return .{
                .buttonData = blk: {
                    var res: [typeInfo.fields.len]Button = undefined;
                    inline for (typeInfo.fields) |field, i| {
                        res[i] = Button.init();
                    }
                    break :blk res;
                },
            };
        }
        pub fn deinit(editor: *Editor) void {
            inline for (typeInfo.fields) |field, i| {
                editor.buttonData[i].deinit();
            }
        }
        pub fn render(
            editor: *Editor,
            value: *Enum,
            font: *win.Font,
            window: *win.Window,
            ev: *ImEvent,
            pos: win.Rect,
        ) !void {
            try window.pushClipRect(pos);
            defer window.popClipRect();
            // draw each button

            const lenInt = @intCast(i64, typeInfo.fields.len);
            const choiceWidth = @divFloor(
                (pos.w - 5 * (lenInt - 1)),
                lenInt,
            );
            inline for (typeInfo.fields) |field, i| {
                const choiceHOffset = (choiceWidth + 5) * @intCast(i64, i);
                var btn = &editor.buttonData[i];
                var clicked = try btn.render(
                    .{
                        .text = if (@hasDecl(Enum, "title_" ++ field.name))
                            @field(Enum, "title_" + field.name)
                        else
                            field.name,
                        .active = value.* == @field(Enum, field.name),

                        .font = font,
                    },
                    window,
                    ev,
                    .{
                        .x = choiceHOffset + pos.x,
                        .y = pos.y,
                        .w = choiceWidth,
                        .h = pos.h,
                    },
                );
                if (clicked) {
                    value.* = @field(Enum, field.name);
                    ev.rerender();
                }
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
