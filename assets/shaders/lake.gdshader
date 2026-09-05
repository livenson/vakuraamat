// Lake and pond water: gentle Gerstner ripples, two scrolling normal layers, depth-based colour
// (Beer's law) with refraction of what lies below, foam along the shore, sky reflection.
// Adapted for Godot 4.7 and still inland water from the "Realistic Water Shader" by UnionBytes
// (Achim Menzel) and K. S. Ernest Lee, https://github.com/godot-extended-libraries/godot-realistic-water,
// MIT licence (see THIRD_PARTY.md). Opaque with a screen-texture composite: no alpha sorting, SSR works.
shader_type spatial;
render_mode cull_back, depth_draw_always, diffuse_burley, specular_schlick_ggx;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float wave_speed = 0.35;
uniform vec4 wave_a = vec4(1.0, 0.4, 0.05, 7.0);    // xy direction, z steepness, w length (m)
uniform vec4 wave_b = vec4(-0.3, 0.8, 0.04, 4.2);
uniform vec4 wave_c = vec4(-0.9, -0.6, 0.03, 2.3);

uniform sampler2D normalmap_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 0.09;                   // texture repeats per metre
uniform vec2 normal_drift = vec2(0.018, 0.012);     // metres per second
uniform float normal_strength : hint_range(0.0, 1.0) = 0.45;

uniform sampler2D foam_sampler : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float foam_level = 0.6;                      // metres of water depth under which foam shows
uniform float refraction = 0.035;

uniform vec4 color_deep : source_color = vec4(0.03, 0.08, 0.08, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.22, 0.34, 0.27, 1.0);
uniform float beers_law = 1.7;
uniform float depth_offset = -0.1;

varying vec3 wave_normal;
varying vec2 world_xz;


vec4 wave(vec4 parameter, vec2 position, float time, inout vec3 tangent, inout vec3 binormal) {
	float wave_steepness = parameter.z;
	float wave_length = parameter.w;
	float k = 2.0 * 3.14159265359 / wave_length;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(parameter.xy);
	float f = k * (dot(d, position) - c * time);
	float a = wave_steepness / k;
	tangent += normalize(vec3(1.0 - d.x * d.x * (wave_steepness * sin(f)), d.x * (wave_steepness * cos(f)), -d.x * d.y * (wave_steepness * sin(f))));
	binormal += normalize(vec3(-d.x * d.y * (wave_steepness * sin(f)), d.y * (wave_steepness * cos(f)), 1.0 - d.y * d.y * (wave_steepness * sin(f))));
	return vec4(d.x * (a * cos(f)), a * sin(f) * 0.25, d.y * (a * cos(f)), 0.0);
}


void vertex() {
	float time = TIME * wave_speed;
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 tang = vec3(0.0);
	vec3 bin = vec3(0.0);
	vec4 v = vec4(0.0);
	v += wave(wave_a, world.xz, time, tang, bin);
	v += wave(wave_b, world.xz, time, tang, bin);
	v += wave(wave_c, world.xz, time, tang, bin);
	VERTEX += v.xyz;
	wave_normal = normalize(cross(bin, tang));
	world_xz = world.xz;
	NORMAL = wave_normal;
}


void fragment() {
	// --- normals: waves plus two drifting ripple layers -----------------------------------------
	vec2 uv = world_xz * normal_scale;
	vec3 n1 = texture(normalmap_a, uv + TIME * normal_drift).xyz * 2.0 - 1.0;
	vec3 n2 = texture(normalmap_a, uv * 1.9 - TIME * normal_drift * vec2(0.7, -0.9)).xyz * 2.0 - 1.0;
	vec3 ripple = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
	NORMAL_MAP = ripple * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;

	// --- water depth along the view ray from the depth buffer -------------------------------------
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float depth_diff = -view_pos.z + VERTEX.z;      // metres of water between the surface and what is below

	// --- refraction: bend the sampling point by the ripple normal, but never onto things above water
	vec2 ref_uv = SCREEN_UV + ripple.xy * refraction * clamp(depth_diff, 0.0, 1.0);
	float ref_depth_raw = texture(DEPTH_TEXTURE, ref_uv).r;
	vec4 ref_view = INV_PROJECTION_MATRIX * vec4(ref_uv * 2.0 - 1.0, ref_depth_raw, 1.0);
	ref_view.xyz /= ref_view.w;
	if (-ref_view.z + VERTEX.z < 0.0) {
		ref_uv = SCREEN_UV;
	}
	float depth_blend = exp((depth_diff + depth_offset) * -beers_law);
	depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
	float depth_blend_pow = clamp(pow(depth_blend, 2.5), 0.0, 1.0);
	vec3 screen_color = textureLod(SCREEN_TEXTURE, ref_uv, depth_blend_pow * 2.5).rgb;
	vec3 dye = mix(color_shallow.rgb, color_deep.rgb, depth_blend_pow);
	vec3 color = mix(screen_color * mix(vec3(1.0), dye, 0.8), dye, depth_blend_pow * 0.9);

	// --- shore foam where the water is shallow ---------------------------------------------------
	float foam_depth = 1.0 - min(1.0, max(depth_diff, 0.0) / max(foam_level, 0.01));
	float foam_noise = clamp(pow(texture(foam_sampler, uv * 3.0 - TIME * normal_drift * 2.0).r, 6.0) * 30.0, 0.0, 0.25);
	float foam_mix = clamp(pow(foam_depth + foam_noise, 6.0) * foam_noise * 0.6, 0.0, 1.0);
	color = mix(color, vec3(0.9, 0.93, 0.9), foam_mix);

	ALBEDO = color;
	METALLIC = 0.0;
	ROUGHNESS = 0.02;
	SPECULAR = 0.5;
}
