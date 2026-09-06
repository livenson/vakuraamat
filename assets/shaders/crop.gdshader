// Crop cards (scripts/world/crops.gd): lit by the sun and sky like the ground they stand on, with
// the normal fixed straight up so the back of a card is as bright as its front (a standard
// double-sided material flips the normal on back faces and turned half a field black). Alpha
// scissor, no shadows cast, the per-instance colour tints the texture.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_linear_mipmap;

void fragment() {
	vec4 c = texture(tex, UV) * COLOR;
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
