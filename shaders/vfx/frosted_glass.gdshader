shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 5.0) = 2.2;
uniform float chromatic_dispersion : hint_range(0.0, 0.02) = 0.0035;
uniform vec4 glass_tint : source_color = vec4(0.05, 0.02, 0.10, 0.70);
uniform float corner_radius : hint_range(0.0, 0.5) = 0.05;

void fragment() {
    vec2 uv = SCREEN_UV;
    
    // Chromatic dispersion multi-sampling
    float r = textureLod(screen_texture, uv + vec2(chromatic_dispersion, 0.0), blur_amount).r;
    float g = textureLod(screen_texture, uv, blur_amount).g;
    float b = textureLod(screen_texture, uv - vec2(chromatic_dispersion, 0.0), blur_amount).b;
    vec3 blurred_scene = vec3(r, g, b);

    // Subtle edge highlight
    float edge_x = smoothstep(0.0, 0.02, UV.x) * smoothstep(1.0, 0.98, UV.x);
    float edge_y = smoothstep(0.0, 0.02, UV.y) * smoothstep(1.0, 0.98, UV.y);
    float edge = 1.0 - (edge_x * edge_y);

    // Composite with dark glass tint and edge specular
    vec3 final_color = mix(blurred_scene, glass_tint.rgb, glass_tint.a) + vec3(edge * 0.12);
    COLOR = vec4(final_color, 1.0);
}
