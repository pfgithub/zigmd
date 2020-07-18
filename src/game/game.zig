const std = @import("std");

pub const Tile = union(enum) {
    floor,
    wall,
    sidewalk,

    pub fn fromChar(char: u8) !Tile {
        return switch (char) {
            '#' => .wall,
            '_' => .floor,
            '=' => .sidewalk,
            else => return error.InvalidTile,
        };
    }
};

pub const Surface = struct {
    const SURFACE_SIZE = 256;
    const SSInt = std.math.IntFittingRange(0, SURFACE_SIZE);
    tiles: [SURFACE_SIZE][SURFACE_SIZE]Tile,
    pub fn fromText(text: []const u8) !Surface {
        var res: Surface = .{ .tiles = undefined };
        var y: SSInt = 0;
        var x: SSInt = 0;
        @setEvalBranchQuota(10000000);
        for (text) |char| {
            x += 1;
            if (char == '\n') {
                if (x != SURFACE_SIZE) return error.TooWide;
                x = 0;
                y += 1;
                continue;
            }
            if (x >= SURFACE_SIZE) return error.TooWide;
            if (y >= SURFACE_SIZE) return error.TooTall;
            res.tiles[y][x] = try Tile.fromChar(char);
        }
        return res;
    }
    pub fn getTile(surf: *Surface, pt: TilePoint) !Tile {
        if (pt.x < 0 or pt.y < 0 or pt.x >= SURFACE_SIZE or pt.y >= SURFACE_SIZE) return error.OutOfBounds;
        return surf.tiles[@intCast(SSInt, pt.y)][@intCast(SSInt, pt.x)];
    }
};

pub const TilePoint = struct {
    // can't these just be vectors and then auto batch operations?
    // that's cheating a bit
    // but vector * 5 is a thing
    x: i64,
    y: i64,
    pub fn toWorldPoint(tp: TilePoint) WorldPoint {
        return .{ .x = @intToFloat(f64, tp.x), .y = @intToFloat(f64, tp.y) };
    }
};
// 1 x = 1 tile
pub const WorldPoint = struct {
    x: f64,
    y: f64,
    __worldPoint: void = {},
    pub fn toTilePoint(wp: WorldPoint) TilePoint {
        return .{ .x = @floatToInt(i64, wp.x), .y = @floatToInt(i64, wp.y) };
    }
};
// 0, 0 is top left. screen_width, screen_height is bottom right.
pub const ScreenPoint = struct { x: f64, y: f64, __screenPoint: void = {} };
pub const Point = struct {
    x: f64,
    y: f64,
    pub fn from(thing: anytype) Point {
        return .{ .x = thing.x, .y = thing.y };
    }
    pub fn as(point: Point, comptime Container: type) Container {
        return Container{ .x = point.x, .y = point.y };
    }
    pub fn mul(point: Point, v: f64) Point {
        return .{ .x = point.x * v, .y = point.y * v };
    }
    pub fn div(point: Point, v: f64) Point {
        return .{ .x = point.x / v, .y = point.y / v };
    }
    pub fn addVec(point: Point, ov: anytype) Point {
        return .{ .x = point.x + ov.x, .y = point.y + ov.y };
    }
    pub fn subVec(point: Point, ov: anytype) Point {
        return .{ .x = point.x - ov.x, .y = point.y - ov.y };
    }
};
pub const Camera = struct {
    topLeft: WorldPoint,
    tileSize: f64,
    pub fn toScreenPoint(camera: Camera, worldPoint: WorldPoint) ScreenPoint {
        return Point.from(worldPoint)
        // 1: untranslate
        .subVec(camera.topLeft)
        // 2: unscale
        .mul(camera.tileSize) //
            .as(ScreenPoint);
    }
    pub fn toWorldPoint(camera: Camera, screenPoint: ScreenPoint) WorldPoint {
        return Point.from(screenPoint)
        // 1: scale
        .div(camera.tileSize)
        // 2: translate
        .addVec(camera.topLeft) //
            .as(WorldPoint);
    }
};

pub const Game = struct {
    surface: Surface,
    camera: Camera,

    pub fn init() Game {
        return .{
            .surface = Surface.fromText(@embedFile("map.txt")) catch @panic("bad map"),
            .camera = .{ .topLeft = .{ .x = 0, .y = 0 }, .tileSize = 65 },
        };
    }
};
