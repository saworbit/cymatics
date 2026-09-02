shader_type canvas_item;
render_mode blend_mix, unshaded;

// Title label treatment. Slow chromatic shimmer sweeping along the text, a
// glow pulse that follows the fluid energy, and a hairline highlight.
// The Label's glyphs come from a font atlas, so the colour fringe is done
// by offsetting the atlas lookup a hair for R and B.

uniform float energy : hint_range(0.0, 1.0) = 0.3;      // fluid energy from MenuManager
uniform float shimmer : hint_range(0.0, 1.0) = 0.6;     // sweep strength
uniform float fringe : hint_range(0.0, 2.0) = 0.8;      // chromatic offset in atlas px
uniform float width_px = 1200.0;                        // label width for the sweep
uniform vec4 tint_a : source_color = vec4(1.0, 0.8, 0.0, 1.0);
uniform vec4 tint_b : source_color = vec4(1.0, 0.95, 0.6, 1.0);

varying float v_x;

void vertex() {
	v_x = clamp(VERTEX.x / max(width_px, 1.0), 0.0, 1.0);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * fringe;
	vec4 base = texture(TEXTURE, UV);
	float r = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	float b = texture(TEXTURE, UV - vec2(px.x, 0.0)).a;

	// Sweep position in 0..1 across the label, wraps every ~5 s.
	float sweep = fract(TIME * 0.18);
	float band = exp(-pow((v_x - sweep) * 7.0, 2.0));
	float pulse = 0.5 + 0.5 * sin(TIME * 2.4);
	float glow = 1.0 + energy * 0.55 * pulse + band * shimmer * 0.9;

	// Colour: theme gold drifting toward a warm white in the band.
	vec3 col = mix(tint_a.rgb, tint_b.rgb, band * shimmer + energy * 0.25 * pulse);
	col *= COLOR.rgb / max(tint_a.rgb, vec3(0.05)); // keep any modulate the label has
	col *= glow;

	// Chromatic fringe: R leads, B trails, only on the glyph edges.
	float a = base.a;
	vec3 fringe_col = vec3(r, a, b);
	col = mix(col * a, col * fringe_col, 0.35 + band * 0.4);
	float out_a = max(a, max(r, b) * 0.6) * COLOR.a;
	COLOR = vec4(col, out_a);
}
