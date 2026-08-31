shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float distortion_strength : hint_range(0.0, 0.15) = 0.045;
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec2 center = vec2(0.5);
    vec2 uv = UV - center;
    float dist = length(uv);

    // Annular shockwave profile
    float radius = progress * 0.48;
    float width = 0.05 * (1.0 - progress * 0.7);
    float mask = smoothstep(radius - width, radius, dist) - smoothstep(radius, radius + width, dist);
    mask = max(mask, 0.0);

    // Screen UV refraction displacement with chromatic shift
    vec2 dir = (dist > 0.0001) ? normalize(uv) : vec2(0.0);
    vec2 refract_offset = dir * mask * distortion_strength * (1.0 - progress);
    
    float r = texture(screen_texture, SCREEN_UV + refract_offset * 1.2).r;
    float g = texture(screen_texture, SCREEN_UV + refract_offset).g;
    float b = texture(screen_texture, SCREEN_UV + refract_offset * 0.8).b;
    vec3 scene_color = vec3(r, g, b);

    vec3 final_color = scene_color + ring_color.rgb * mask * (1.0 - progress) * 2.5;
    COLOR = vec4(final_color, mask * (1.0 - progress));
}
