#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rg32f) uniform readonly image2D velocity;
layout(set = 0, binding = 1, r32f) uniform writeonly image2D divergence;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(velocity);
    if (any(greaterThanEqual(coord, size))) return;

    // Free-slip solid boundaries
    float vl = (coord.x > 0) ? imageLoad(velocity, coord + ivec2(-1, 0)).x : 0.0;
    float vr = (coord.x < size.x - 1) ? imageLoad(velocity, coord + ivec2(1, 0)).x : 0.0;
    float vu = (coord.y > 0) ? imageLoad(velocity, coord + ivec2(0, -1)).y : 0.0;
    float vd = (coord.y < size.y - 1) ? imageLoad(velocity, coord + ivec2(0, 1)).y : 0.0;

    if (coord.x == 0) vl = -imageLoad(velocity, coord).x;
    if (coord.x == size.x - 1) vr = -imageLoad(velocity, coord).x;
    if (coord.y == 0) vu = -imageLoad(velocity, coord).y;
    if (coord.y == size.y - 1) vd = -imageLoad(velocity, coord).y;

    float div = 0.5 * ((vr - vl) + (vd - vu));
    imageStore(divergence, coord, vec4(div, 0.0, 0.0, 0.0));
}
