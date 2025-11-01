shader_type canvas_item;

uniform sampler2D effect_texture;
uniform vec2 effect_texture_size;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	vec4 s = texture(effect_texture, UV);
	vec4 w = vec4(0.0, 0.0, 1.0, s.x);
	vec4 p = vec4(1.0, 0.0, 0.0, s.y);
	vec3 b = (p.rgb * p.a) + (w.rgb * (1.0 - p.a));
	float a = p.a + w.a * (1.0 - p.a);
	COLOR = vec4(b.rgb, a);
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
