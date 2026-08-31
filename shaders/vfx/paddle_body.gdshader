shader_type canvas_item;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform float ready_factor : hint_range(0.0, 1.0) = 0.0;
uniform float action_factor : hint_range(0.0, 1.0) = 0.0;
uniform float time_pulse : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	vec2 b = vec2(0.28, 0.72);
	vec2 q = abs(p) - b;
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);

	float body = smoothstep(0.08, -0.02, sdf);
	float rim = smoothstep(0.14, 0.02, sdf) * (1.0 - body);
	float glow = exp(-max(sdf, 0.0) * 9.0);

	float pulse = 0.55 + 0.45 * sin(time_pulse * 9.0);
	vec3 col = mix(glow_color.rgb, core_color.rgb, body);
	col += glow_color.rgb * rim * 1.3;
	col += glow_color.rgb * glow * (0.35 + action_factor * 0.7);
	col += vec3(1.0, 0.92, 0.45) * ready_factor * pulse * (0.45 + glow);

	float alpha = max(body, max(rim * 0.85, glow * 0.65));
	if (alpha < 0.03) {
		discard;
	}
	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
