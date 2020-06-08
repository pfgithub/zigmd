const std = @import("std");
const main = @import("main.zig");
const win = @import("render.zig");
const help = @import("helpers.zig");
const Auto = @import("Auto.zig");

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
                pub fn of(activity: Active, mode: bool) win.Color {
                    return if (mode) activity.active else activity.inactive;
                }
            };
            base: Active,
            hover: Active,
            shadow: Active,
        },
        hole: struct {
            floor: win.Color,
            wall: win.Color,
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

pub const ID = struct {
    // lower 48 is what is updated by .newID()
    // upper 16 is used by id.next(count)
    id: u64 = 0,
    pub fn next(id: ID, count: u16) ID {
        if (id.id > std.math.maxInt(u48)) @panic("next used on already next id");
        return .{ .id = id.id + std.math.maxInt(u48) * @as(u64, count) };
    }
};

pub const ImEvent = struct {
    const Internal = struct {
        mouseDown: bool = false,
        click: bool = false,
        rerender: bool = undefined,
        latestAssignedID: u32 = 0,

        hoverID: u64 = 0,
        clickID: u64 = 0,
        scrollID: u64 = 0,
        prevScrollDelta: win.Point = undefined,
        next: Next = Next{},

        const Next = struct {
            hoverID: u64 = 0,
            clickID: u64 = 0,
            scrollID: u64 = 0,
        };
    };
    const Data = struct {
        settings: struct {
            style: Style,
            updateMode: main.UpdateMode,
        },
    };
    data: Data,
    internal: Internal = Internal{},
    click: bool = false,
    mouseDown: bool = false,
    mouseUp: bool = undefined,
    mouseDelta: win.Point = undefined,
    cursor: win.Point = win.Point{ .x = 0, .y = 0 },
    keyDown: ?win.Key = undefined,
    key: KeyArr = KeyArr.initDefault(false),
    keyUp: ?win.Key = undefined,
    textInput: ?win.Event.TextInput = undefined,
    time: u64 = undefined,
    animationEnabled: bool = false,
    scrollDelta: win.Point = win.Point{ .x = 0, .y = 0 },
    // unfortunately, sdl scrolling is really bad. numbers are completely random and useless,
    // and it only scrolls by whole ticks. this is one of the places raylib is better.
    window: *win.Window = undefined,
    render: bool = false,
    const KeyArr = help.EnumArray(win.Key, bool);

    pub fn newID(imev: *ImEvent) ID {
        imev.internal.latestAssignedID += 1;
        return .{ .id = imev.internal.latestAssignedID };
    }

    pub const Hover = struct {
        click: bool,
        hover: bool,
    };
    pub fn hover(imev: *ImEvent, id: ID, rect_: win.Rect) Hover {
        if (imev.mouseUp) {
            imev.internal.next.clickID = 0;
        }
        const rect = if (imev.window.clippingRectangle()) |cr| rect_.overlap(cr) else rect_;
        if (rect.containsPoint(imev.cursor)) {
            imev.internal.next.hoverID = id.id;
            if (imev.mouseDown) {
                imev.internal.next.clickID = id.id;
            }
        }
        return .{
            .hover = imev.internal.hoverID == id.id and if (imev.internal.clickID != 0)
                imev.internal.hoverID == imev.internal.clickID
            else
                true,
            .click = imev.internal.clickID == id.id,
        };
    }
    pub fn scroll(imev: *ImEvent, id: ID, rect_: win.Rect) win.Point {
        const rect = if (imev.window.clippingRectangle()) |cr| rect_.overlap(cr) else rect_;
        // overview:
        // - if scrolled:
        if (!std.meta.eql(imev.scrollDelta, win.Point.origin)) {
            if (rect.containsPoint(imev.cursor))
                imev.internal.next.scrollID = id.id;
            // there needs to be some way to keep the current scroll id if:
            //      the last scroll was <300ms ago
            // and  the last scroll is still under the cursor
        }
        if (imev.internal.scrollID == id.id) {
            return imev.internal.prevScrollDelta;
        }
        return .{ .x = 0, .y = 0 };
    }

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
        imev.internal.prevScrollDelta = imev.scrollDelta;
        imev.scrollDelta = .{ .x = 0, .y = 0 };

        // is this worth it or should it be written manually? // not worth it
        // inline for (@typeInfo(Internal.Next).Struct.fields) |field| {
        //     @field(imev.internal, field.name) = @field(imev.internal.next, field.name);
        //     @field(imev.internal.next, field.name) = 0;
        // }

        imev.internal.hoverID = imev.internal.next.hoverID;
        imev.internal.next.hoverID = 0;

        imev.internal.clickID = imev.internal.next.clickID;

        imev.internal.scrollID = imev.internal.next.scrollID;
        imev.internal.next.scrollID = 0;

        const startCursor = imev.cursor;

        // apply event
        switch (ev) {
            .mouseMotion => |mmv| {
                imev.cursor = mmv.pos;
            },
            .mouseDown => |clk| {
                imev.internal.mouseDown = true;
                imev.cursor = clk.pos;
                imev.internal.click = true;
            },
            .mouseUp => |clk| {
                imev.mouseUp = true;
                imev.cursor = clk.pos;
                imev.internal.click = false;
            },
            .keyDown => |keyev| {
                imev.keyDown = keyev.key;
                _ = imev.key.set(keyev.key, true);
            },
            .keyUp => |keyev| {
                _ = imev.key.set(keyev.key, false);
                imev.keyUp = keyev.key;
            },
            .textInput => |textin| {
                imev.textInput = textin;
            },
            .mouseWheel => |wheel| {
                imev.scrollDelta = .{ .x = wheel.x, .y = wheel.y };
            },
            else => {},
        }

        // transfer internal to ev itself
        imev.mouseDown = imev.internal.mouseDown;
        imev.click = imev.internal.click;
        imev.mouseDelta = .{ .x = imev.cursor.x - startCursor.x, .y = imev.cursor.y - startCursor.y };
    }
    pub fn rerender(imev: *ImEvent) void {
        imev.internal.rerender = true;
    }
};

// caching text
pub const Text = struct {
    id: ID,
    text: ?struct {
        hash: u32, // std.hash.autoHash("text")
        text: win.Text,
        color: win.Color,
        font: *win.Font,
    } = null,
    pub fn init(ev: *ImEvent) Text {
        return .{ .id = ev.newID() };
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
        if (ev.render)
            try text.text.render(window, .{
                .x = textSizeRect.x,
                .y = textSizeRect.y,
            });
        return textSizeRect; // if this didn't return its size, it wouldn't be necessary to do anything here except on the last frame
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
                exact: ?Kind,
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
        pub fn autoInit(event: *ImEvent, alloc: *std.mem.Allocator) Interp {
            return init(100); // maybe transitionDuration should be a comptime arg to the type
        }
        pub fn teleport(cinterp: *Interp, imev: *ImEvent, nv: Kind, timingFunction: TimingFunction, easeMode: EaseMode) void {
            if (cinterp.value.started.exact == null)
                cinterp.set(imev, nv, timingFunction, easeMode);
            cinterp.value.started.exact = nv;
        }
        pub fn set(cinterp: *Interp, imev: *ImEvent, nv: Kind, timingFunction: TimingFunction, easeMode: EaseMode) void {
            const baseValue: Kind = if (cinterp.value == .started and imev.animationEnabled)
                if (std.meta.eql(cinterp.value.started.target, nv)) {
                    cinterp.value.started.exact = null;
                    return {};
                } else
                    cinterp.get(imev)
            else
                nv;
            cinterp.value = .{
                .started = .{
                    .base = baseValue,
                    .startTime = imev.time,
                    .target = nv,
                    .exact = null,
                    .timingFunction = timingFunction,
                    .easeMode = easeMode,
                },
            };
        }
        pub fn animationProgressLinear(cinterp: Interp, imev: *ImEvent) f64 {
            const dat = cinterp.value.started;
            return @intToFloat(f64, imev.time - dat.startTime) / @intToFloat(f64, cinterp.transitionDuration);
        }
        pub fn animationProgress(cinterp: Interp, imev: *ImEvent) f64 {
            const dat = cinterp.value.started;
            const timeOffset = cinterp.animationProgressLinear(imev);
            return switch (dat.easeMode) {
                .forward => dat.timingFunction(timeOffset),
                .reverse => 1 - dat.timingFunction(1 - timeOffset),
                .positive, .negative => blk: {
                    if (!isInt) @panic(".positive is only available for integer types");
                    const target = cinterp.final();
                    return if (if (dat.easeMode == .positive) dat.base > target else dat.base < target)
                        dat.timingFunction(timeOffset)
                    else
                        1 - dat.timingFunction(1 - timeOffset);
                },
            };
        }
        pub fn get(cinterp: Interp, imev: *ImEvent) Kind {
            const dat = cinterp.value.started; // only call get after value has been set at least once
            if (!imev.animationEnabled) return cinterp.final();
            const animProgress = cinterp.animationProgress(imev);
            const target = cinterp.final();

            return help.interpolate(dat.base, target, animProgress);
        }
        pub fn getOptional(cinterp: Interp, imev: *ImEvent) ?Kind {
            if (cinterp.value == .started) return cinterp.get(imev);
            return null;
        }
        pub fn final(cinterp: Interp) Kind {
            return if (cinterp.value.started.exact) |exct| exct else cinterp.value.started.target;
        }
    };
}

pub const ColorInterpolation = Interpolation(win.Color);
pub const PosInterpolation = Interpolation(i64);

pub const Button = struct {
    id: ID,
    text: Text,
    bumpColor: ColorInterpolation,
    topColor: ColorInterpolation,
    bumpOffset: PosInterpolation,

    pub fn init(ev: *ImEvent) Button {
        return .{
            .id = ev.newID(),
            .text = Text.init(ev),
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
        imev: *ImEvent,
        pos: win.Rect,
    ) !ButtonReturnState {
        const window = imev.window;

        const style = settings.style;
        var clickedThisFrame: bool = false;

        const hoverfocus = imev.hover(btn.id, pos);
        const hover = hoverfocus.hover;
        const click = hoverfocus.click;

        if (imev.mouseUp and hover and click) {
            clickedThisFrame = true;
        }

        // no user interaction below this line
        if (!imev.render)
            return ButtonReturnState{
                .click = clickedThisFrame,
                .active = click,
            };

        if (hover) window.cursor = .pointer;

        const bumpHeight = 4;
        btn.bumpOffset.set(imev, if (click) 0 else if (settings.active and !settings.forceUp) @as(i64, 2) else @as(i64, 4), timing.EaseIn, .negative);
        const bumpOffset = btn.bumpOffset.get(imev);

        const buttonPos: win.Rect = pos.addHeight(-bumpHeight).down(bumpHeight - bumpOffset);
        const bumpPos: win.Rect = pos.downCut(pos.h - bumpHeight);

        btn.bumpColor.set(imev, if (settings.active)
            style.gui.button.shadow.active
        else
            style.gui.button.shadow.inactive, timing.Linear, .forward);
        btn.topColor.set(imev, if (hover)
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
                btn.bumpColor.get(imev),
                bumpPos,
            );
            try win.renderRect(
                window,
                btn.topColor.get(imev),
                buttonPos,
            );

            _ = try btn.text.render(
                .{
                    .text = settings.text,
                    .font = settings.font,
                    .color = style.gui.text,
                },
                imev,
                buttonPos,
            );
        }

        return ButtonReturnState{ .click = clickedThisFrame, .active = click };
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
        id: ID,
        data: DataStruct,
        pub const isInline = false;
        pub fn init(ev: *ImEvent) Editor {
            var data: DataStruct = undefined;
            inline for (@typeInfo(DataStruct).Struct.fields) |field| {
                @field(data, field.name) = .{
                    .editor = field.field_type.EditorType.init(ev),
                    .visible = true,
                    .toggleButton = Button.init(ev),
                    .label = Text.init(ev),
                    .choiceHeight = PosInterpolation.init(100),
                };
            }
            return .{
                .id = ev.newID(),
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

            var valu = false;
            if (valu) return error.WorkaroundCompilerBug;

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

            return Height{ .h = std.math.max(currentPos.y - pos.y - gap + trueHeight, 0) };
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

    const ModeData = if (@hasDecl(Union, "ModeData")) Union.ModeData else if (@hasDecl(Union, "ModeData2")) Union.ModeData2 else @compileError("Any unions to be edited require a pub const ModeData = union(Tag) {...everything: gui.UnionPart(type), pub const default_...everything = defaultValue;}. This is because zig does not currently have @Type for unions.");
    const modeDataInfo = @typeInfo(ModeData).Union;
    const MdiEnum = modeDataInfo.tag_type orelse @compileError("ModeData must be a tagged union too!");
    if (Enum != MdiEnum) @compileError("ModeData tag must be outer union tag. Eg union(enum) {const Tag = @TagType(@This()); pub const ModeData = union(Tag){ ... };}");

    return struct {
        const Editor = @This();
        id: ID,
        enumEditor: DataEditor(Enum),
        selectedUnionEditor: ?struct { choice: Enum, editor: ModeData },
        deselectedUnionData: [typeInfo.fields.len]Union, // storage for if you enter some data and select a different union choice so when you go back, your data is still there
        choiceHeight: PosInterpolation,
        pub const isInline = false;
        pub fn init(ev: *ImEvent) Editor {
            return .{
                .id = ev.newID(),
                .enumEditor = DataEditor(Enum).init(ev),
                .deselectedUnionData = blk: {
                    var res: [typeInfo.fields.len]Union = undefined;
                    inline for (typeInfo.fields) |field, i| {
                        const defaultValue = if (@hasDecl(Union, "default_" ++ field.name))
                            @field(Union, "default_" ++ field.name)
                        else if (help.FieldType(Union, field.name) == void)
                            ({})
                        else
                            @compileError("Missing default_" ++ field.name ++ ". All union choices to be edited require an accompanying pub const default_ value.");
                        res[i] = @unionInit(Union, field.name, defaultValue);
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
                    .editor = help.unionCallReturnsThis(ModeData, "init", activeTag, .{ev}),
                };
            }
            const sue = &editor.selectedUnionEditor.?;

            cpos.y += seperatorGap;

            const callOptions: std.builtin.CallOptions = .{};
            inline for (typeInfo.fields) |field| {
                if (@enumToInt(activeTag) == field.enum_field.?.value) {
                    var addY = (try @call(
                        callOptions,
                        help.FieldType(ModeData, field.name).render,
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

fn tagNameTerminated(thing: var, comptime terminator: []const u8) []const u8 {
    const TI = @typeInfo(@TypeOf(thing)).Enum;
    inline for (TI.fields) |fld| {
        if (@enumToInt(thing) == fld.value) {
            return fld.name ++ terminator;
        }
    }
    unreachable;
}

fn EnumEditor(comptime Enum: type) type {
    const typeInfo = @typeInfo(Enum).Enum;
    if (typeInfo.fields.len == 0) unreachable;
    return struct {
        const Editor = @This();
        id: ID,
        dropdownMenuShow: Button,
        buttonData: [typeInfo.fields.len]Button,
        consideringChange: ?Enum = null,
        pub const isInline = true;
        pub fn init(ev: *ImEvent) Editor {
            return .{
                .id = ev.newID(),
                .dropdownMenuShow = Button.init(ev),
                .buttonData = blk: {
                    var res: [typeInfo.fields.len]Button = undefined;
                    inline for (typeInfo.fields) |field, i| {
                        res[i] = Button.init(ev);
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
                // ev.pushOverlay(&editor.dropdownMenu, DropdownMenu.render);
                // pushOverlay allocates a temporary value for args that is deleted
                // after the function is called
                // how to get results back from the overlay? it only gets called
                // after all the normal stuff is rendered

                // if(activeTag != originalTag)
                //
                // pushOverlay? how to get results back then? frame delay? that introduces a frame delay for every overlay
                // maybe just frame delay if it returns? that significantly limits what can be done but might work
                // overlayReturn = editor.dropdownMenu.returnValue;
                // if(overlayReturn) { menu is closed }
                // else try imev.pushOverlay(.{}); // allocates some memory and puts it into a void*. maybe comptime stores a set of mappings from type => argtype to make sure the type is correct?
                // if(editor.showDropdown)
                var btnRes = try editor.dropdownMenuShow.render(.{
                    .text = tagNameTerminated(value.*, &[_]u8{ ' ', 'v', 0 }),
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

pub fn Dropdown(comptime Choices: []const []const u8) type {
    return struct {
        const Editor = @This();
    };
}

pub fn StringEditor(comptime RawData: type) type {
    const typeInfo = @typeInfo(RawData).Array;
    const Type = typeInfo.child;

    return struct {
        const Editor = @This();
        id: ID,
        text: Text,
        pub const isInline = true;
        pub fn init(ev: *ImEvent) Editor {
            return .{
                .id = ev.newID(),
                .text = Text.init(ev),
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

            const hover = ev.hover(editor.id, area);
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

pub fn VoidEditor(comptime Ignore: type) type {
    return struct {
        const Editor = @This();
        pub const isInline = true;
        pub fn init(ev: *ImEvent) Editor {
            return .{};
        }
        pub fn deinit(editor: *Editor) void {}
        pub fn render(
            editor: *Editor,
            value: *Ignore,
            style: Style,
            ev: *ImEvent,
            pos: win.TopRect,
        ) WorkaroundError!Height {
            const window = ev.window;
            return Height{ .h = 0 };
        }
    };
}

pub fn UnsupportedEditor(comptime Ignore: type) type {
    return struct {
        const Editor = @This();
        id: ID,
        text: Text,
        pub const isInline = true;
        pub fn init(ev: *ImEvent) Editor {
            return .{ .id = ev.newID(), .text = Text.init(ev) };
        }
        pub fn deinit(editor: *Editor) void {
            editor.text.deinit();
        }
        pub fn render(
            editor: *Editor,
            value: *Ignore,
            style: Style,
            ev: *ImEvent,
            pos: win.TopRect,
        ) !Height {
            const window = ev.window;
            const size = pos.height(lineHeight);
            _ = try editor.text.render(.{
                .text = "Unsupported Editor Type: " ++ @typeName(Ignore),
                .font = style.fonts.standard,
                .color = style.colors.errorc,
                .halign = .left,
            }, ev, size);
            return Height{ .h = size.h };
        }
    };
}

pub fn BoolEditor(comptime Bool: type) type {
    return struct {
        const Editor = @This();
        id: ID,
        rightOffset: PosInterpolation,
        clicking: union(enum) { no: void, yes: struct { start: usize, moved: bool } },
        buttonColor: ColorInterpolation,
        buttonShadowColor: ColorInterpolation,
        buttonPressLevel: PosInterpolation,
        pub const isInline = true;
        pub fn init(ev: *ImEvent) Editor {
            return .{
                .id = ev.newID(),
                .rightOffset = PosInterpolation.init(200),
                .buttonColor = ColorInterpolation.init(100),
                .buttonShadowColor = ColorInterpolation.init(100),
                .buttonPressLevel = PosInterpolation.init(100),
                .clicking = .no,
            };
        }
        pub fn deinit(editor: *Editor) void {}
        pub fn render(
            editor: *Editor,
            value: *Bool,
            style: Style,
            ev: *ImEvent,
            pos: win.TopRect,
        ) !Height {
            // todo update this to have some scaling stuff
            // holds left line while < 0.5, transitions over to right line past 0.5
            // right now this switch feels not clicky enough and weirdly smooth
            const window = ev.window;
            const area = pos.height(lineHeight);
            const knobSize = win.WH{ .w = 20, .h = 20 };
            const switchPos = area.position(
                .{ .w = knobSize.w * 2, .h = knobSize.h },
                .left,
                .vcenter,
            );

            const hc = ev.hover(editor.id, switchPos);
            const hover = hc.hover;
            const hoveringThis = (hover and !ev.click) or (hover and editor.clicking == .yes);
            var rightOffset = if (!value.*) 0 else switchPos.w - knobSize.w;
            const switchButtonArea = switchPos.width(@divFloor(switchPos.w, 2)).right(if (value.*) @divFloor(switchPos.w, 2) else 0);
            if (hover) {
                if (ev.mouseDown) {
                    editor.clicking = .{
                        .yes = .{
                            .moved = !switchButtonArea.containsPoint(ev.cursor),
                            .start = ev.time,
                        },
                    };
                }
            }
            if (editor.clicking == .yes) {
                const clk = &editor.clicking.yes;
                if (!clk.moved and ev.mouseDelta.x != 0)
                    clk.moved = true;
                if (clk.moved) {
                    rightOffset = ev.cursor.x - (knobSize.w / 2) - switchPos.x;
                    rightOffset = std.math.max(std.math.min(rightOffset, switchPos.w - knobSize.w), 0);
                }
                if (clk.moved)
                    editor.rightOffset.teleport(ev, rightOffset, timing.EaseInOut, .forward)
                else
                    editor.rightOffset.set(ev, rightOffset, timing.EaseInOut, .forward);

                if (ev.mouseUp) {
                    const moved = clk.moved;
                    const clkstart = clk.start;
                    editor.clicking = .no;
                    if (hover and (!moved or ev.time - clkstart < 100)) {
                        value.* = !value.*;
                    } else if (rightOffset < @divFloor(switchPos.w, 2) - knobSize.w / 2) {
                        value.* = false;
                    } else {
                        value.* = true;
                    }
                    ev.rerender();
                }
            }
            if (editor.clicking == .no) {
                editor.rightOffset.set(ev, rightOffset, timing.EaseInOut, .forward);
            }

            try win.renderRect(window, style.gui.hole.wall, switchPos.downCut(4).height(4));
            try win.renderRect(window, style.gui.hole.floor, switchPos.downCut(8));

            const visualRightOffset = editor.rightOffset.get(ev);
            editor.buttonPressLevel.set(ev, if (editor.clicking == .yes and ev.time - editor.clicking.yes.start > 100) 4 else if (value.*) @as(i64, 0) else 0, timing.EaseIn, .negative);
            const resh = editor.buttonPressLevel.get(ev);

            editor.buttonColor.set(ev, (if (hoveringThis) style.gui.button.hover else style.gui.button.base).of(value.*), timing.Linear, .forward);
            editor.buttonShadowColor.set(ev, style.gui.button.shadow.of(value.*), timing.Linear, .forward);

            var finalSwitchPos = switchPos.width(knobSize.w).right(visualRightOffset);

            if (visualRightOffset < @divFloor(switchPos.w, 2) - knobSize.w / 2) {
                finalSwitchPos = finalSwitchPos.setX(switchPos.x).addWidth(visualRightOffset * 2);
            } else {
                const finalWidth = (20 - visualRightOffset) * 2 + knobSize.w;
                finalSwitchPos = finalSwitchPos.setX2(switchPos.x + switchPos.w).setX1(switchPos.x + switchPos.w - finalWidth);
            }

            try win.renderRect(window, editor.buttonColor.get(ev), finalSwitchPos.down(resh).addHeight(-4));
            try win.renderRect(window, editor.buttonShadowColor.get(ev), finalSwitchPos.downCut(switchPos.h - 4 + resh));

            return Height{ .h = area.h };
        }
    };
}

pub const EditorHeader = struct {
    pub const isInline: bool = undefined;
    pub fn init(ev: *ImEvent) EditorHeader {
        return undefined;
    }
    pub fn deinit(editor: *EditorHeader) void {}
    pub fn render(
        editor: *EditorHeader,
        value: *Ignore,
        style: Style,
        ev: *ImEvent,
        pos: win.TopRect,
    ) header_check.types.atleastOneError(Height) {
        return undefined;
    }
};

pub fn DataEditor(comptime Data: type) type {
    const typeInfo = @typeInfo(Data);
    return switch (typeInfo) {
        .Struct => StructEditor(Data),
        .Union => UnionEditor(Data),
        .Enum => EnumEditor(Data),

        .Bool => BoolEditor(Data),
        // .Array => ArrayEditor(Data),
        .Void => VoidEditor(Data),

        else => UnsupportedEditor(Data),
    };
}

// to help with this, lots of optimization can be done in child components
// eg don't render if out of view. maybe don't even do any processing unless
// in view. that would make global "find" methods harder though, find would
// be pretty "simple" if text is always at least processed. that doesn't
// matter though.

/// child must have an autoDeinit fn.
pub fn ScrollView(comptime Child: type) type {
    return struct {
        const Me = @This();

        auto: Auto,
        child: Child,

        scrollY: i64 = 0,
        scrollYAnim: PosInterpolation,

        pub fn init(ev: *ImEvent, alloc: *std.mem.Allocator) Me {
            return Auto.create(Me, ev, alloc, .{});
        }

        pub fn autoDeinit(me: *Me) void {
            Auto.destroy(me, .{ .auto, .child });
        }

        pub fn render(
            me: *Me,
            childArgs: var,
            style: Style,
            imev: *ImEvent,
            pos: win.Rect,
        ) !void {
            try imev.window.pushClipRect(pos);
            defer imev.window.popClipRect();

            // scroll will need a timeout so if you are just scrolling you
            // don't get to another scrollview and immediately start scrolling it
            // instead it keeps scrolling the thing you were scrolling until
            // it has been a few hundred ms.

            me.scrollYAnim.set(imev, me.scrollY, timing.EaseIn, .reverse);
            const visualScrollY = me.scrollYAnim.get(imev);
            var updPos = pos.noHeight().down(-visualScrollY);

            var resHeight = try @call(.{}, me.child.render, childArgs ++ .{ style, imev, updPos });

            const scrollDistance = imev.scroll(me.auto.id, pos).y;
            me.scrollY -= scrollDistance;
            if (me.scrollY > resHeight.h - lineHeight) me.scrollY = resHeight.h - lineHeight;
            if (me.scrollY < 0) me.scrollY = 0;

            if (scrollDistance != 0)
                imev.rerender();
        }
    };
}
