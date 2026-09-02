shader_type canvas_item;
render_mode blend_add, unshaded;

// Overlay for a momentum ProgressBar: a bright comet head at the fill edge
// with a glowing tail that trails behind it, plus a sweeping shimmer while
// the bar is at READY. `dir` = 1 fills left-to-right, -1 right-to-left.

uniform vec4 team_color : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float trail : hint_range(0.0, 1.0) = 0.0;   // lagging fill; tail spans trail..fill
uniform float head : hint_range(0.0, 2.0) = 0.0;    // head flare, spikes on gain
uniform float ready : hint_range(0.0, 1.0) = 0.0;
uniform float dir = 1.0;
uniform float aspect = 13.6;                        // width / height of the bar

void fragment() {
	float x = dir > 0.0 ? UV.x : 1.0 - UV.x;
	float y = (UV.y - 0.5) * 2.0;
	float vmask = 1.0 - smoothstep(0.55, 1.0, abs(y));

	// Comet head at the fill edge.
	float dx = (x - fill) * aspect;
	float core = exp(-dx * dx * 22.0) * exp(-y * y * 3.5);
	float flare = exp(-dx * dx * 4.0) * exp(-y * y * 1.5) * head;

	// Tail: bright just behind the head, fading toward the trailing edge.
	float behind = fill - x;
	float span = max(fill - trail, 0.02);
	float tail = 0.0;
	if (behind > 0.0) {
		tail = exp(-behind / (span * 0.6 + 0.02)) * smoothstep(0.0, 0.01, fill - x);
	}
	tail *= exp(-y * y * 2.0);

	// READY shimmer: a diagonal band sweeping across, plus a soft breathing lift.
	float sweep = fract(TIME * 0.55);
	float band = exp(-pow(((x - y * 0.06) - sweep) * 9.0, 2.0));
	float breathe = 0.5 + 0.5 * sin(TIME * 5.0);
	float shimmer = (band * 0.9 + breathe * 0.12) * ready * step(x, max(fill, 0.98)) * vmask;

	float a = core * (0.55 + head * 0.6) + flare * 0.5 + tail * 0.35 + shimmer;
	a *= step(0.005, fill);
	vec3 col = team_color.rgb * a + vec3(1.0) * (core * 0.45 + flare * 0.25 + band * ready * 0.3);
	if (a < 0.003) {
		discard;
	}
	COLOR = vec4(col, clamp(a, 0.0, 1.0));
}
