#include <raylib.h>

#ifdef workaround_implementation
	#define IMPL(body) body
#else
	#define IMPL(body) ;
#endif

void _wDrawTextureV(
	const Texture2D* texture, const Vector2* position, const Color* tint
) IMPL({
	DrawTextureV(*texture, *position, *tint);
})

void _wGetScreenToWorld2D(
	const Vector2* position, const Camera2D* camera, Vector2* out
) IMPL({
	*out = GetScreenToWorld2D(*position, *camera);
})