// The land still being surveyed: a soft, slowly breathing bank of haze standing on the tile that
// is being generated, fading out towards its top and edges so it reads as weather, not a wall.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 tint : source_color = vec4(0.82, 0.86, 0.9, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.55;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// box is size x 90 x size, centred; fade with height and towards the box's vertical edges
	float up = clamp(local_pos.y / 45.0 + 0.5, 0.0, 1.0);        // 0 at the bottom, 1 at the top
	float edge = 1.0 - max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0;
	float breathe = 0.85 + 0.15 * sin(TIME * 0.7 + local_pos.x * 0.01 + local_pos.z * 0.013);
	float drift = 0.5 + 0.5 * sin(local_pos.x * 0.02 + TIME * 0.3) * sin(local_pos.z * 0.017 - TIME * 0.2);
	float a = density * (1.0 - up) * (1.0 - up) * breathe * (0.6 + 0.4 * drift);
	ALBEDO = tint.rgb;
	ALPHA = clamp(a, 0.0, 0.8);
}
