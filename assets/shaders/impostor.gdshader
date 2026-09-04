// Billboard impostor: picks the atlas frame nearest the camera direction (8 yaws x 2 elevations)
// and draws it on a camera-facing quad. Alpha scissor so it sorts like geometry.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, alpha_to_coverage;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform int yaws = 8;
uniform int elevations = 2;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;

varying vec2 frame_uv;

void vertex() {
	// Y-axis billboard: face the camera around the vertical axis only.
	vec3 to_cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - NODE_POSITION_WORLD;
	float yaw = atan(to_cam.x, to_cam.z);
	float elev = atan(to_cam.y, length(to_cam.xz));
	mat3 rot = mat3(vec3(cos(yaw), 0.0, -sin(yaw)), vec3(0.0, 1.0, 0.0), vec3(sin(yaw), 0.0, cos(yaw)));
	vec3 local = rot * VERTEX;
	VERTEX = local;
	NORMAL = rot * vec3(0.0, 0.0, 1.0);
	// frame selection (yaw measured the same way the baker moved the camera)
	float fy = mod(yaw / (2.0 * PI), 1.0) * float(yaws);
	int yi = int(floor(fy + 0.5)) % yaws;
	int ei = elev > radians(15.0) ? 1 : 0;
	int idx = ei * yaws + yi;
	vec2 cell = vec2(float(idx % 4), float(idx / 4)) / 4.0;
	frame_uv = cell + UV / 4.0;
}

void fragment() {
	vec4 c = texture(atlas, frame_uv);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALBEDO = c.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.05;
}
