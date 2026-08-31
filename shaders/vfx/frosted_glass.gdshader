shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 5.0) = 2.2;
uniform float chromatic_dispersion : hint_range(0.0, 0.02) = 0.0035;
uniform vec4 glass_tint : source_color = vec4(0.05, 0.02, 0.10, 0.70);
uniform float corner_radius : hint_range(0.0, 0.5) = 0.05;

void fragment() {
    vec2 uv = SCREEN_UV;
    
    // Chromatic dispersion multi-sampling
    vec2 aspect_correction = vec2(SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.0001), 1.0);
    float r = textureLod(screen_texture, uv + vec2(chromatic_dispersion, 0.0) * aspect_correction, blur_amount).r;
    float g = textureLod(screen_texture, uv, blur_amount).g;
    float b = textureLod(screen_texture, uv - vec2(chromatic_dispersion, 0.0) * aspect_correction, blur_amount).b;
    vec3 blurred_scene = vec3(r, g, b);

    // Rounded rectangle SDF
    vec2 p = abs(UV - 0.5) - (vec2(0.5) - vec2(corner_radius));
    float dist = length(max(p, vec2(0.0))) - corner_radius;
    float alpha = 1.0 - smoothstep(0.0, 0.015, dist);

    // Edge highlight
    float edge = smoothstep(0.0, -0.015, dist) * (1.0 - smoothstep(-0.04, -0.015, dist));

    // Composite with dark glass tint and edge specular
    vec3 final_color = mix(blurred_scene, glass_tint.rgb, glass_tint.a) + vec3(edge * 0.22);
    COLOR = vec4(final_color, alpha * glass_tint.a);
}
