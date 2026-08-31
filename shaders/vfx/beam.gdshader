shader_type canvas_item;

uniform vec4 beam_color : source_color = vec4(0.0, 0.95, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	float shaft = smoothstep(0.55, 0.0, abs(uv.y - 0.5));
	float falloff = pow(1.0 - uv.x, 1.4);
	float core = smoothstep(0.18, 0.0, abs(uv.y - 0.5));
	float glow = shaft * falloff * intensity;
	vec3 col = mix(beam_color.rgb, vec3(1.0), core * 0.65);
	float alpha = clamp(glow + core * falloff, 0.0, 1.0);
	if (alpha < 0.02) {
		discard;
	}
	COLOR = vec4(col, alpha);
}
