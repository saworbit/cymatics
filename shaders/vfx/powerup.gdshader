shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 core_color : source_color = vec4(1.0, 0.9, 0.3, 1.0);
uniform vec4 glow_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv);
	float ang = atan(uv.y, uv.x) + TIME * 2.2;
	float diamond = abs(uv.x) + abs(uv.y);
	float gem = smoothstep(0.42, 0.22, diamond);
	float core = smoothstep(0.16, 0.02, d);
	float halo = exp(-d * 5.0);
	float spike = pow(abs(cos(ang * 2.0)), 16.0) * smoothstep(0.5, 0.05, d);
	vec3 col = mix(glow_color.rgb, core_color.rgb, gem);
	col += vec3(1.0) * core * 1.4;
	col += glow_color.rgb * spike * 0.9;
	col += glow_color.rgb * halo * 0.5;
	float alpha = max(gem, max(halo * 0.8, spike));
	if (alpha < 0.03) {
		discard;
	}
	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
