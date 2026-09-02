#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Splats touch only their own texel, so velocity and dye are read-write in
// place. That removes the per-splat ping-pong copy of the whole grid and lets
// the dispatch be bounded to the splat's radius.
layout(set = 0, binding = 0, rg32f) uniform image2D velocity;
layout(set = 0, binding = 1, rgba16f) uniform image2D dye;

layout(push_constant, std430) uniform SplatParams {
    vec2 point;
    vec2 force;
    vec4 color;      // rgb = dye colour, a = opacity weight (0..1)
    float radius;
    float strength;
    float mode;      // 0 = jet, 1 = vortex, 2 = sink
    float dye_gain;  // global multiplier on dye deposition
    ivec2 origin;    // texel offset of this bounded dispatch
    ivec2 pad;
} splat;

const float DYE_CAP = 1.6;

void main() {
    ivec2 coord = splat.origin + ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(velocity);
    if (any(greaterThanEqual(coord, size)) || any(lessThan(coord, ivec2(0)))) return;

    vec2 cell_pos = vec2(coord) + 0.5;
    vec2 splat_pos = splat.point * vec2(size);
    vec2 delta = cell_pos - splat_pos;

    float dist_sq = dot(delta, delta);
    float rad = max(splat.radius * float(size.x), 1.0);
    float rad_sq = rad * rad;
    float influence = exp(-dist_sq / rad_sq) * splat.strength;

    vec2 vel = imageLoad(velocity, coord).xy;
    float mode = splat.mode;
    if (mode < 0.5) {
        vel += splat.force * influence;
    } else if (mode < 1.5) {
        float len = length(delta);
        if (len > 0.35) {
            vec2 tang = vec2(-delta.y, delta.x) / len;
            vel += tang * splat.force.x * influence;
        }
    } else {
        float len = length(delta);
        if (len > 0.35) {
            vec2 inward = -delta / len;
            vel += inward * splat.force.x * influence;
        }
    }
    imageStore(velocity, coord, vec4(vel, 0.0, 0.0));

    // Dye deposition: alpha is an opacity weight, and a global gain keeps the
    // field from saturating when several emitters run every frame. The cap is
    // soft so bright cores compress instead of flat-topping to white.
    vec4 d = imageLoad(dye, coord);
    float deposit = influence * splat.color.a * splat.dye_gain;
    d.rgb += splat.color.rgb * deposit;
    d.rgb = d.rgb / (1.0 + max(d.rgb - DYE_CAP, vec3(0.0)) * 0.5);
    d.a = min(d.a + splat.color.a * influence, 1.0);
    imageStore(dye, coord, d);
}
