shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.18, 1.0);
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float lock : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 2.0) = 1.0;
uniform float fireball : hint_range(0.0, 1.0) = 0.0;
uniform int shape_type : hint_range(0, 4) = 0; // 0=Round, 1=Triangle, 2=Cube, 3=Star, 4=Rugby
uniform float shape_angle = 0.0;

float sd_equilateral_triangle(vec2 p, float r) {
	const float k = sqrt(3.0);
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	
	// Rotation transform for non-spherical morphs
	float sa = sin(shape_angle);
	float ca = cos(shape_angle);
	vec2 rot_p = vec2(uv.x * ca - uv.y * sa, uv.x * sa + uv.y * ca);

	float d = length(uv);
	float ang = atan(uv.y, uv.x);

	// Evaluate distance field by shape
	if (shape_type == 1) {
		// Triangle / Prism
		float sdf = sd_equilateral_triangle(rot_p * 2.2, 0.55);
		d = sdf + 0.32;
		ang = atan(rot_p.y, rot_p.x);
	} else if (shape_type == 2) {
		// Cube / Hypercube
		float sdf = sd_box(rot_p * 2.0, vec2(0.38, 0.38)) - 0.06;
		d = sdf + 0.32;
		ang = atan(rot_p.y, rot_p.x);
	} else if (shape_type == 3) {
		// Star / Shuriken
		float a = atan(rot_p.y, rot_p.x);
		float star_r = 0.26 + 0.12 * cos(a * 4.0);
		float sdf = length(rot_p) - star_r;
		d = sdf + 0.32;
		ang = a;
	} else if (shape_type == 4) {
		// Rugby / Viscoelastic Pill
		vec2 squish_p = vec2(rot_p.x * 1.45, rot_p.y * 0.85);
		d = length(squish_p);
		ang = atan(rot_p.y, rot_p.x);
	}

	// Void silhouette so the orb punches through plasma.
	float body = smoothstep(0.42, 0.28, d);
	float rim_dark = smoothstep(0.46, 0.34, d) * (1.0 - smoothstep(0.30, 0.22, d));
	float core = smoothstep(0.18, 0.04, d);
	float hot_mid = smoothstep(0.30, 0.10, d);
	float halo = exp(-d * 5.2) * (0.85 + heat * 0.7 + lock * 1.1 + fireball * 0.6);
	float ring = smoothstep(0.33, 0.26, d) * smoothstep(0.20, 0.27, d);

	float spark = pow(abs(cos(ang * (shape_type == 3 ? 4.0 : 2.0) + TIME * 6.0)), 18.0) * smoothstep(0.42, 0.08, d);
	spark += pow(abs(cos(ang * 2.0 + 1.57 - TIME * 4.0)), 22.0) * 0.55 * smoothstep(0.38, 0.10, d);

	vec3 hot = mix(glow_color.rgb, vec3(1.0, 0.28, 0.04), max(heat, fireball));
	vec3 col = mix(hot * 0.55, core_color.rgb, core);
	col = mix(col, hot, hot_mid * 0.35);
	col = mix(col, vec3(1.0), lock * 0.8);
	col += vec3(1.0, 0.95, 0.65) * ring * (0.8 + lock * 1.6) * pulse;
	col += hot * spark * (0.55 + heat * 0.8);
	col += vec3(0.35, 0.85, 1.0) * halo * lock * 0.6;
	col += vec3(1.0, 0.45, 0.05) * fireball * halo * 0.5;

	// Black halo ring for contrast against the field.
	col = mix(vec3(0.0), col, 1.0 - rim_dark * 0.92);

	float alpha = max(body, max(halo * 0.9, spark * 0.7));
	alpha *= smoothstep(0.50, 0.42, d);
	alpha = clamp(alpha * pulse, 0.0, 1.0);
	if (alpha < 0.04 || d > 0.55) {
		discard;
	}
	COLOR = vec4(col * (1.35 + heat * 0.8 + lock * 1.0 + fireball * 0.6), alpha);
}
