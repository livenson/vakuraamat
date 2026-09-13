shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// The roof as the tile's orthophoto shows it (FootprintBuilding._photo_roof): the photograph
// projected straight down by world position, so a roof carries its own tiles, tin, moss and
// skylights instead of one colour. One material per tile; LOD2 faces, fitted roofs and flat roofs
// all take it, and the merged far cells (BuildingChunks) keep it, since the projection reads the
// world position, not the mesh's UVs.
uniform sampler2D photo : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 origin;             // the tile's north-west corner: world x and z
uniform float extent = 1024.0;   // the tile's size in metres

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = clamp((world_pos.xz - origin) / extent, vec2(0.0), vec2(1.0));
	// the photograph already carries the day's sunlight: a little darker, matte and hardly specular,
	// or a pitched roof turned to the sun is lit twice and reads white (Rīga's LOD2 roofs)
	// a steep face sees the photograph stretched down its slope (streaks, a neighbour's shadow as a dark
	// wedge on Rīga's LOD2 facets): it takes the photograph blurred to ~8 m instead, the roof's colour
	// without its detail; a flat or gentle face keeps the detail
	vec3 up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float flatness = smoothstep(0.55, 0.85, abs(up.y));
	vec3 detail = texture(photo, uv).rgb;
	vec3 broad = textureLod(photo, uv, 5.0).rgb;
	ALBEDO = mix(broad, detail, flatness) * 0.9;
	ROUGHNESS = 1.0;
	SPECULAR = 0.08;
}
