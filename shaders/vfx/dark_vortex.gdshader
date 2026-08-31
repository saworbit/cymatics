shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float swirl_strength : hint_range(0.0, 10.0) = 3.5;
uniform float radius : hint_range(0.0, 1.0) = 0.5;
uniform float active_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vortex_tint : source_color = vec4(0.0, 0.9, 1.0, 0.4);

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);

    vec2 warped_uv = UV;
    if (dist < radius && active_factor > 0.001) {
        float percent = (radius - dist) / radius;
        float theta = percent * percent * swirl_strength * active_factor;
        float s = sin(theta);
        float c = cos(theta);
        vec2 rot_uv = vec2(dot(uv, vec2(c, -s)), dot(uv, vec2(s, c)));
        warped_uv = rot_uv + vec2(0.5);
    }

    vec3 scene = texture(screen_texture, SCREEN_UV + (warped_uv - UV) * 0.25).rgb;
    
    // Accretion disk edge glow
    float ring = smoothstep(0.15, 0.08, dist) * smoothstep(0.02, 0.08, dist) * active_factor;
    vec3 final_color = scene + vortex_tint.rgb * ring * 1.5;

    COLOR = vec4(final_color, active_factor * smoothstep(radius, 0.0, dist));
}
