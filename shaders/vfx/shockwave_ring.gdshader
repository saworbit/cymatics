shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
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

    // Screen UV refraction displacement with chromatic shift. The quad is
    // square in pixels, so x offsets shrink by the screen aspect to stay isotropic.
    vec2 dir = (dist > 0.0001) ? normalize(uv) : vec2(0.0);
    vec2 aspect_correction = vec2(SCREEN_PIXEL_SIZE.x / max(SCREEN_PIXEL_SIZE.y, 0.0001), 1.0);
    vec2 refract_offset = dir * mask * distortion_strength * (1.0 - progress) * aspect_correction * ring_color.a;

    float r = texture(screen_texture, SCREEN_UV + refract_offset * 1.2).r;
    float g = texture(screen_texture, SCREEN_UV + refract_offset).g;
    float b = texture(screen_texture, SCREEN_UV + refract_offset * 0.8).b;
    vec3 scene_color = vec3(r, g, b);

    float fade = (1.0 - progress);
    fade *= fade;
    // ring_color.a scales both the additive ring and its alpha so soft pulses stay soft.
    vec3 final_color = scene_color + ring_color.rgb * mask * fade * 2.5 * ring_color.a;
    COLOR = vec4(final_color, mask * fade * ring_color.a);
}
