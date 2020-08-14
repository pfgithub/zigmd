result: RollResult,
history: std.ArrayList(RollResult),

const Me = @This();

const RollResult = union(enum) {
    roll: struct { result: u8 },
};

// place renders the item for size only and then renders it for real
// builtin stuff like text probably wants to cache its size eg

pub fn render(me: Me, layout: *Layout) void {
    const vgrid = layout.vgrid(.{ .gap = 10, .overflow = .scroll });
    defer vgrid.end();

    layout.place(component.Label, .{"Hello! This is a test"});
    layout.place(component.Label, .{"If this is rendering correctly, that means it's working."});
}

pub fn renderReal(me: Me, layout: *Layout) void {
    var vgrid = layout.vgrid(.{ .gap = 10, .overflow = .scroll }); // in debug, these can capture a stack trace eg to say which one couldn't end
    defer vgrid.end();
    {
        var hgrid = layout.hgrid(.{ .overflow = .wrap, .gap = 10 });
        defer hgrid.end();
        if (layout.place(gui.Button, .{"Roll"}).click) {
            me.roll();
        }
        if (layout.place(gui.Button, .{"Roll 2"}).click) {
            me.roll2();
        }
        if (layout.place(gui.Button, .{"Roll Best 2 of 3"}).click) {
            me.roll3();
        }
    }
    {
        for (me.history.items) |histitm, i| {
            var k = layout.key(i) orelse continue; // if the item is too early and should be skipped. in the future, maybe layout could help even better idk
            defer k.end();

            // render history item
            var hgrid = layout.hgrid(.{ .overflow = .wrap, .gap = 10 });

            switch (histitem) {
                .roll => layout.place(gui.Text, .{.{ "Roll Result: ", r.roll }}),
            }
        }
    }
}
