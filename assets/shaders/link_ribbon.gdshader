// A link drawn in the air: a band arcing from one plot to another, dashed and flowing away from the
// plot the player asked about, so a still picture still says which end is which. Unshaded and never
// written to depth - it is a mark on the world, not a thing standing in it.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform float speed = 0.35;         // dashes a second along the band
uniform float dash = 0.55;          // share of each metre that is lit
uniform float edge_fade = 0.25;     // how far in from the band's top and bottom the alpha falls off
uniform float end_fade = 0.08;      // and from its two ends, so a ribbon does not stop dead

// UV runs 0..1 from end to end whatever the span, so the fades sit in the same place on a 40 m
// tether and a 600 m ribbon; UV2.x counts twenty-metre lengths, so the dashes stay the same size on
// the ground however long the link is.
void fragment() {
	float run = fract(UV2.x - TIME * speed);
	float lit = smoothstep(0.0, 0.12, run) * (1.0 - smoothstep(dash, dash + 0.12, run));
	float across = 1.0 - smoothstep(1.0 - edge_fade, 1.0, abs(UV.y * 2.0 - 1.0));
	float ends = smoothstep(0.0, end_fade, UV.x) * (1.0 - smoothstep(1.0 - end_fade, 1.0, UV.x));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * across * ends * mix(0.08, 1.0, lit);
}
