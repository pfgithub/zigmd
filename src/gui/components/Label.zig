// caching, non selectable text

const Text = @This();

text: ?struct {
    hash: u32, // std.hash.autoHash("text")
    text: win.Text,
    color: win.Color,
    font: *win.Font,
    const Me = @This();
    fn deinit(me: *Me) void {
        me.text.deinit();
    }
} = null,
pub fn init() Text {
    return .{};
}
pub fn deinit(txt: *Text) void {
    if (txt.text) |*text| text.deinit();
    txt.* = undefined;
}

fn requiresUpdate(txt: *Text, newColor: win.Color, newFont: *const win.Font, hashed: u32) bool {
    // hashed always needs to be calculated, no matter what this function returns
    if (txt.text) |*text| {
        if (text.font != newFont) return true;
        if (!std.meta.eql(text.color, newColor)) return true;
        if (text.hash != hashed) return true;
        return false;
    } else return true;
}

// NOTE: This item SHOULD NOT return its size. Instead, it should mutate layout
// to say how much space it has used.

/// Render the component, return the space it took up.
/// When rendering filled, this component will use all available space.
/// When rendering anchored, this component will expand in the allowed direction.
pub fn render(
    txt: *Text,
    layout: *Layout,
    placement: Layout.Placement,
    text: []const u8,
) !void {
    const window = layout.window;

    const color = layout.style(.label, .color);
    const font = layout.style(.label, .font);

    const hashed = std.hash_map.hashString(text);
    if (layout.duplicateCall or txt.requiresUpdate(color, font, hashed)) {
        if (txt.text) |*prev| prev.deinit();
        txt.text = try win.Text.init(font, color, text, null, window);
    }

    const textSizeRect = switch (placement) {
        // try window.pushClipRect(pos);
        // defer window.popClipRect();
        .fill => @panic("fill not implemented yet"),
        .anchored => |ancr| ancr.wh(txt.text.?.text.size.w, txt.text.?.text.size.h),
    };
    layout.reportSize(textSizeRect);

    //// ---------- RENDER -----------
    if (!layout.render) return;

    try text.text.render(.{
        .x = textSizeRect.x,
        .y = textSizeRect.y,
    });
}
