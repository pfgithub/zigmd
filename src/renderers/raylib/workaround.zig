pub usingnamespace @cImport({
    // @cDefine("SUPPORT_EVENTS_WAITING", "");
    @cInclude("raylib.h");
    @cInclude("workaround.h");
});

pub fn WDrawTextureV(texture: Texture2D, position: Vector2, tint: Color) void {
    _wDrawTextureV(&texture, &position, &tint);
}
pub fn WGetScreenToWorld2D(position: Vector2, camera: Camera2D) Vector2 {
    var out: Vector2 = undefined;
    _wGetScreenToWorld2D(&position, &camera, &out);
    return out;
}
