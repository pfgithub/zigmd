const std = @import("std");
const Alloc = std.mem.Allocator;

const main = @import("../main.zig");
const help = @import("../helpers.zig");
const gui = @import("../gui.zig");
const win = @import("../render.zig");
const Auto = gui.Auto;
const ImEvent = gui.ImEvent;

usingnamespace @import("game.zig");

pub const GameRender = struct {
    id: gui.ID,
    pub fn init(imev: *ImEvent) GameRender {
        return .{ .id = imev.newID() };
    }
    pub fn deinit(gr: *GameRender) void {}
    pub fn renderTile(gr: *GameRender, tile: Tile, imev: *ImEvent, rect: win.Rect) !void {
        try win.renderRect(imev.window, switch (tile) {
            .wall => win.Color.hex(0xFFFFFF),
            .floor => win.Color.hex(0xEEAAFF),
            .sidewalk => win.Color.hex(0xAAEEFF),
        }, rect);
    }
    pub fn render(gr: *GameRender, game: *Game, imev: *ImEvent, rect: win.Rect) !void {
        try imev.window.pushClipRect(rect);
        defer imev.window.popClipRect();

        const hs = imev.hover(gr.id, rect);

        if (hs.click) {
            game.camera.topLeft = game.camera.toWorldPoint(Point.from(game.camera.toScreenPoint(game.camera.topLeft)) //
                .subVec(.{ .x = @intToFloat(f64, imev.mouseDelta.x), .y = @intToFloat(f64, imev.mouseDelta.y) }) //
                .as(ScreenPoint));
        }

        var ul = game.camera.toWorldPoint(.{ .x = 0, .y = 0 }).toTilePoint();
        var dr = game.camera.toWorldPoint(.{ .x = @intToFloat(f64, rect.w), .y = @intToFloat(f64, rect.h) }).toTilePoint();

        var c: TilePoint = .{ .x = undefined, .y = ul.y };
        while (c.y <= dr.y) : (c.y += 1) {
            c.x = ul.x;
            while (c.x <= dr.x) : (c.x += 1) {
                const tile = game.surface.getTile(c) catch continue;
                const screenPos = game.camera.toScreenPoint(c.toWorldPoint());
                try gr.renderTile(tile, imev, .{
                    .x = @floatToInt(i64, screenPos.x),
                    .y = @floatToInt(i64, screenPos.y),
                    .w = @floatToInt(i64, game.camera.tileSize),
                    .h = @floatToInt(i64, game.camera.tileSize),
                });
            }
        }
    }
};
