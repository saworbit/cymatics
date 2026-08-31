shader_type canvas_item;

uniform float intensity : hint_range(0.0, 5.0) = 2.5;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 star_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);

void fragment() {
    vec2 uv = UV - 0.5;
    float d = length(uv);

    float fade = 1.0 - progress;

    // Anamorphic cross diffraction spikes
    float cross_x = (0.004 / (abs(uv.y) + 0.004)) * smoothstep(0.5, 0.0, abs(uv.x));
    float cross_y = (0.004 / (abs(uv.x) + 0.004)) * smoothstep(0.5, 0.0, abs(uv.y));
    float core = 0.015 / (d + 0.015);

    float flare = (cross_x + cross_y + core) * intensity * fade;
    COLOR = vec4(star_color.rgb * flare, clamp(flare, 0.0, 1.0));
}
