shader_type canvas_item;

// Fluid display: maps the dye field to a plasma palette, adds flow-aligned
// filaments and velocity-aware chromatic split, and leaves HDR headroom so
// the 2D glow pass (WorldEnvironment in arena.tscn) can bloom hot regions.

uniform sampler2D velocity_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec2 sim_texel = vec2(0.00390625, 0.00694444);
uniform float bloom_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float chromatic_aberration : hint_range(0.0, 5.0) = 1.4;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.32;
uniform float film_grain : hint_range(0.0, 0.1) = 0.02;
uniform vec3 background_color : source_color = vec3(0.02, 0.01, 0.045);
uniform float impact_pulse : hint_range(0.0, 1.5) = 0.0;
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float flow_energy : hint_range(0.0, 1.0) = 0.35;
uniform float exposure : hint_range(0.2, 3.0) = 1.0;
uniform int palette_mode : hint_range(0, 4) = 0;
// Cavitation void around the ball: the field is suppressed near the hot body
// so the ball is always the brightest, warmest thing on screen.
uniform vec2 ball_uv = vec2(-1.0, -1.0);
uniform float void_radius_px = 90.0;
uniform float void_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 field_px = vec2(1920.0, 1080.0); // 0=Cyberpunk, 1=Solar, 2=Toxic, 3=Cosmos, 4=Prismatic

vec3 plasma_ramp(float t) {
	t = clamp(t, 0.0, 1.0);
	if (palette_mode == 1) {
		vec3 deep = vec3(0.08, 0.01, 0.02);
		vec3 crimson = vec3(0.75, 0.08, 0.04);
		vec3 orange = vec3(1.0, 0.45, 0.05);
		vec3 gold = vec3(1.0, 0.88, 0.25);
		vec3 c = mix(deep, crimson, smoothstep(0.0, 0.30, t));
		c = mix(c, orange, smoothstep(0.25, 0.60, t));
		c = mix(c, gold, smoothstep(0.55, 0.90, t));
		c = mix(c, vec3(1.0, 0.98, 0.9), smoothstep(0.88, 1.0, t));
		return c;
	} else if (palette_mode == 2) {
		vec3 deep = vec3(0.01, 0.06, 0.04);
		vec3 emerald = vec3(0.05, 0.65, 0.35);
		vec3 lime = vec3(0.45, 1.0, 0.15);
		vec3 yellow = vec3(0.95, 1.0, 0.28);
		vec3 c = mix(deep, emerald, smoothstep(0.0, 0.30, t));
		c = mix(c, lime, smoothstep(0.25, 0.60, t));
		c = mix(c, yellow, smoothstep(0.55, 0.90, t));
		c = mix(c, vec3(0.92, 1.0, 0.95), smoothstep(0.88, 1.0, t));
		return c;
	} else if (palette_mode == 3) {
		vec3 deep = vec3(0.02, 0.01, 0.08);
		vec3 indigo = vec3(0.18, 0.08, 0.65);
		vec3 violet = vec3(0.68, 0.15, 0.95);
		vec3 ice = vec3(0.35, 0.88, 1.0);
		vec3 c = mix(deep, indigo, smoothstep(0.0, 0.30, t));
		c = mix(c, violet, smoothstep(0.25, 0.60, t));
		c = mix(c, ice, smoothstep(0.55, 0.90, t));
		c = mix(c, vec3(0.95, 0.98, 1.0), smoothstep(0.88, 1.0, t));
		return c;
	} else if (palette_mode == 4) {
		float hue = fract(t * 1.2 + TIME * 0.15);
		vec3 rgb = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
		rgb = mix(vec3(0.04, 0.0, 0.1), rgb, smoothstep(0.0, 0.25, t));
		rgb = mix(rgb, vec3(1.0), smoothstep(0.85, 1.0, t));
		return rgb;
	}
	// Cyberpunk: void -> violet -> team hue -> gold -> white.
	vec3 deep = vec3(0.05, 0.0, 0.16);
	vec3 violet = vec3(0.36, 0.07, 0.68);
	vec3 cyan = vec3(0.06, 0.72, 1.0);
	vec3 magenta = vec3(1.0, 0.16, 0.62);
	vec3 hot = vec3(0.64, 0.44, 1.0);
	vec3 c = mix(deep, violet, smoothstep(0.0, 0.30, t));
	c = mix(c, mix(cyan, magenta, 0.35 + 0.25 * heat), smoothstep(0.24, 0.58, t));
	c = mix(c, hot, smoothstep(0.62, 0.95, t));
	return c;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV;
	vec2 texel = sim_texel;
	vec4 dye0 = texture(TEXTURE, uv);
	vec2 vel = texture(velocity_tex, uv).xy;
	float speed = length(vel);

	// Dye colour split: along the local flow direction when there is flow,
	// horizontal otherwise; stronger toward the edges of the field.
	float radial = length(uv - 0.5);
	vec2 split_dir = speed > 0.02 ? vel / speed : vec2(1.0, 0.0);
	float aberr = (0.0012 + min(length(dye0.rgb), 1.2) * 0.0016 + clamp(speed * 0.004, 0.0, 0.003)) * chromatic_aberration;
	aberr *= 0.45 + 0.55 * smoothstep(0.08, 0.55, radial);
	aberr += impact_pulse * 0.003;
	vec3 split;
	split.r = texture(TEXTURE, uv + split_dir * aberr).r;
	split.g = dye0.g;
	split.b = texture(TEXTURE, uv - split_dir * aberr).b;

	// Flow-aligned line integral convolution for filament structure.
	float dx = length(texture(TEXTURE, uv + vec2(texel.x, 0.0)).rgb) - length(texture(TEXTURE, uv - vec2(texel.x, 0.0)).rgb);
	float dy = length(texture(TEXTURE, uv + vec2(0.0, texel.y)).rgb) - length(texture(TEXTURE, uv - vec2(0.0, texel.y)).rgb);
	vec2 grad = vec2(dx, dy);
	float gsz = length(grad);
	vec2 flow = gsz > 1e-5 ? vec2(-grad.y, grad.x) / gsz : vec2(0.0);
	if (speed > 0.05) {
		flow = normalize(mix(flow, vel / speed, 0.5));
	}
	float lic = 0.0;
	for (int k = -3; k <= 3; k++) {
		lic += length(texture(TEXTURE, uv + flow * (float(k) * texel.x * 0.85)).rgb);
	}
	lic /= 7.0;

	float i0 = length(split);
	float filament = clamp(gsz * 5.0, 0.0, 1.0);
	// Energy curve: leaves the top ~20% of the ramp for genuine peaks.
	float energy = pow(mix(i0, lic, 0.4) * 0.42, 0.85);
	energy = clamp(energy + filament * 0.10, 0.0, 1.0);

	vec3 plasma = plasma_ramp(energy);
	// Subtle hue bias from the actual dye colour so team dyes stay readable.
	vec3 dye_hue = split / max(i0, 1e-3);
	plasma = mix(plasma, plasma * (0.35 + dye_hue * 1.25), 0.6 * smoothstep(0.06, 0.45, energy) * (1.0 - smoothstep(0.7, 0.95, energy)));
	plasma += vec3(0.7, 0.88, 1.0) * filament * 0.16 * smoothstep(0.1, 0.5, energy);

	// Schlieren-style shading from the velocity field: shear brightens slightly.
	float vx1 = texture(velocity_tex, uv + vec2(texel.x, 0.0)).y - texture(velocity_tex, uv - vec2(texel.x, 0.0)).y;
	float vy1 = texture(velocity_tex, uv + vec2(0.0, texel.y)).x - texture(velocity_tex, uv - vec2(0.0, texel.y)).x;
	float curl = abs(vx1 - vy1);
	plasma *= 0.92 + clamp(curl * 0.06, 0.0, 0.22);

	vec3 nebula = background_color;
	nebula += vec3(0.10, 0.02, 0.18) * (0.05 + flow_energy * 0.04);
	// Faint velocity shimmer keeps the empty field alive.
	nebula += vec3(0.16, 0.08, 0.30) * clamp(speed * 0.02, 0.0, 0.25);

	float dye_mask = smoothstep(0.02, 0.30, max(dye0.a * 0.8, energy));

	// Cavitation void: darken and desaturate plasma around the ball, with a
	// thin bright rim at the boundary so the hole reads as a physical edge.
	float void_d = length((uv - ball_uv) * field_px);
	float void_core = 1.0 - smoothstep(void_radius_px * 0.55, void_radius_px, void_d);
	float void_rim = smoothstep(void_radius_px * 0.8, void_radius_px, void_d) * (1.0 - smoothstep(void_radius_px, void_radius_px * 1.25, void_d));
	float vs = void_strength;
	float lum = dot(plasma, vec3(0.3, 0.5, 0.2));
	plasma = mix(plasma, vec3(lum) * 0.35, void_core * vs * 0.85);
	plasma += vec3(1.0, 0.92, 0.75) * void_rim * vs * 0.55 * smoothstep(0.05, 0.3, energy);
	dye_mask *= 1.0 - void_core * vs * 0.6;

	vec3 composite = mix(nebula, plasma, dye_mask);

	// HDR peak: hot regions push above 1.0 so the glow pass catches them.
	float peak = smoothstep(0.72, 1.0, energy);
	composite += plasma * peak * (0.3 + heat * 0.2) * bloom_intensity;

	float vig = 1.0 - dot(uv - 0.5, uv - 0.5) * (vignette_strength * 2.0);
	composite *= clamp(vig, 0.0, 1.0);
	composite += vec3(1.0, 0.8, 0.4) * impact_pulse * 0.10 * vig;

	composite *= exposure;
	// Gentle shoulder that preserves >1.0 values for bloom.
	composite = composite / (1.0 + composite * 0.24);

	float n = hash12(floor(FRAGCOORD.xy) + vec2(mod(TIME * 61.0, 512.0), mod(TIME * 37.0, 512.0)));
	composite += (n - 0.5) * film_grain;
	COLOR = vec4(max(composite, vec3(0.0)), 1.0);
}
