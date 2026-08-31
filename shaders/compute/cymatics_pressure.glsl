#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rg32f) uniform readonly image2D pressure_read;
layout(set = 0, binding = 1, rg32f) uniform writeonly image2D pressure_write;
layout(set = 0, binding = 2, rg32f) uniform readonly image2D divergence;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(divergence);
    if (any(greaterThanEqual(coord, size))) return;

    // Neumann boundary conditions at borders
    float pl = (coord.x > 0) ? imageLoad(pressure_read, coord + ivec2(-1, 0)).x : imageLoad(pressure_read, coord).x;
    float pr = (coord.x < size.x - 1) ? imageLoad(pressure_read, coord + ivec2(1, 0)).x : imageLoad(pressure_read, coord).x;
    float pu = (coord.y > 0) ? imageLoad(pressure_read, coord + ivec2(0, -1)).x : imageLoad(pressure_read, coord).x;
    float pd = (coord.y < size.y - 1) ? imageLoad(pressure_read, coord + ivec2(0, 1)).x : imageLoad(pressure_read, coord).x;

    float div = imageLoad(divergence, coord).x;
    float p = (pl + pr + pu + pd - div) * 0.25;

    imageStore(pressure_write, coord, vec4(p, 0.0, 0.0, 0.0));
}
