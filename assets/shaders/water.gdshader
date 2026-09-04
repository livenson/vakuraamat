// Still water: two scrolling ripple normal layers, sky/SSR reflection, fresnel transparency.
shader_type spatial;
render_mode cull_back, depth_draw_always, specular_schlick_ggx;

uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.12, 0.2, 0.16);
uniform vec3 deep_color : source_color = vec3(0.03, 0.06, 0.07);
uniform float ripple_scale = 0.12;
uniform float ripple_speed = 0.03;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec2 uv = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz * ripple_scale;
	vec3 n1 = texture(normal_map, uv + vec2(TIME * ripple_speed, TIME * ripple_speed * 0.6)).xyz * 2.0 - 1.0;
	vec3 n2 = texture(normal_map, uv * 1.7 - vec2(TIME * ripple_speed * 0.8, -TIME * ripple_speed * 0.5)).xyz * 2.0 - 1.0;
	vec3 n = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = ripple_strength;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(shallow_color, deep_color, fresnel);
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ROUGHNESS = 0.05;
	ALPHA = mix(0.8, 0.97, fresnel);
}
