shader_type canvas_item;
render_mode blend_add, unshaded;

// Additive ghost orb left behind the ball. Fades and cools as `progress` runs 0 -> 1.
uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.4;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv) * 2.0;
	float fade = 1.0 - progress;
	fade = fade * fade;
	float core = exp(-d * d * 9.0);
	float halo = exp(-d * d * 2.6) * 0.5;
	float a = clamp((core + halo) * fade, 0.0, 1.0);
	if (a < 0.01) {
		discard;
	}
	vec3 col = mix(tint.rgb, vec3(1.0, 0.97, 0.85), core * 0.7 * fade);
	COLOR = vec4(col * (core + halo) * fade * intensity, a);
}
