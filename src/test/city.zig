const Tile = enum {
    // walkable
    floor,
    // not
    wall,
};
const Chunk = struct {
    x: i64,
    y: i64,
    z: i64,
    tiles: [chunk_wh][chunk_wh][chunk_d]Tile,
    const chunk_wh = 100;
    const chunk_d = 10;

    fn tileAt(chunk: *Chunk, x: i64, y: i64, z: i64) ?Tile {
        var cx = x - chunk.x;
        if (cx < 0 or cx > chunk_wh) return null;
        var cy = y - chunk.y;
        if (cy < 0 or cy > chunk_wh) return null;
        var cz = z - chunk.z;
        if (cz < 0 or cz > chunk_d) return null;
        return chunk.tiles[cx][cy][cz];
    }
};
const World = struct {
    chunk: Chunk,
    fn getTopTile(world: *World, x: i64, y: i64) *Tile {
        //
    }
};

// the goal is to make a city "simulator" thing
// randomly generated cities
// infinite world
// being able to walk around in vehicles while they move
// enter any building
