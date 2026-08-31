#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rg32f) uniform readonly image2D velocity_read;
layout(set = 0, binding = 1, rg32f) uniform writeonly image2D velocity_write;
layout(set = 0, binding = 2, rg32f) uniform readonly image2D pressure;
layout(set = 0, binding = 3, rgba16f) uniform readonly image2D dye_read;
layout(set = 0, binding = 4, rgba16f) uniform writeonly image2D dye_write;

layout(push_constant, std430) uniform ProjectParams {
    vec2 texel_size;
    float vorticity_strength;
    float surface_tension_strength;
    float dt;
} params;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(velocity_read);
    if (any(greaterThanEqual(coord, size))) return;

    ivec2 l = ivec2(max(coord.x - 1, 0), coord.y);
    ivec2 r = ivec2(min(coord.x + 1, size.x - 1), coord.y);
    ivec2 u = ivec2(coord.x, max(coord.y - 1, 0));
    ivec2 d = ivec2(coord.x, min(coord.y + 1, size.y - 1));

    float pL = imageLoad(pressure, l).x;
    float pR = imageLoad(pressure, r).x;
    float pU = imageLoad(pressure, u).x;
    float pD = imageLoad(pressure, d).x;

    vec2 vel = imageLoad(velocity_read, coord).xy;
    vel -= 0.5 * vec2(pR - pL, pD - pU);

    // 1. Vorticity Confinement
    float vL = imageLoad(velocity_read, l).y;
    float vR = imageLoad(velocity_read, r).y;
    float vU = imageLoad(velocity_read, u).x;
    float vD = imageLoad(velocity_read, d).x;
    float curl = 0.5 * ((vR - vL) - (vD - vU));

    ivec2 ll = ivec2(max(coord.x - 2, 0), coord.y);
    ivec2 rr = ivec2(min(coord.x + 2, size.x - 1), coord.y);
    ivec2 uu = ivec2(coord.x, max(coord.y - 2, 0));
    ivec2 dd = ivec2(coord.x, min(coord.y + 2, size.y - 1));

    float cL = abs(imageLoad(velocity_read, ll).y - imageLoad(velocity_read, l).y);
    float cR = abs(imageLoad(velocity_read, rr).y - imageLoad(velocity_read, r).y);
    float cU = abs(imageLoad(velocity_read, uu).x - imageLoad(velocity_read, u).x);
    float cD = abs(imageLoad(velocity_read, dd).x - imageLoad(velocity_read, d).x);

    vec2 eta = 0.5 * vec2(cR - cL, cD - cU);
    if (length(eta) > 1e-4) {
        eta = normalize(eta);
        vec2 force = vec2(eta.y, -eta.x) * curl * params.vorticity_strength;
        vel += force * params.dt;
    }

    // 2. Viscoelastic Surface Tension (Cohesive Filament Force)
    float dye_c = imageLoad(dye_read, coord).a;
    float dye_l = imageLoad(dye_read, l).a;
    float dye_r = imageLoad(dye_read, r).a;
    float dye_u = imageLoad(dye_read, u).a;
    float dye_d = imageLoad(dye_read, d).a;
    vec2 dye_grad = 0.5 * vec2(dye_r - dye_l, dye_d - dye_u);
    float dye_laplacian = (dye_l + dye_r + dye_u + dye_d - 4.0 * dye_c);

    if (length(dye_grad) > 1e-3) {
        vel += -params.surface_tension_strength * dye_laplacian * normalize(dye_grad) * params.dt;
    }

    // Rigid boundary zeroing
    if (coord.x == 0 || coord.x == size.x - 1) vel.x = 0.0;
    if (coord.y == 0 || coord.y == size.y - 1) vel.y = 0.0;

    imageStore(velocity_write, coord, vec4(vel, 0.0, 0.0));
    imageStore(dye_write, coord, imageLoad(dye_read, coord));
}
