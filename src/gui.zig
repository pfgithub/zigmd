const std = @import("std");
const win = @import("./render.zig");
const help = @import("./helpers.zig");

pub const Style = struct {
    colors: struct {
        // syntax highlighting
        text: win.Color,
        control: win.Color,
        special: win.Color,
        errorc: win.Color,
        inlineCode: win.Color,

        // backgrounds
        background: win.Color,
        window: win.Color,
        codeBackground: win.Color,
        linebg: win.Color,

        // special
        cursor: win.Color,
    },
    gui: struct {
        text: win.Color,
        button: struct {
            pub const Active = struct {
                inactive: win.Color,
                active: win.Color,
            };
            base: Active,
            hover: Active,
            shadow: Active,
        },
    },
    fonts: struct {
        standard: *win.Font,
        bold: *win.Font,
        italic: *win.Font,
        bolditalic: *win.Font,
        heading: *win.Font,
        monospace: *win.Font,
    },
};

pub const ImEvent = struct {
    const Internal = struct {
        mouseDown: bool = false,
        click: bool = false,
        rerender: bool = undefined,
    };
    internal: Internal = Internal{},
    click: bool = false,
    mouseDown: bool = false,
    mouseUp: bool = undefined,
    cursor: win.Point = win.Point{ .x = 0, .y = 0 },
    keyDown: ?win.Key = undefined,
    key: KeyArr = KeyArr.initDefault(false),
    keyUp: ?win.Key = undefined,
    textInput: ?*const win.Event.TextInputEvent = undefined,
    time: u64 = undefined,
    animationEnabled: bool = false,
    window: *win.Window = undefined,
    const KeyArr = help.EnumArray(win.Key, bool);

    pub fn apply(imev: *ImEvent, ev: win.Event, window: *win.Window) void {
        // clear instantanious flags (mouseDown, mouseUp)
        if (imev.internal.mouseDown) {
            imev.internal.mouseDown = false;
        }
        imev.mouseUp = false;
        imev.internal.rerender = false;
        imev.keyDown = null;
        imev.keyUp = null;
        imev.textInput = null;
        imev.time = win.time();
        imev.window = window;

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
    pub fn rerender(imev: *ImEvent) void {
        imev.internal.rerender = true;
    }
    pub fn takeMouseDown(imev: *ImEvent) void {
        if (!imev.mouseDown) unreachable;
        imev.mouseDown = false;
    }
    pub fn takeMouseUp(imev: *ImEvent) void {
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
            halign: win.HAlign = .hcenter,
            valign: win.VAlign = .vcenter,
        },
        ev: *ImEvent,
        pos: win.Rect,
    ) !win.Rect {
        const window = ev.window;

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
        const textSizeRect = pos.position(.{
            .w = text.text.size.w,
            .h = text.text.size.h,
        }, settings.halign, settings.valign).overlap(pos);
        try text.text.render(window, .{
            .x = textSizeRect.x,
            .y = textSizeRect.y,
        });
        return textSizeRect;
    }
};

const TimingFunction = fn (f64) f64;

pub const timing = struct {
    pub const Linear: TimingFunction = _Linear;
    fn _Linear(time: f64) f64 {
        return time;
    }
    pub const EaseIn: TimingFunction = _EaseIn;
    pub fn _EaseIn(t: f64) f64 {
        return t * t * t;
    }
    pub const EaseInOut: TimingFunction = _EaseInOut;
    pub fn _EaseInOut(t: f64) f64 {
        return if (t < 0.5) 4 * t * t * t else (t - 1) * (2 * t - 2) * (2 * t - 2) + 1;
    }
};
/// forward/reverse: Apply the easing function in this direction (eg forward easeIn = reverse easeOut)
/// positive/negative: Apply the easing function forward when the object is moving in this direction. eg if the object is moving in the positive direction, forward easeIn, else reverse easeIn.
pub const EaseMode = enum { forward, reverse, positive, negative };
pub fn Interpolation(comptime Kind: type) type {
    const isInt = @typeInfo(Kind) == .Int;
    return struct {
        const Interp = @This();

        value: union(enum) {
            started: struct {
                base: Kind,
                target: Kind,
                startTime: u64,
                timingFunction: TimingFunction,
                easeMode: EaseMode,
                // timingFunctionBack: TimingFunction,
                // timingFunctionForwards: TimingFunction,
                // eg EaseIn going down, EaseOut going up
            },
            unset: void,
        },
        transitionDuration: u64,

        pub fn init(transitionDuration: u64) Interp {
            return .{ .transitionDuration = transitionDuration, .value = .unset };
        }
        pub fn set(cinterp: *Interp, imev: *ImEvent, nv: Kind, timingFunction: TimingFunction, easeMode: EaseMode) void {
            const baseValue: Kind = if (cinterp.value == .started and imev.animationEnabled)
                if (std.meta.eql(cinterp.value.started.target, nv))
                    return {}
                else
                    cinterp.get(imev)
            else
                nv;
            cinterp.value = .{
                .started = .{
                    .base = baseValue,
                    .startTime = imev.time,
                    .target = nv,
                    .timingFunction = timingFunction,
                    .easeMode = easeMode,
                },
            };
        }
        pub fn get(cinterp: Interp, imev: *ImEvent) Kind {
            const dat = cinterp.value.started; // only call get after value has been set at least once
            if (!imev.animationEnabled) return dat.target;
            const timeOffset = @intToFloat(f64, imev.time - dat.startTime) / @intToFloat(f64, cinterp.transitionDuration);

            return switch (dat.easeMode) {
                .forward => help.interpolate(dat.base, dat.target, dat.timingFunction(timeOffset)),
                .reverse => help.interpolate(dat.base, dat.target, 1 - dat.timingFunction(1 - timeOffset)),
                .positive => if (isInt) if (dat.base > dat.target) help.interpolate(dat.base, dat.target, dat.timingFunction(timeOffset)) else help.interpolate(dat.base, dat.target, 1 - dat.timingFunction(1 - timeOffset)) else @panic(".positive is only available for integer types"),
                .negative => if (isInt) if (dat.base < dat.target) help.interpolate(dat.base, dat.target, dat.timingFunction(timeOffset)) else help.interpolate(dat.base, dat.target, 1 - dat.timingFunction(1 - timeOffset)) else @panic(".negative is only available for integer types"),
            };
        }
        pub fn getOptional(cinterp: Interp, imev: *ImEvent) ?Kind {
            if (cinterp.value == .started) return cinterp.get(imev);
            return null;
        }
        pub fn final(cinterp: Interp) Kind {
            return cinterp.value.started.target;
        }
    };
}

const ColorInterpolation = Interpolation(win.Color);
const PosInterpolation = Interpolation(i64);

pub const Button = struct {
    clickStarted: bool = false,
    text: Text,
    bumpColor: ColorInterpolation,
    topColor: ColorInterpolation,
    bumpOffset: PosInterpolation,

    pub fn init() Button {
        return .{
            .text = Text.init(),
            .bumpColor = ColorInterpolation.init(100),
            .topColor = ColorInterpolation.init(100),
            .bumpOffset = PosInterpolation.init(100),
        };
    }
    pub fn deinit(btn: *Button) void {
        btn.text.deinit();
    }

    const ButtonReturnState = struct {
        click: bool,
        active: bool,
    };
    pub fn render(
        btn: *Button,
        settings: struct {
            text: []const u8,
            font: *win.Font,
            active: bool = false,
            forceUp: bool = false,
            style: Style,
        },
        ev: *ImEvent,
        pos: win.Rect,
    ) !ButtonReturnState {
        const window = ev.window;

        const style = settings.style;
        var clickedThisFrame: bool = false;

        if (ev.mouseDown and win.Rect.containsPoint(pos, ev.cursor)) {
            ev.takeMouseDown();
            btn.clickStarted = true;
        }
        const hover = pos.containsPoint(ev.cursor);
        if (btn.clickStarted and ev.mouseUp) {
            btn.clickStarted = false;
            if (hover) {
                clickedThisFrame = true;
            }
        }
        const hoveringAny = hover and (btn.clickStarted or clickedThisFrame or !ev.click);
        if (hoveringAny) window.cursor = .pointer;

        const down = btn.clickStarted;

        const bumpHeight = 4;
        btn.bumpOffset.set(ev, if (down) 0 else if (settings.active and !settings.forceUp) @as(i64, 2) else @as(i64, 4), timing.EaseIn, .negative);
        const bumpOffset = btn.bumpOffset.get(ev);

        const buttonPos: win.Rect = pos.addHeight(-bumpHeight).down(bumpHeight - bumpOffset);
        const bumpPos: win.Rect = pos.downCut(pos.h - bumpHeight);

        btn.bumpColor.set(ev, if (settings.active)
            style.gui.button.shadow.active
        else
            style.gui.button.shadow.inactive, timing.Linear, .forward);
        btn.topColor.set(ev, if (hoveringAny)
            if (settings.active)
                style.gui.button.hover.active
            else
                style.gui.button.hover.inactive
        else if (settings.active)
            style.gui.button.base.active
        else
            style.gui.button.base.inactive, timing.Linear, .forward);

        // render
        {
            try win.renderRect(
                window,
                btn.bumpColor.get(ev),
                bumpPos,
            );
            try win.renderRect(
                window,
                btn.topColor.get(ev),
                buttonPos,
            );

            _ = try btn.text.render(
                .{
                    .text = settings.text,
                    .font = settings.font,
                    .color = style.gui.text,
                },
                ev,
                buttonPos,
            );
        }

        return ButtonReturnState{ .click = clickedThisFrame, .active = btn.clickStarted };
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

pub fn StructDataHelper(comptime Struct: type) fn (var) type {
    return struct {
        pub fn g(arg: var) type {
            return Part(help.FieldType(Struct, @tagName(arg)));
        }
    }.g;
}

pub fn Part(comptime Type: type) type {
    return struct {
        pub const EditorType = DataEditor(Type);
        editor: EditorType,
        visible: bool,
        toggleButton: Button,
        label: Text,
        choiceHeight: PosInterpolation,
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
    if (!@hasDecl(Struct, "ModeData")) @compileError("Any structs to be edited require a pub const ModeData = struct {...everything: gui.Part(type)}. This is because zig does not currently have @Type for structs.");

    return struct {
        const Editor = @This();
        data: DataStruct,
        pub const isInline = false;
        pub fn init() Editor {
            var data: DataStruct = undefined;
            inline for (@typeInfo(DataStruct).Struct.fields) |field| {
                @field(data, field.name) = .{
                    .editor = field.field_type.EditorType.init(),
                    .visible = true,
                    .toggleButton = Button.init(),
                    .label = Text.init(),
                    .choiceHeight = PosInterpolation.init(100),
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
            style: Style,
            ev: *ImEvent,
            pos: win.TopRect,
        ) !Height {
            const window = ev.window;
            const gap = seperatorGap;

            const lenInt = @intCast(i64, typeInfo.fields.len);
            var currentPos = pos;
            var trueHeight: i64 = 0;

            inline for (typeInfo.fields) |field, i| {
                const ItemType = @TypeOf(@field(editor.data, field.name).editor);
                var iteminfo = &@field(editor.data, field.name);
                var item = &iteminfo.editor;
                var fieldv = &@field(value, field.name);
                const labelText = getName(Struct, field.name);

                if (!ItemType.isInline) {
                    const area: win.Rect = currentPos.height(lineHeight);

                    const textSizeRect = try iteminfo.label.render(
                        .{
                            .text = labelText,
                            .font = style.fonts.standard,
                            .color = style.gui.text,
                            .halign = .left,
                        },
                        ev,
                        area,
                    );

                    if ((try iteminfo.toggleButton.render(
                        .{
                            .text = if (iteminfo.visible) "v" else ">",
                            .font = style.fonts.monospace,
                            .active = iteminfo.visible,
                            .style = style,
                        },
                        ev,
                        area.right(textSizeRect.w + textGap).position(.{ .w = 20, .h = 20 }, .left, .vcenter),
                    )).click) {
                        iteminfo.visible = !iteminfo.visible;
                        ev.rerender();
                    }
                    // this is where a stateful layout manager could be useful
                    // pos.right(count).newline().down(count)
                    currentPos.y += area.h + gap;
                    if (iteminfo.visible) {
                        var tmpY: i64 = 0;
                        const rh = try item.render(fieldv, style, ev, currentPos.rightCut(indentWidth));
                        tmpY += rh.h + gap;
                        iteminfo.choiceHeight.set(ev, tmpY, timing.EaseInOut, .forward);
                    } else {
                        iteminfo.choiceHeight.set(ev, 0, timing.EaseInOut, .forward);
                    }
                    const cval = iteminfo.choiceHeight.get(ev);
                    currentPos.y += cval;
                    trueHeight += iteminfo.choiceHeight.final() - cval;
                } else {
                    const rh = try item.render(
                        fieldv,
                        style,
                        ev,
                        currentPos.rightCut(textWidth + textGap),
                    );

                    _ = try iteminfo.label.render(
                        .{
                            .text = labelText,
                            .font = style.fonts.standard,
                            .color = style.gui.text,
                            .halign = .left,
                        },
                        ev,
                        currentPos.width(textWidth).height(rh.h),
                    );

                    currentPos.y += rh.h + gap;
                }
            }

            return Height{ .h = currentPos.y - pos.y - gap + trueHeight };
        }
    };
}

pub fn UnionDataHelper(comptime Union: type) fn (var) type {
    return struct {
        pub fn g(arg: var) type {
            if (@TypeOf(arg) == type) return @TagType(Union);
            return UnionPart(help.FieldType(Union, @tagName(arg)));
        }
    }.g;
}

pub fn UnionPart(comptime T: type) type {
    return DataEditor(T);
}

/// all choices must have a default value
fn UnionEditor(comptime Union: type) type {
    const typeInfo = @typeInfo(Union).Union;
    const Enum = typeInfo.tag_type orelse @compileError("Can only edit tagged unions");
    const enumInfo = @typeInfo(Enum).Enum;

    if (!@hasDecl(Union, "ModeData")) @compileError("Any unions to be edited require a pub const ModeData = union(Tag) {...everything: gui.UnionPart(type), pub const default_...everything = defaultValue;}. This is because zig does not currently have @Type for unions.");
    const modeDataInfo = @typeInfo(Union.ModeData).Union;
    const MdiEnum = modeDataInfo.tag_type orelse @compileError("ModeData must be a tagged union too!");
    if (Enum != MdiEnum) @compileError("ModeData tag must be outer union tag. Eg union(enum) {const Tag = @TagType(@This()); pub const ModeData = union(Tag){ ... };}");

    return struct {
        const Editor = @This();
        enumEditor: DataEditor(Enum),
        selectedUnionEditor: ?struct { choice: Enum, editor: Union.ModeData },
        deselectedUnionData: [typeInfo.fields.len]Union, // storage for if you enter some data and select a different union choice so when you go back, your data is still there
        choiceHeight: PosInterpolation,
        pub const isInline = false;
        pub fn init() Editor {
            return .{
                .enumEditor = DataEditor(Enum).init(),
                .deselectedUnionData = blk: {
                    var res: [typeInfo.fields.len]Union = undefined;
                    inline for (typeInfo.fields) |field, i| {
                        if (!@hasDecl(Union, "default_" ++ field.name)) @compileError("Missing default_" ++ field.name ++ ". All union choices to be edited require an accompanying pub const default_ value.");
                        res[i] = @unionInit(Union, field.name, @field(Union, "default_" ++ field.name));
                    }
                    break :blk res;
                },
                .selectedUnionEditor = null,
                .choiceHeight = PosInterpolation.init(100), // only for setting when we change enum values. otherwise, teleport. so that union{union{}} doesn't double interpolate.
            };
        }
        pub fn deinit(editor: *Editor) void {
            editor.enumEditor.deinit();
            if (editor.selectedUnionEditor) |*sue|
                help.unionCallThis("deinit", &sue.editor, .{});
        }
        pub fn render(
            editor: *Editor,
            value: *Union,
            style: Style,
            ev: *ImEvent,
            pos: win.TopRect,
        ) !Height {
            const window = ev.window;
            var cpos = pos;

            var trueHeight: i64 = 0;

            const originalTag = std.meta.activeTag(value.*);
            var activeTag = originalTag;
            cpos.y += (try editor.enumEditor.render(&activeTag, style, ev, pos)).h;
            if (activeTag != originalTag) {
                value.* = editor.deselectedUnionData[@enumToInt(activeTag)];
            }

            if (editor.selectedUnionEditor) |*sue| {
                if (sue.choice != activeTag) {
                    help.unionCallThis("deinit", &sue.editor, .{});
                    editor.selectedUnionEditor = null;
                }
            }
            if (editor.selectedUnionEditor == null) {
                editor.selectedUnionEditor = .{
                    .choice = activeTag,
                    .editor = help.unionCallReturnsThis(Union.ModeData, "init", activeTag, .{}),
                };
            }
            const sue = &editor.selectedUnionEditor.?;

            cpos.y += seperatorGap;

            const callOptions: std.builtin.CallOptions = .{};
            inline for (typeInfo.fields) |field| {
                if (@enumToInt(activeTag) == field.enum_field.?.value) {
                    // if(activeTag != originalTag)
                    //
                    var addY = (try @call(
                        callOptions,
                        help.FieldType(Union.ModeData, field.name).render,
                        .{ &@field(sue.editor, field.name), &@field(value, field.name), style, ev, cpos },
                    )).h;
                    if (addY > 0) addY += seperatorGap;
                    editor.choiceHeight.set(ev, addY, timing.EaseInOut, .forward);

                    const cval = editor.choiceHeight.get(ev);
                    cpos.y += cval;
                    trueHeight += editor.choiceHeight.final() - cval;
                    break;
                }
            }

            editor.deselectedUnionData[@enumToInt(activeTag)] = value.*;
            // it doesn't make sense to save it when it's active but idk how else to do it. this could be slow if the value is big.
            // eg if someone else changes the tag of value, all the data would be lost when switching tabs if we don't save it somehow and idk what to do about that

            return Height{ .h = cpos.y - pos.y - seperatorGap + trueHeight };
        }
    };
}

fn tagName0(thing: var) []const u8 {
    const TI = @typeInfo(@TypeOf(thing)).Enum;
    inline for (TI.fields) |fld| {
        if (@enumToInt(thing) == fld.value) {
            return fld.name ++ [_]u8{0};
        }
    }
    unreachable;
}

fn EnumEditor(comptime Enum: type) type {
    const typeInfo = @typeInfo(Enum).Enum;
    if (typeInfo.fields.len == 0) unreachable;
    return struct {
        const Editor = @This();
        dropdownMenuShow: Button,
        buttonData: [typeInfo.fields.len]Button,
        consideringChange: ?Enum = null,
        pub const isInline = true;
        pub fn init() Editor {
            return .{
                .dropdownMenuShow = Button.init(),
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
            editor.dropdownMenuShow.deinit();
        }
        pub fn render(
            editor: *Editor,
            value: *Enum,
            style: Style,
            ev: *ImEvent,
            pos: win.TopRect,
        ) !Height {
            const window = ev.window;
            const gap = connectedGap;

            const lenInt = @intCast(i64, typeInfo.fields.len);
            const choiceWidth = @divFloor(
                (pos.w - gap * (lenInt - 1)),
                lenInt,
            );
            if (choiceWidth > 50) {
                inline for (typeInfo.fields) |field, i| {
                    const choicePos = pos.rightCut((choiceWidth + gap) * @intCast(i64, i)).width(choiceWidth).height(lineHeight);
                    const thisTag = @field(Enum, field.name);

                    var btn = &editor.buttonData[i];
                    var btnRes = try btn.render(.{
                        .text = getName(Enum, field.name),
                        .active = value.* == thisTag,
                        .forceUp = value.* == thisTag and editor.consideringChange != null,
                        .font = style.fonts.standard,
                        .style = style,
                    }, ev, choicePos);
                    if (btnRes.click) {
                        value.* = @field(Enum, field.name);
                        ev.rerender();
                    }
                    if (btnRes.active and (editor.consideringChange == null or (editor.consideringChange != null and editor.consideringChange.? != thisTag))) {
                        editor.consideringChange = thisTag;
                        ev.rerender();
                    } else if (!btnRes.active and editor.consideringChange != null and editor.consideringChange.? == thisTag) {
                        editor.consideringChange = null;
                        ev.rerender();
                    }
                }
            } else {
                // render dropdown menu
                var btnRes = try editor.dropdownMenuShow.render(.{
                    .text = tagName0(value.*),
                    .font = style.fonts.standard,
                    .style = style,
                }, ev, pos.height(lineHeight));
                if (btnRes.click) {
                    var nv = @enumToInt(value.*);
                    if (nv == @typeInfo(Enum).Enum.fields.len - 1)
                        nv = 0
                    else
                        nv += 1;
                    value.* = @intToEnum(Enum, nv);
                }
            }

            return Height{ .h = lineHeight };
        }
    };
}

pub fn StringEditor(comptime RawData: type) type {
    const typeInfo = @typeInfo(RawData).Array;
    const Type = typeInfo.child;

    return struct {
        const Editor = @This();
        text: Text,
        pub const isInline = true;
        pub fn init() Editor {
            return .{
                .text = Text.init(),
            };
        }
        pub fn deinit(editor: *Editor) void {
            editor.text.deinit();
        }
        pub fn render(
            editor: *Editor,
            value: *RawData,
            style: Style,
            ev: *ImEvent,
            pos: win.TopRect,
        ) !Height {
            const window = ev.window;
            const area = pos.height(lineHeight);
            const textEntryArea = area.addHeight(-4);
            const belowTextArea = area.downCut(area.h - 4);

            const hover = area.containsPoint(ev.cursor) and !ev.click;
            if (hover) {
                window.cursor = .ibeam;
            }

            try win.renderRect(window, win.Color.hex(0x1c2029), textEntryArea);
            try win.renderRect(window, if (hover) win.Color.hex(0x565f73) else win.Color.hex(0x3f4757), belowTextArea);

            return Height{ .h = area.h };
        }
    };
}

pub fn ArrayEditor(comptime RawData: type) type {
    const typeInfo = @typeInfo(RawData).Array;
    const Type = typeInfo.child;
    if (Type == u8) return StringEditor(RawData);
    @compileError("Only strings are supported rn");
}

const WorkaroundError = error{CompilerBugWorkaround};

const VoidEditor = struct {
    const Editor = @This();
    pub const isInline = true;
    pub fn init() Editor {
        return .{};
    }
    pub fn deinit(editor: *Editor) void {}
    pub fn render(
        editor: *Editor,
        value: *void,
        style: Style,
        ev: *ImEvent,
        pos: win.TopRect,
    ) WorkaroundError!Height {
        const window = ev.window;
        return Height{ .h = 0 };
    }
};
// unioneditor is more difficult
// tabs at the top
// needs to keep data for each tab if you switch tabs and switch back

pub fn DataEditor(comptime Data: type) type {
    const typeInfo = @typeInfo(Data);
    return switch (typeInfo) {
        .Struct => StructEditor(Data),
        .Union => UnionEditor(Data),
        .Enum => EnumEditor(Data),

        .Array => ArrayEditor(Data),
        .Void => VoidEditor,

        else => @compileError("unsupported editor type: " ++ @tagName(@as(@TagType(@TypeOf(typeInfo)), typeInfo))),
    };
}

// eg StructEditor(enum {One, Two}) shows a select switch for one or two
