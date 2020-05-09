const std = @import("std");
const win = @import("./render.zig");
const help = @import("./helpers.zig");

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
    keyDown: ?win.Key = null,
    key: KeyArr = KeyArr.initDefault(false),
    keyUp: ?win.Key = null,
    textInput: ?*const win.Event.TextInputEvent = null,
    const KeyArr = help.EnumArray(win.Key, bool);

    fn apply(imev: *ImEvent, ev: win.Event) void {
        // clear instantanious flags (mouseDown, mouseUp)
        if (imev.internal.mouseDown) {
            imev.internal.mouseDown = false;
        }
        imev.mouseUp = false;
        imev.internal.rerender = false;
        imev.keyDown = null;
        imev.keyUp = null;
        imev.textInput = null;

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
            .KeyDown => |keyev| {
                imev.keyDown = keyev.key;
                _ = imev.key.set(keyev.key, true);
            },
            .KeyUp => |keyev| {
                _ = imev.key.set(keyev.key, false);
                imev.keyUp = keyev.key;
            },
            .TextInput => |*textin| {
                imev.textInput = textin;
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

// caching text
pub const Text = struct {
    text: ?struct {
        hash: u32, // std.hash.autoHash("text")
        text: win.Text,
        color: win.Color,
        font: *win.Font,
    } = null,
    pub fn init() Text {
        return .{};
    }
    pub fn deinit(txt: *Text) void {
        if (txt.text) |*text| text.text.deinit();
    }
    // todo pub fn measure (text: []const u8, font: *win.Font)
    // updates the internal text data if needed and returns the measure
    pub fn render(
        txt: *Text,
        settings: struct {
            text: []const u8,
            font: *win.Font,
            color: win.Color,
            halign: enum { left, center, right } = .center,
            valign: enum { top, center, bottom } = .center,
        },
        window: *win.Window,
        ev: *ImEvent,
        pos: win.Rect,
    ) !win.Rect {
        try window.pushClipRect(pos);
        defer window.popClipRect();

        var set = false;
        if (txt.text != null and
            std.meta.eql(txt.text.?.color, settings.color) and
            txt.text.?.font == settings.font)
        {
            var text = &txt.text.?;
            var hashed = std.hash_map.hashString(settings.text);
            if (text.hash != hashed) {
                text.text.deinit();
                txt.text = .{
                    .hash = hashed,
                    .color = settings.color,
                    .font = settings.font,
                    .text = undefined,
                };
                set = true;
            }
        } else {
            txt.text = .{
                .hash = std.hash_map.hashString(settings.text),
                .color = settings.color,
                .font = settings.font,
                .text = undefined,
            };
            set = true;
        }
        var text = &txt.text.?;
        if (set) {
            text.text = try win.Text.init(
                settings.font,
                settings.color,
                settings.text,
                null,
                window,
            );
        }
        const center = pos.center();
        const textSizeRect = (win.Rect{
            .x = switch (settings.halign) {
                .left => pos.x,
                .center => center.x - @divFloor(text.text.size.w, 2),
                .right => pos.x + pos.w - text.text.size.w,
            },
            .y = switch (settings.valign) {
                .top => pos.y,
                .center => center.y - @divFloor(text.text.size.h, 2),
                .bottom => pos.y + pos.h - text.text.size.h,
            },
            .w = text.text.size.w,
            .h = text.text.size.h,
        }).overlap(pos);
        try text.text.render(window, .{
            .x = textSizeRect.x,
            .y = textSizeRect.y,
        });
        return textSizeRect;
    }
};

pub const Button = struct {
    clickStarted: bool = false,
    text: Text,

    pub fn init() Button {
        return .{ .text = Text.init() };
    }
    pub fn deinit(btn: *Button) void {
        btn.text.deinit();
    }

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
        const hoveringAny = hover and (btn.clickStarted or result or !ev.click);
        if (hoveringAny) window.cursor = .pointer;
        const bumpy = !btn.clickStarted;

        const bumpHeight = 4;
        const bumpOffset: i64 = if (bumpy) if (settings.active) @as(i64, 2) else @as(i64, 4) else 0;

        const buttonPos: win.Rect = .{
            .x = pos.x,
            .y = pos.y + (bumpHeight - bumpOffset),
            .w = pos.w,
            .h = pos.h - bumpHeight,
        };
        const bumpPos: win.Rect = .{
            .x = buttonPos.x,
            .y = buttonPos.y + buttonPos.h,
            .w = buttonPos.w,
            .h = (pos.y + pos.h) - (buttonPos.y + buttonPos.h),
        };

        // render
        {
            if (bumpy)
                try win.renderRect(
                    window,
                    if (settings.active)
                        win.Color.hex(0x142927)
                    else
                        win.Color.hex(0x1c2029),
                    bumpPos,
                );
            try win.renderRect(
                window,
                if (hoveringAny)
                    if (settings.active)
                        win.Color.hex(0x385c55)
                    else
                        win.Color.hex(0x565f73)
                else if (settings.active)
                    win.Color.hex(0x2c4a44)
                else
                    win.Color.hex(0x3f4757),
                buttonPos,
            );

            _ = try btn.text.render(
                .{
                    .text = settings.text,
                    .font = settings.font,
                    .color = win.Color.hex(0xFFFFFF),
                },
                window,
                ev,
                buttonPos,
            );
        }

        return result;
    }
};

pub const Height = struct {
    h: i64
};

pub const lineHeight = 25;
pub const seperatorGap = 10;
pub const connectedGap = 1;
pub const indentWidth = 20;
pub const textGap = 5;
pub const textWidth = 100;

pub fn Part(comptime Type: type) type {
    return struct {
        pub const EditorType = DataEditor(Type);
        editor: EditorType,
        visible: bool,
        toggleButton: Button,
        label: Text,
    };
}

fn getName(comptime Container: type, comptime field: []const u8) []const u8 {
    const titled = "title_" ++ field;
    return if (@hasDecl(Container, titled))
        @field(Container, titled)
    else
        field;
}

fn StructEditor(comptime Struct: type) type {
    const typeInfo = @typeInfo(Struct).Struct;
    const DataStruct = Struct.ModeData;

    return struct {
        const Editor = @This();
        data: DataStruct,
        pub const isInline = true;
        pub fn init() Editor {
            var data: DataStruct = undefined;
            inline for (@typeInfo(DataStruct).Struct.fields) |field| {
                @field(data, field.name) = .{
                    .editor = field.field_type.EditorType.init(),
                    .visible = true,
                    .toggleButton = Button.init(),
                    .label = Text.init(),
                };
            }
            return .{
                .data = data,
            };
        }
        pub fn deinit(editor: *Editor) void {
            inline for (@typeInfo(DataStruct).Struct.fields) |*field| {
                var dat = &@field(editor.data, field.name);
                dat.editor.deinit();
                dat.label.deinit();
            }
        }
        pub fn render(
            editor: *Editor,
            value: *Struct,
            font: *win.Font,
            window: *win.Window,
            ev: *ImEvent,
            pos: win.TopRect,
        ) !Height {
            const gap = seperatorGap;

            const lenInt = @intCast(i64, typeInfo.fields.len);
            var currentHeight: i64 = 0;

            inline for (typeInfo.fields) |field, i| {
                const ItemType = @TypeOf(@field(editor.data, field.name).editor);
                var iteminfo = &@field(editor.data, field.name);
                var item = &iteminfo.editor;
                var fieldv = &@field(value, field.name);
                const labelText = getName(Struct, field.name);
                const linePos: win.TopRect = pos.down(currentHeight);

                if (ItemType.isInline) {
                    const area: win.Rect = linePos.height(lineHeight);

                    const textSizeRect = try iteminfo.label.render(
                        .{
                            .text = labelText,
                            .font = font,
                            .color = win.Color.hex(0xFFFFFF),
                            .halign = .left,
                        },
                        window,
                        ev,
                        area,
                    );

                    if (try iteminfo.toggleButton.render(
                        .{
                            .text = if (iteminfo.visible) "v" else ">",
                            .font = font,
                            .active = iteminfo.visible,
                        },
                        window,
                        ev,
                        .{
                            .x = textSizeRect.x + textSizeRect.w + textGap,
                            .y = currentHeight + pos.y + @divFloor(lineHeight, 2) - @divFloor(20, 2),
                            .w = 20,
                            .h = 20,
                        },
                    )) {
                        iteminfo.visible = !iteminfo.visible;
                        ev.rerender();
                    }
                    currentHeight += area.h + gap;
                    if (iteminfo.visible) {
                        const rh = try item.render(fieldv, font, window, ev, .{
                            .x = pos.x + indentWidth,
                            .y = currentHeight + pos.y,
                            .w = pos.w - indentWidth,
                        });
                        currentHeight += rh.h + gap;
                    }
                } else {
                    const rh = try item.render(
                        fieldv,
                        font,
                        window,
                        ev,
                        linePos.rightCut(textWidth + textGap),
                    );

                    _ = try iteminfo.label.render(
                        .{
                            .text = labelText,
                            .font = font,
                            .color = win.Color.hex(0xFFFFFF),
                            .halign = .left,
                        },
                        window,
                        ev,
                        linePos.width(textWidth).height(rh.h),
                    );

                    currentHeight += rh.h + gap;
                }
            }

            return Height{ .h = currentHeight - gap };
        }
    };
}

fn EnumEditor(comptime Enum: type) type {
    const typeInfo = @typeInfo(Enum).Enum;
    if (typeInfo.fields.len == 0) unreachable;
    return struct {
        const Editor = @This();
        buttonData: [typeInfo.fields.len]Button,
        pub const isInline = false;
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
            pos: win.TopRect,
        ) !Height {
            const gap = connectedGap;
            const height = lineHeight;

            const lenInt = @intCast(i64, typeInfo.fields.len);
            const choiceWidth = @divFloor(
                (pos.w - gap * (lenInt - 1)),
                lenInt,
            );
            inline for (typeInfo.fields) |field, i| {
                const choiceHOffset = (choiceWidth + gap) * @intCast(i64, i);
                var btn = &editor.buttonData[i];
                var clicked = try btn.render(
                    .{
                        .text = if (@hasDecl(Enum, "title_" ++ field.name))
                            @field(Enum, "title_" ++ field.name)
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
                        .h = height,
                    },
                );
                if (clicked) {
                    value.* = @field(Enum, field.name);
                    ev.rerender();
                }
            }

            return Height{ .h = height };
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
