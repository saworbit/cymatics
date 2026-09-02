shader_type canvas_item;
render_mode blend_add, unshaded;

// Goal energy membrane. One tall ColorRect per side. UV.x = 0 is the goal
// edge (the rect is mirrored for the right side with `flip`). Additive so it
// never darkens the plasma; values above 1.0 bloom through the 2D glow.

uniform vec4 team_color : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform float flip : hint_range(0.0, 1.0) = 0.0;
uniform float idle : hint_range(0.0, 1.0) = 0.25;      // resting brightness
uniform float threat : hint_range(0.0, 1.0) = 0.0;     // ball inbound pressure
uniform float ripple_y : hint_range(0.0, 1.0) = 0.5;   // predicted crossing (UV.y)
uniform float ripple : hint_range(0.0, 1.0) = 0.0;     // ripple strength
uniform float pulse : hint_range(0.0, 2.0) = 0.0;      // goal flash
uniform float fracture : hint_range(0.0, 1.0) = 0.0;   // crack lines after a goal
uniform float aspect = 0.12;                           // rect width / height

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return v;
}

// Cheap voronoi edge distance for the fracture web.
float crack(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash21(i + g), hash21(i + g + 7.3));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

void fragment() {
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	// Physical-ish coordinates so noise and rings are not stretched.
	vec2 p = vec2(uv.x * aspect, uv.y);

	float energy = clamp(idle + threat * 0.9 + pulse * 0.8, 0.0, 2.2);

	// Membrane body: bright at the goal edge, falling into the court. Threat
	// pushes the falloff further into the arena.
	float reach = 0.3 + threat * 0.5 + pulse * 0.4;
	float edge = exp(-uv.x / max(reach * 0.55, 0.02));
	float sheet = smoothstep(reach, 0.0, uv.x);
	// Crisp membrane edge on the goal line itself.
	float rim = 1.0 - smoothstep(0.0, 0.02, uv.x);

	// Vertical gradient: full at mid-court, soft toward the walls.
	float vgrad = 1.0 - pow(abs(uv.y - 0.5) * 2.0, 3.0);

	// Scrolling plasma noise, faster when threatened.
	float speed = 0.25 + threat * 0.9 + pulse * 1.2;
	float n1 = fbm(vec2(p.x * 6.0, p.y * 5.0 - TIME * speed));
	float n2 = fbm(vec2(p.x * 11.0 + 3.0, p.y * 9.0 + TIME * speed * 0.6));
	float plasma = 0.55 + 0.45 * (n1 * 0.7 + n2 * 0.3) * 1.6;

	// Fine vertical filaments near the edge.
	float filament = pow(0.5 + 0.5 * sin(uv.y * 120.0 + n1 * 12.0 - TIME * 3.0), 6.0) * edge * 0.5;

	// Ripple around the predicted crossing point.
	float ry = ripple_y;
	float dist = length(vec2(p.x, (uv.y - ry)));
	float ring_t = fract(TIME * 1.6);
	float ring = exp(-pow((dist - ring_t * 0.16) * 60.0, 2.0)) * (1.0 - ring_t);
	float hotspot = exp(-dist * 14.0);
	float ripple_v = (ring * 0.8 + hotspot * 1.4) * ripple;

	// Fracture web that flashes on a goal.
	float web = 0.0;
	if (fracture > 0.001) {
		float c = crack(vec2(p.x * 26.0, p.y * 20.0));
		web = (1.0 - smoothstep(0.0, 0.05, c)) * fracture * sheet;
	}

	float body = (edge * 1.1 + sheet * 0.45 * plasma + rim * 1.2) * vgrad * energy;
	float total = body + filament * energy + ripple_v * (0.6 + threat) + web * 2.5;

	vec3 col = team_color.rgb * total;
	// Whiten the core during a pulse so it reads as an impact, not a colour wash.
	col += vec3(1.0) * (pulse * 0.5 * edge + web * 1.2 + ripple_v * 0.25);

	float alpha = clamp(total * 0.85, 0.0, 1.0);
	if (alpha < 0.004) {
		discard;
	}
	COLOR = vec4(col, alpha);
}
