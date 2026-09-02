shader_type canvas_item;

uniform float bloom_intensity : hint_range(0.0, 3.0) = 1.25;
uniform float chromatic_aberration : hint_range(0.0, 5.0) = 1.8;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.44;
uniform float film_grain : hint_range(0.0, 0.1) = 0.03;
uniform vec3 background_color : source_color = vec3(0.02, 0.01, 0.045);
uniform float impact_pulse : hint_range(0.0, 1.5) = 0.0;
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float flow_energy : hint_range(0.0, 1.0) = 0.35;
uniform int palette_mode : hint_range(0, 4) = 0; // 0=Cyberpunk, 1=Solar, 2=Toxic, 3=Cosmos, 4=Prismatic

vec3 plasma_ramp(float t) {
	t = clamp(t, 0.0, 1.0);
	if (palette_mode == 1) {
		// Solar Flare
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
		// Toxic Venom
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
		// Deep Cosmos
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
		// Prismatic Rainbow
		float hue = fract(t * 1.2 + TIME * 0.15);
		vec3 rgb = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
		rgb = mix(vec3(0.04, 0.0, 0.1), rgb, smoothstep(0.0, 0.25, t));
		rgb = mix(rgb, vec3(1.0), smoothstep(0.85, 1.0, t));
		return rgb;
	}
	
	// Default: Cyberpunk
	vec3 deep = vec3(0.06, 0.0, 0.18);
	vec3 violet = vec3(0.42, 0.08, 0.72);
	vec3 cyan = vec3(0.08, 0.78, 1.0);
	vec3 magenta = vec3(1.0, 0.18, 0.62);
	vec3 gold = vec3(1.0, 0.78, 0.28);
	vec3 c = mix(deep, violet, smoothstep(0.0, 0.28, t));
	c = mix(c, mix(cyan, magenta, 0.35 + 0.25 * heat), smoothstep(0.22, 0.55, t));
	c = mix(c, gold, smoothstep(0.58, 0.88, t));
	c = mix(c, vec3(1.0, 0.96, 0.9), smoothstep(0.86, 1.0, t));
	return c;
}

void fragment() {
	vec2 uv = UV;
	vec2 texel = vec2(1.0 / 256.0, 1.0 / 144.0);
	vec4 dye0 = texture(TEXTURE, uv);
	float i0 = min(length(dye0.rgb), 2.2);

	float aberr = min(i0, 1.0) * chromatic_aberration * 0.0032 + impact_pulse * 0.004;
	float cr = texture(TEXTURE, uv + vec2(aberr, 0.0)).r;
	float cg = dye0.g;
	float cb = texture(TEXTURE, uv - vec2(aberr, 0.0)).b;
	vec3 split = vec3(cr, cg, cb);

	float dx = length(texture(TEXTURE, uv + vec2(texel.x, 0.0)).rgb) - length(texture(TEXTURE, uv - vec2(texel.x, 0.0)).rgb);
	float dy = length(texture(TEXTURE, uv + vec2(0.0, texel.y)).rgb) - length(texture(TEXTURE, uv - vec2(0.0, texel.y)).rgb);
	vec2 grad = vec2(dx, dy);
	float gsz = length(grad);
	vec2 flow = gsz > 1e-5 ? grad.yx * vec2(-1.0, 1.0) / gsz : vec2(0.0);

	float lic = 0.0;
	for (int k = -3; k <= 3; k++) {
		lic += length(texture(TEXTURE, uv + flow * (float(k) * 0.0032)).rgb);
	}
	lic /= 7.0;

	float filament = clamp(gsz * 6.0, 0.0, 1.0);
	float energy = pow(mix(i0, lic, 0.45) * 0.55, 0.72);
	energy = clamp(energy + filament * 0.12, 0.0, 1.0);

	vec3 plasma = plasma_ramp(energy);
	plasma += vec3(0.75, 0.9, 1.0) * filament * 0.22;
	plasma += split * bloom_intensity * smoothstep(0.35, 0.85, energy) * 0.35;

	vec3 nebula = background_color;
	nebula += vec3(0.10, 0.02, 0.18) * (0.04 + flow_energy * 0.03);

	float dye_mask = smoothstep(0.04, 0.42, max(dye0.a, energy));
	vec3 composite = mix(nebula, plasma, dye_mask);

	float vig = 1.0 - dot(uv - 0.5, uv - 0.5) * (vignette_strength * 2.1);
	composite *= clamp(vig, 0.0, 1.0);
	composite += vec3(1.0, 0.8, 0.4) * impact_pulse * 0.08 * vig;

	float n = fract(sin(dot(uv * TIME, vec2(12.9898, 78.233))) * 43758.5453);
	composite += (n - 0.5) * film_grain;
	composite = composite / (1.0 + composite * 0.35);
	composite = pow(max(composite, vec3(0.0)), vec3(0.92));
	COLOR = vec4(composite, 1.0);
}
