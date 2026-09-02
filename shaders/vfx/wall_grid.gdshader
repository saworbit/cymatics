shader_type canvas_item;
render_mode blend_mix, unshaded;

// Top/bottom arena walls. Dark slab with a faint hex lattice and slow
// scanlines; `energy` lifts the lattice a touch when the rally is hot and
// `hit_x`/`hit` light a short section after a wall bounce.

uniform vec4 base_color : source_color = vec4(0.05, 0.02, 0.10, 0.92);
uniform vec4 line_color : source_color = vec4(0.55, 0.40, 0.95, 1.0);
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float hit : hint_range(0.0, 1.0) = 0.0;
uniform float hit_x : hint_range(0.0, 1.0) = 0.5;
uniform float cell_px = 22.0;
uniform vec2 rect_size = vec2(1920.0, 40.0);
uniform float flip_y : hint_range(0.0, 1.0) = 0.0;

// Hex grid edge distance (pointy-top), returns 0 at cell centre, 1 at edge.
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 hv = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	hv = abs(hv);
	return max(dot(hv, s * 0.5), hv.x) * 2.0;
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 uv = UV;
	if (flip_y > 0.5) {
		uv.y = 1.0 - uv.y;
	}
	float e = hex_edge(px / cell_px);
	float lattice = smoothstep(0.86, 0.98, e);

	// Scanline sweep that drifts along the wall.
	float sweep = fract(px.x / 900.0 - TIME * 0.05);
	float sweep_glow = exp(-pow((sweep - 0.5) * 6.0, 2.0)) * 0.35;
	float scan = 0.5 + 0.5 * sin(px.y * 1.4 + TIME * 0.8);

	// Fade the lattice toward the court-facing edge so it reads as a bevel.
	float inner = smoothstep(1.0, 0.35, uv.y);
	float rim = 1.0 - smoothstep(0.0, 0.12, uv.y);

	float hit_glow = 0.0;
	if (hit > 0.001) {
		float d = abs(UV.x - hit_x) * rect_size.x;
		hit_glow = exp(-d / 90.0) * hit;
	}

	float lat = lattice * (0.06 + energy * 0.08 + sweep_glow * 0.5) * inner;
	vec3 col = base_color.rgb;
	col += line_color.rgb * (lat + scan * 0.012 * inner);
	col += line_color.rgb * rim * (0.18 + energy * 0.35 + hit_glow * 1.2);
	col += vec3(1.0, 0.95, 1.0) * hit_glow * 0.9 * (rim + lattice * 0.6);
	float alpha = base_color.a + rim * 0.08 + hit_glow * 0.3;
	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
