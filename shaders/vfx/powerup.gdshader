shader_type canvas_item;
render_mode blend_add, unshaded;

// Powerup orb: spinning gem halo with an SDF glyph per kind so pickups read
// without a text label. `kind` follows Powerup.Kind; -1 draws the generic gem.

uniform vec4 core_color : source_color = vec4(1.0, 0.9, 0.3, 1.0);
uniform vec4 glow_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform int kind = -1;

float sd_circle(vec2 p, float r) {
	return length(p) - r;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float sd_tri(vec2 p, float r) {
	const float k = sqrt(3.0);
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
}

float sd_arc(vec2 p, float r, float open_angle, float rot) {
	float c = cos(rot);
	float s = sin(rot);
	p = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
	float a = atan(p.y, p.x);
	float ring = abs(length(p) - r);
	// Gap centred on +x of width open_angle.
	float gap = smoothstep(open_angle * 0.5, open_angle * 0.5 + 0.2, abs(a));
	return mix(1.0, ring, gap);
}

// Returns (fill distance, stroke distance). Negative = inside.
vec2 glyph(vec2 p, int k) {
	float fill = 1.0;
	float stroke = 1.0;
	if (k == 0) {
		// MULTIBALL: three orbs
		float d = min(sd_circle(p - vec2(0.0, -0.11), 0.07), min(sd_circle(p - vec2(-0.11, 0.08), 0.07), sd_circle(p - vec2(0.11, 0.08), 0.07)));
		fill = d;
	} else if (k == 1) {
		// GROW: ring with plus
		stroke = abs(sd_circle(p, 0.19));
		fill = min(sd_box(p, vec2(0.10, 0.025)), sd_box(p, vec2(0.025, 0.10)));
	} else if (k == 2) {
		// TINY: small ring with minus
		stroke = abs(sd_circle(p, 0.13));
		fill = sd_box(p, vec2(0.07, 0.022));
	} else if (k == 3) {
		// STUN: lightning bolt
		float d = sd_segment(p, vec2(0.06, -0.2), vec2(-0.07, 0.02));
		d = min(d, sd_segment(p, vec2(-0.07, 0.02), vec2(0.05, 0.0)));
		d = min(d, sd_segment(p, vec2(0.05, 0.0), vec2(-0.06, 0.2)));
		fill = d - 0.035;
	} else if (k == 4) {
		// MAGNET: horseshoe with pole tips
		stroke = sd_arc(p, 0.16, 1.9, 1.5707963);
		fill = min(sd_box(p - vec2(-0.13, 0.13), vec2(0.045, 0.05)), sd_box(p - vec2(0.13, 0.13), vec2(0.045, 0.05)));
	} else if (k == 5) {
		// FIREBALL: teardrop flame
		vec2 q = p;
		q.y += 0.04;
		float d = sd_circle(q, 0.13);
		float tip = sd_tri(vec2(q.x, -(q.y + 0.10)) * 1.0, 0.13);
		fill = min(d, tip);
	} else if (k == 6) {
		// HYPER: double chevron
		float d = sd_segment(p, vec2(-0.16, -0.14), vec2(-0.02, 0.0));
		d = min(d, sd_segment(p, vec2(-0.02, 0.0), vec2(-0.16, 0.14)));
		d = min(d, sd_segment(p, vec2(0.02, -0.14), vec2(0.16, 0.0)));
		d = min(d, sd_segment(p, vec2(0.16, 0.0), vec2(0.02, 0.14)));
		fill = d - 0.03;
	} else if (k == 7) {
		// BALL_TRI
		stroke = abs(sd_tri(p * vec2(1.0, -1.0), 0.19));
	} else if (k == 8) {
		// BALL_CUBE
		stroke = abs(sd_box(p, vec2(0.15)));
	} else if (k == 9) {
		// BALL_STAR: four-point star
		float a = atan(p.y, p.x);
		float r = 0.09 + 0.11 * pow(abs(cos(a * 2.0)), 0.6);
		fill = length(p) - r;
	} else if (k == 10) {
		// BALL_RUGBY: ellipse
		stroke = abs(length(p * vec2(0.75, 1.3)) - 0.17);
	} else if (k == 11) {
		// PADDLE_SCOOP: open arc facing right
		stroke = sd_arc(p, 0.17, 1.6, 0.0);
	} else if (k == 12) {
		// PADDLE_WEDGE: wedge pointing right
		vec2 q = vec2(-p.y, p.x);
		fill = sd_tri(q * vec2(1.0, -1.0), 0.17);
	} else if (k == 13) {
		// PADDLE_FORTRESS: crenellated shield
		float body = sd_box(p - vec2(0.0, 0.03), vec2(0.17, 0.13));
		float teeth = min(sd_box(p - vec2(-0.11, -0.13), vec2(0.035, 0.035)), min(sd_box(p - vec2(0.0, -0.13), vec2(0.035, 0.035)), sd_box(p - vec2(0.11, -0.13), vec2(0.035, 0.035))));
		fill = min(body, teeth);
	}
	return vec2(fill, stroke);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv);
	float ang = atan(uv.y, uv.x) + TIME * 2.2;
	float halo = exp(-d * 5.0);
	float spike = pow(abs(cos(ang * 2.0)), 16.0) * smoothstep(0.5, 0.05, d);

	vec3 col;
	float alpha;
	if (kind < 0) {
		float diamond = abs(uv.x) + abs(uv.y);
		float gem = smoothstep(0.42, 0.22, diamond);
		float core = smoothstep(0.16, 0.02, d);
		col = mix(glow_color.rgb, core_color.rgb, gem);
		col += vec3(1.0) * core * 1.4;
		col += glow_color.rgb * spike * 0.9;
		col += glow_color.rgb * halo * 0.5;
		alpha = max(gem, max(halo * 0.8, spike));
	} else {
		// Soft disc backdrop so the glyph reads over any plasma.
		float disc = smoothstep(0.30, 0.20, d);
		float ring = smoothstep(0.30, 0.27, d) * smoothstep(0.24, 0.27, d);
		vec2 g = glyph(uv, kind);
		float aa = 0.012;
		float fill = 1.0 - smoothstep(-aa, aa, g.x);
		float stroke = 1.0 - smoothstep(0.018, 0.018 + aa * 2.0, g.y);
		float glyph_mask = max(fill, stroke);
		col = glow_color.rgb * disc * 0.35;
		col += glow_color.rgb * ring * 1.2;
		col += mix(core_color.rgb, vec3(1.0), 0.55) * glyph_mask * 1.6;
		col += glow_color.rgb * spike * 0.6;
		col += glow_color.rgb * halo * 0.45;
		alpha = max(max(disc * 0.5, ring), max(glyph_mask, max(halo * 0.7, spike * 0.8)));
	}
	if (alpha < 0.03) {
		discard;
	}
	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
