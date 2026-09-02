shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform float swirl_strength : hint_range(0.0, 10.0) = 3.5;
uniform float radius : hint_range(0.0, 1.0) = 0.5;
uniform float active_factor : hint_range(0.0, 1.0) = 0.0;
// Capture hold 0..1: the accretion disc tightens onto the orbit and brightens.
uniform float hold : hint_range(0.0, 1.0) = 0.0;
// Orbit radius in UV units (rect half-size = 0.5).
uniform float orbit_r : hint_range(0.0, 0.5) = 0.44;
uniform vec4 vortex_tint : source_color = vec4(0.0, 0.9, 1.0, 0.4);

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);
    float lens_r = mix(0.28, radius, hold);

    vec2 warped_uv = UV;
    if (dist < lens_r && active_factor > 0.001) {
        float percent = (lens_r - dist) / lens_r;
        float theta = percent * percent * swirl_strength * active_factor * (1.0 + hold * 1.5);
        float s = sin(theta);
        float c = cos(theta);
        vec2 rot_uv = vec2(dot(uv, vec2(c, -s)), dot(uv, vec2(s, c)));
        warped_uv = rot_uv + vec2(0.5);
    }

    vec2 aspect_correction = vec2(SCREEN_PIXEL_SIZE.x / max(SCREEN_PIXEL_SIZE.y, 0.0001), 1.0);
    vec2 offset = (warped_uv - UV) * 0.25 * aspect_correction;
    vec3 scene = texture(screen_texture, SCREEN_UV + offset).rgb;

    // Accretion disc: idle it is a soft ring at the nozzle; during a capture it
    // sits on the orbit radius and tightens/brightens with the hold.
    float idle_r = mix(0.10, 0.07, active_factor);
    float disk_r = mix(idle_r, orbit_r, hold);
    float width = mix(0.045, 0.02 + 0.02 * (1.0 - hold), hold);
    float ring = smoothstep(disk_r + width, disk_r, dist) * smoothstep(disk_r - width, disk_r, dist);
    ring *= active_factor * (1.0 + hold * 1.6);
    // Spokes: the disc streaks as it spins up.
    float ang = atan(uv.y, uv.x);
    float spokes = 0.5 + 0.5 * sin(ang * 6.0 + TIME * (4.0 + hold * 10.0));
    ring *= mix(1.0, 0.55 + 0.45 * spokes, hold);
    float core_dark = smoothstep(0.06 + hold * 0.03, 0.0, dist) * active_factor * 0.6;
    vec3 final_color = scene * (1.0 - core_dark) + vortex_tint.rgb * ring * (1.8 + hold * 1.4);
    final_color += vec3(1.0) * ring * hold * 0.5;

    // Only the warped core re-composites the screen; the rest of the rect is
    // the disc alone, so the lens never reads as a bright wash over the paddle.
    float core_r = mix(0.12, 0.09, hold);
    float alpha = active_factor * smoothstep(core_r, core_r * 0.35, dist) * 0.85;
    alpha = max(alpha, ring * 0.9);
    COLOR = vec4(final_color, clamp(alpha, 0.0, 1.0));
}
