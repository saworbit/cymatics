shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 bolt_color : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float crackle : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	float across = abs(uv.y - 0.5) * 2.0;
	float jag = sin(uv.x * 40.0 + TIME * 48.0) * 0.12 * crackle;
	across = abs(across + jag);
	float core = exp(-across * 18.0);
	float glow = exp(-across * 5.0);
	float tick = 0.7 + 0.3 * sin(TIME * 60.0);
	vec3 col = mix(bolt_color.rgb, vec3(1.0), core);
	float alpha = clamp((core * 1.4 + glow * 0.55) * tick, 0.0, 1.0);
	if (alpha < 0.03) {
		discard;
	}
	COLOR = vec4(col * 1.6, alpha);
}
