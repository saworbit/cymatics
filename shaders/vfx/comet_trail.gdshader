shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 hot_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 cool_color : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform float heat : hint_range(0.0, 1.0) = 0.5;
uniform float streak : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Line2D UV: x along the ribbon, y across the width.
	float across = abs(UV.y - 0.5) * 2.0;
	float along = UV.x;
	float core = exp(-across * across * 14.0);
	float sheet = exp(-across * across * 4.5) * 0.55;
	float scroll = abs(sin((along * 18.0 + TIME * 14.0) * 3.14159));
	float filaments = pow(scroll, 3.0) * (1.0 - across) * streak;
	vec3 col = mix(cool_color.rgb, hot_color.rgb, core);
	col = mix(col, hot_color.rgb, filaments);
	col *= 1.2 + heat * 1.4;
	float head = 1.0 - along;
	float alpha = clamp(max(core, sheet) * (0.15 + head * head * 0.95), 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
