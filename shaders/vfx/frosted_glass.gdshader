shader_type canvas_item;

// Frosted glass panel. Apply to a ColorRect (it needs real UVs) placed behind
// a panel's content. Blurs the back buffer with a rotated multi-tap kernel,
// tints it, and adds a rounded-rect mask with an inner light edge.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float blur_amount : hint_range(0.0, 5.0) = 2.2;
uniform float chromatic_dispersion : hint_range(0.0, 0.02) = 0.0025;
uniform vec4 glass_tint : source_color = vec4(0.05, 0.02, 0.10, 0.70);
uniform float corner_radius : hint_range(0.0, 0.5) = 0.05;
uniform float edge_light : hint_range(0.0, 1.0) = 0.35;
uniform float noise_amount : hint_range(0.0, 0.1) = 0.012;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 blur_sample(vec2 uv, float lod, vec2 radius_uv, vec2 frag) {
	// 12 taps on two rings + centre. Kernel rotated per-pixel to trade banding for grain.
	float rot = hash12(floor(frag)) * 6.2831853;
	vec3 acc = textureLod(screen_texture, uv, lod).rgb * 2.0;
	float wsum = 2.0;
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 1.0471976 + rot;
		vec2 d = vec2(cos(a), sin(a));
		acc += textureLod(screen_texture, uv + d * radius_uv, lod).rgb;
		acc += textureLod(screen_texture, uv + d * radius_uv * 2.0, lod).rgb * 0.6;
		wsum += 1.6;
	}
	return acc / wsum;
}

void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.x / max(SCREEN_PIXEL_SIZE.y, 0.0001), 1.0);
	vec2 radius_uv = vec2(0.006) * aspect * (0.4 + blur_amount * 0.35);
	vec2 disp = vec2(chromatic_dispersion, 0.0) * aspect;
	float lod = blur_amount * 0.7;

	vec3 base = blur_sample(SCREEN_UV, lod, radius_uv, FRAGCOORD.xy);
	float r = blur_sample(SCREEN_UV + disp, lod, radius_uv, FRAGCOORD.xy).r;
	float b = blur_sample(SCREEN_UV - disp, lod, radius_uv, FRAGCOORD.xy).b;
	vec3 blurred = vec3(r, base.g, b);

	// Rounded rectangle SDF in UV space.
	vec2 p = abs(UV - 0.5) - (vec2(0.5) - vec2(corner_radius));
	float dist = length(max(p, vec2(0.0))) - corner_radius;
	float aa = fwidth(dist) * 1.5;
	float alpha = 1.0 - smoothstep(-aa, aa, dist);

	// Inner light edge, brighter toward the top-left like a lit bevel.
	float edge = 1.0 - smoothstep(0.0, 0.03, -dist);
	float light_dir = 0.55 + 0.45 * dot(normalize(UV - 0.5 + vec2(1e-4)), vec2(-0.7, -0.7));
	vec3 col = mix(blurred, glass_tint.rgb, glass_tint.a);
	col += vec3(edge * edge_light * light_dir);
	col += (hash12(floor(FRAGCOORD.xy) + 17.0) - 0.5) * noise_amount;

	COLOR = vec4(col, alpha * max(glass_tint.a, 0.15) + edge * edge_light * 0.5 * alpha);
}
