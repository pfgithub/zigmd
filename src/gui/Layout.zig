// Sizing calls eg:
// say you want to render a label in a pill
// first you must do a sizing call and render the label
// then you know the size and can do a real call.
// Label should cache most of the information necessary,
// and Layout will be helpful and set duplicateCall to true the second time.
//
// eg it could look like this:
// ```
//  const size = layout.measure();
//  defer size.endMeasure()
//  if(size) |siz| {
//    render rectangle (siz)
//  }
//  render label
// ```
// since Layout is the only thing that calls the render fn, ...
// it can eg call it again
// this is basically react but it does layout too
// and *hopefully* is able to be faster
// eg good performance by default for long lists (as long as you specify .key())
// that is the hope, we'll see.

/// Whether a render is required or not. Render is not required for sizing calls or event handling in general.
render: bool = false,

/// True if a call is exactly the same as a previous call, but with render set to true this time.
/// EG: a size call is made to get the size of the item. Then, duplicateCall is set to true and
///     render is called again with the exact same args.
duplicateCall: bool = false,

const Placement = union(enum) {
    /// Placed item fills the area completely
    fill: win.Rect,
    /// Placed item expands in a given direction.
    /// Often, anchored items may need a first render to
    /// determine their size, and then a second render to
    /// actually draw to the screen.
    anchored: Anchor,
    const Anchor = struct {
        anchor: win.Point,
        halign: win.HAlign,
        valign: win.VAlign,
        pub fn wh(ancr: Anchor, w: i64, h: i64) win.Rect {
            if (ancr.valign != .top) @panic("Unsupported");
            if (ancr.halign != .left) @panic("Unsupported");
            return .{ .x = ancr.anchor.x, .y = ancr.anchor.y, .w = w, .h = h };
        }
    };
};

pub fn Ender(comptime EndFn: anytype) type {
    return struct {
        me: *Me,
        const This = @This();
        pub fn end(me: This) void {
            return EndFn(me.me);
        }
    };
}

const Layout = @This();

pub fn vgrid() Ender(vgridEnd) {}
pub fn hgrid() Ender(hgridEnd) {}
pub fn place(comptime Item: Type, args: anytype) Item.RenderResult {}

pub fn key(k: anytype) Ender(keyEnd) {}

pub const StyleProp = enum {
    color,
    font,
    pub fn Type(me: StyleProp) type {
        return switch (me) {
            .color => win.Color,
            .font => *win.Font,
        };
    }
};

/// TODO completely replace this with something actually useful
/// maybe there is like a `clean layout.class(.classname)` and then there is css
/// that is a bad idea
/// is it?
pub fn style(layout: *Layout, comptime a: anytype, comptime b: StyleProp) b.Type() {
    switch (b) {
        .color => return layout.style.gui.text,
        .font => return layout.style.fonts.standard,
    }
}
