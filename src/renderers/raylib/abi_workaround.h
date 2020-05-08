#include <raylib.h>

void waDrawTextureRec(const Texture2D* texture, const Rectangle* sourceRec, const Vector2* pos, const Color* tint);

#ifdef workaround_implementation
void waDrawTextureRec(const Texture2D* texture, const Rectangle* sourceRec, const Vector2* pos, const Color* tint) {
	DrawTextureRec(
		*texture, *sourceRec, *pos, *tint
	);
}
#endif

void workaroundScreenToWorld2D(const Vector2* position, const Camera2D* camera, Vector2* out);

#ifdef workaround_implementation
void waGetScreenToWorld2D(const Vector2* position, const Camera2D* camera, Vector2* out) {
	*out = GetScreenToWorld2D(*position, *camera);
}
#endif