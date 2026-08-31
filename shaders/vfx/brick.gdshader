shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.9, 0.4, 1.0);
uniform float hp_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float hit_pulse : hint_range(0.0, 2.0) = 0.0;
uniform float time_offset = 0.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	vec2 b = vec2(0.85, 0.82);
	vec2 d = abs(p) - b;
	float sdf = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - 0.05;

	float body = smoothstep(0.05, -0.02, sdf);
	float rim = smoothstep(0.12, 0.01, sdf) * (1.0 - body);
	float glow = exp(-max(sdf, 0.0) * 8.0);

	// Internal cymatic lattice pattern
	float grid = abs(sin(p.x * 6.0 + time_offset)) * abs(cos(p.y * 6.0 - time_offset));
	float crack = 0.0;
	if (hp_ratio < 0.68) {
		crack += smoothstep(0.06, 0.0, abs(p.y - sin(p.x * 12.0) * 0.25));
	}
	if (hp_ratio < 0.35) {
		crack += smoothstep(0.06, 0.0, abs(p.x - cos(p.y * 14.0) * 0.25));
	}

	vec3 col = mix(base_color.rgb * 0.45, base_color.rgb, body);
	col += glow_color.rgb * rim * (1.2 + hit_pulse * 1.5);
	col += glow_color.rgb * grid * (0.35 * hp_ratio);
	col += vec3(1.0, 0.3, 0.2) * crack * 1.6;
	col += vec3(1.0, 1.0, 0.8) * hit_pulse * (0.6 + glow);

	float alpha = max(body * 0.88, max(rim, glow * 0.6));
	if (alpha < 0.03) {
		discard;
	}
	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
