#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rg32f) uniform readonly image2D velocity_read;
layout(set = 0, binding = 1, rgba16f) uniform readonly image2D dye_read;
layout(set = 0, binding = 2, rg32f) uniform writeonly image2D velocity_write;
layout(set = 0, binding = 3, rgba16f) uniform writeonly image2D dye_write;

layout(push_constant, std430) uniform AdvectParams {
    vec2 texel_size;
    float dt;
    float dissipation;      // velocity decay per sub-step
    float dye_dissipation;  // dye decay per sub-step (multiplicative)
    float dye_floor;        // dye decay per sub-step (subtractive, clears haze)
    float pad0;
    float pad1;
} params;

vec2 sample_vel(ivec2 coord, ivec2 size) {
    coord = clamp(coord, ivec2(0), size - ivec2(1));
    return imageLoad(velocity_read, coord).xy;
}

vec4 sample_dye(ivec2 coord, ivec2 size) {
    coord = clamp(coord, ivec2(0), size - ivec2(1));
    return imageLoad(dye_read, coord);
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(velocity_read);
    if (any(greaterThanEqual(coord, size))) return;

    vec2 uv = (vec2(coord) + 0.5) * params.texel_size;
    vec2 vel = sample_vel(coord, size);

    // Semi-Lagrangian backtracing
    vec2 prev_uv = uv - vel * params.dt * params.texel_size;
    vec2 prev_coord = prev_uv / params.texel_size - 0.5;
    ivec2 i = ivec2(floor(prev_coord));
    vec2 f = fract(prev_coord);

    // Bilinear interpolation for velocity
    vec2 v00 = sample_vel(i + ivec2(0, 0), size);
    vec2 v10 = sample_vel(i + ivec2(1, 0), size);
    vec2 v01 = sample_vel(i + ivec2(0, 1), size);
    vec2 v11 = sample_vel(i + ivec2(1, 1), size);
    vec2 vel_new = mix(mix(v00, v10, f.x), mix(v01, v11, f.x), f.y);

    // Bilinear interpolation for dye
    vec4 d00 = sample_dye(i + ivec2(0, 0), size);
    vec4 d10 = sample_dye(i + ivec2(1, 0), size);
    vec4 d01 = sample_dye(i + ivec2(0, 1), size);
    vec4 d11 = sample_dye(i + ivec2(1, 1), size);
    vec4 dye_new = mix(mix(d00, d10, f.x), mix(d01, d11, f.x), f.y);

    dye_new = max(dye_new * params.dye_dissipation - vec4(params.dye_floor), vec4(0.0));

    imageStore(velocity_write, coord, vec4(vel_new * params.dissipation, 0.0, 0.0));
    imageStore(dye_write, coord, dye_new);
}
