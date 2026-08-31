shader_type canvas_item;

uniform float bloom_intensity : hint_range(0.0, 3.0) = 1.15;
uniform float chromatic_aberration : hint_range(0.0, 5.0) = 1.6;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.48;
uniform float film_grain : hint_range(0.0, 0.1) = 0.025;
uniform vec3 background_color : source_color = vec3(0.025, 0.012, 0.05);
uniform float impact_pulse : hint_range(0.0, 1.5) = 0.0;
uniform float heat : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 uv = UV;
    vec4 dye_sample = texture(TEXTURE, uv);
    vec3 dye_color = dye_sample.rgb;
    float intensity = length(dye_color);

    float aberration = intensity * chromatic_aberration * 0.0035 + impact_pulse * 0.004;
    float r = texture(TEXTURE, uv + vec2(aberration, 0.0)).r;
    float g = dye_sample.g;
    float b = texture(TEXTURE, uv - vec2(aberration, 0.0)).b;
    vec3 split_color = vec3(r, g, b) * (1.18 + heat * 0.4);

    // Filament streamline contour luminance
    vec2 duv = vec2(1.0 / 256.0, 1.0 / 144.0);
    float dx = length(texture(TEXTURE, uv + vec2(duv.x, 0.0)).rgb) - length(texture(TEXTURE, uv - vec2(duv.x, 0.0)).rgb);
    float dy = length(texture(TEXTURE, uv + vec2(0.0, duv.y)).rgb) - length(texture(TEXTURE, uv - vec2(0.0, duv.y)).rgb);
    float filament_edge = clamp(length(vec2(dx, dy)) * 4.5, 0.0, 1.0);

    float luma = dot(split_color, vec3(0.3, 0.5, 0.2));
    vec3 bloom = split_color * bloom_intensity * smoothstep(0.10, 0.50, luma);
    vec3 contour = vec3(0.9, 0.95, 1.0) * filament_edge * (0.35 + heat * 0.45);

    float dye_mask = clamp(max(dye_sample.a, intensity) * 1.45, 0.0, 1.0);
    vec3 void_col = background_color * (1.0 + heat * 0.35);
    vec3 composite = mix(void_col, split_color + bloom + contour, dye_mask);

    float vig = 1.0 - dot(uv - 0.5, uv - 0.5) * (vignette_strength * 2.15);
    composite *= clamp(vig, 0.0, 1.0);
    composite += vec3(1.0, 0.85, 0.55) * impact_pulse * 0.08 * vig;

    float noise = fract(sin(dot(uv * TIME, vec2(12.9898, 78.233))) * 43758.5453);
    composite += (noise - 0.5) * film_grain;

    composite = composite / (1.0 + composite * 0.55);
    composite = pow(max(composite, vec3(0.0)), vec3(0.92));

    COLOR = vec4(composite, 1.0);
}
