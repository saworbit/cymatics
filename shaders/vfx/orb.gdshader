shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.18, 1.0);
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float lock : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 2.0) = 1.0;
uniform float fireball : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv);
	float ang = atan(uv.y, uv.x);

	// Void silhouette so the orb punches through plasma.
	float body = smoothstep(0.42, 0.28, d);
	float rim_dark = smoothstep(0.46, 0.34, d) * (1.0 - smoothstep(0.30, 0.22, d));
	float core = smoothstep(0.18, 0.04, d);
	float hot_mid = smoothstep(0.30, 0.10, d);
	float halo = exp(-d * 5.2) * (0.85 + heat * 0.7 + lock * 1.1 + fireball * 0.6);
	float ring = smoothstep(0.33, 0.26, d) * smoothstep(0.20, 0.27, d);

	float spark = pow(abs(cos(ang * 2.0 + TIME * 6.0)), 18.0) * smoothstep(0.42, 0.08, d);
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
	if (alpha < 0.04 || d > 0.5) {
		discard;
	}
	COLOR = vec4(col * (1.35 + heat * 0.8 + lock * 1.0 + fireball * 0.6), alpha);
}
