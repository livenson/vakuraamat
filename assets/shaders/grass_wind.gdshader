// Grass card with wind sway. Alpha scissor, double-sided, tip-weighted sway from world position.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D card : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.25;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.4;
uniform vec3 tint : source_color = vec3(0.85, 0.9, 0.75);

void vertex() {
	float t = 1.0 - UV.y;                       // 0 at root, 1 at tip
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = wp.x * 0.35 + wp.z * 0.27;
	float sway = sin(TIME * wind_speed + phase) * 0.6 + sin(TIME * wind_speed * 2.3 + phase * 1.7) * 0.4;
	VERTEX.x += sway * wind_strength * t * t;
	VERTEX.z += sway * wind_strength * 0.5 * t * t;
}

void fragment() {
	vec4 c = texture(card, UV);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = c.rgb * tint * COLOR.rgb;   // COLOR = per-instance tint from the instancer
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	// fake translucency: brighter tips
	BACKLIGHT = vec3(0.3, 0.4, 0.15);
}
