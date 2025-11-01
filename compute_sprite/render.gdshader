shader_type canvas_item;

uniform sampler2D effect_texture;
uniform vec2 effect_texture_size;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	ivec2 coords = ivec2(effect_texture_size * UV);
	vec4 s = texelFetch(effect_texture, coords, 0);
	vec4 w = vec4(0.0, 0.0, 1.0, s.x);               // wet pixels = blue
	vec4 p = vec4(1.0, 0.0, 0.0, s.y);               // pigmen pixels = red
	// composite them with blue underneath, but note that we ensure 
	// no blue will appear when there is no water present by doing `w.rgb * w.a`
	// we do this because the water is only shown for helping understand what is being painted
	vec3 b = (p.rgb * p.a) + (w.rgb * w.a * (1.0 - p.a));
	float a = p.a + w.a * (1.0 - p.a);
	COLOR = vec4(b.rgb, clamp(a, 0.0, 1.0));
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
