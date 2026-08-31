#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rg32f) uniform readonly image2D velocity_read;
layout(set = 0, binding = 1, rg32f) uniform writeonly image2D velocity_write;
layout(set = 0, binding = 2, rgba16f) uniform readonly image2D dye_read;
layout(set = 0, binding = 3, rgba16f) uniform writeonly image2D dye_write;

layout(push_constant, std430) uniform SplatParams {
    vec2 point;
    vec2 force;
    vec4 color;
    float radius;
    float strength;
    float mode; // 0 = jet, 1 = vortex, 2 = sink
    float pad;
} splat;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(velocity_read);
    if (any(greaterThanEqual(coord, size))) return;

    vec2 cell_pos = vec2(coord) + 0.5;
    vec2 splat_pos = splat.point * vec2(size);
    vec2 delta = cell_pos - splat_pos;

    float dist_sq = dot(delta, delta);
    float rad = max(splat.radius * float(size.x), 1.0);
    float rad_sq = rad * rad;
    float influence = exp(-dist_sq / rad_sq) * splat.strength;

    vec2 vel = imageLoad(velocity_read, coord).xy;
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
    imageStore(velocity_write, coord, vec4(vel, 0.0, 0.0));

    vec4 dye = imageLoad(dye_read, coord);
    dye += splat.color * influence;
    dye = min(dye, vec4(1.8, 1.8, 1.8, 1.0));
    imageStore(dye_write, coord, dye);
}
