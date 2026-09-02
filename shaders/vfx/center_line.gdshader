shader_type canvas_item;
render_mode blend_add, unshaded;

// Centre line as a dashed energy filament. `breath` is a 0..1 pulse driven by
// the serve beats; `energy` follows the rally length. Stays dim on purpose:
// it is a court marking, not a light source.

uniform vec4 line_color : source_color = vec4(0.55, 0.40, 0.95, 1.0);
uniform float breath : hint_range(0.0, 1.0) = 0.0;
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float dash_px = 26.0;
uniform vec2 rect_size = vec2(24.0, 984.0);

void fragment() {
	vec2 px = UV * rect_size;
	float cx = (UV.x - 0.5) * rect_size.x;
	// Dashes scroll outward from the centre dot when breathing.
	float dir = sign(px.y - rect_size.y * 0.5);
	float scroll = TIME * (8.0 + energy * 40.0) * dir;
	// Dash duty grows with breath so the line "fills in" on each beat.
	float duty = mix(0.55, 0.85, breath);
	float phase = fract((px.y + scroll) / dash_px);
	float dash = smoothstep(1.0 - duty - 0.06, 1.0 - duty + 0.06, phase);

	float core = exp(-cx * cx / (2.0 * 1.4 * 1.4));
	float glow = exp(-abs(cx) / (4.0 + breath * 6.0 + energy * 4.0)) * 0.5;
	// Softer near the walls so it does not collide with the wall rim.
	float vfade = smoothstep(0.0, 0.06, UV.y) * smoothstep(1.0, 0.94, UV.y);

	float a = (core * (0.55 + breath * 0.9) + glow * (0.35 + energy * 0.5)) * mix(0.35, 1.0, dash) * vfade;
	a *= 0.32 + energy * 0.25 + breath * 0.5;
	vec3 col = line_color.rgb * (1.0 + breath * 0.8);
	col += vec3(1.0) * breath * core * 0.35;
	if (a < 0.003) {
		discard;
	}
	COLOR = vec4(col * a, a);
}
