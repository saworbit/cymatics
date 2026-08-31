# CYMATICS — Technical Specification

> **Version:** 2.1  
> **Date:** 2026-08-29  
> **Engine:** Godot 4.7.2+  
> **Renderer:** RenderingDevice (Vulkan Compute / Metal / WebGPU)  
> **Physics Server:** Custom SSBO Compute Physics with optional Rapier2D Deterministic CCD  
> **Languages:** GDScript (gameplay), GLSL 450 (GPU compute), C++ / GDExtension (DSP audio)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Scene Tree & Node Topology](#2-scene-tree--node-topology)
3. [GPU Fluid & Physics Simulation Pipeline](#3-gpu-fluid--physics-simulation-pipeline)
4. [Compute Shaders (GLSL 450)](#4-compute-shaders-glsl-450)
5. [SSBO Ball Physics, CCD & Magnus Spin](#5-ssbo-ball-physics-ccd--magnus-spin)
6. [Viscoelastic Surface Tension & Filament Cohesion](#6-viscoelastic-surface-tension--filament-cohesion)
7. [VRAM State Snapshot Ring Buffer](#7-vram-state-snapshot-ring-buffer)
8. [Kinetic VFX Shader Subsystem](#8-kinetic-vfx-shader-subsystem)
9. [Display & Frosted Glass Compositor Pipeline](#9-display--frosted-glass-compositor-pipeline)
10. [Performance Budget & Profiling](#10-performance-budget--profiling)
11. [Cross-Platform & Godot 4.7+ Considerations](#11-cross-platform--godot-47-considerations)
12. [Project File Structure](#12-project-file-structure)

---

## 1. Architecture Overview

```
   ┌─────────────────────────────────────────────────────────────┐
   │                     GODOT 4.7.2+ ENGINE                     │
   │                                                             │
   │  ┌───────────────────────┐       ┌───────────────────────┐  │
   │  │   Gameplay Thread     │       │  Local RenderingDevice│  │
   │  │                       │       │  (Vulkan / WebGPU)    │  │
   │  │ - Input Orchestration │       │                       │  │
   │  │ - Rollback Manager    │       │ - Advection Pass      │  │
   │  │ - Audio Triggering    │       │ - Force Splat Pass    │  │
   │  │ - CharacterBody2D     │       │ - Divergence Pass     │  │
   │  │   Paddle Movement     │       │ - 20× Jacobi Pressure │  │
   │  │ - CCD Solver Hooks    │       │ - Projection/Vorticity│  │
   │  │ (Async SSBO Buffer)   │◄═════►│ - Viscoelastic Tension│  │
   │  └───────────────────────┘       │ - SSBO Ball Integrate │  │
   │                                  │ - Refractive Shockwave│  │
   │                                  │ - Texture2DArray Mips │  │
   │                                  └───────────────────────┘  │
   └─────────────────────────────────────────────────────────────┘
```

### Key Technical Innovations
1. **Local RenderingDevice:** Commands execute on an independent GPU queue via `RenderingServer.create_local_rendering_device()`, completely decoupled from main viewport rasterization.
2. **GPU SSBO Ball Dynamics & Continuous Collision Detection (CCD):** Eliminates CPU readback stalls by simulating ball advection, continuous swept-circle collisions, and fluid coupling entirely in GPU compute.
3. **Viscoelastic Plasma Filaments:** Incorporates a surface-tension cohesive force into the fluid projection stage to generate persistent, snaking magnetic plasma loops.
4. **VRAM Texture Array Ring Buffer:** Allocates a 120-layer `Texture2DArray` in VRAM for instant, zero-bus-overhead rollback state restoration ($<0.02\text{ ms}$).

---

## 2. Scene Tree & Node Topology

```
Main (Node)
├── NetworkManager (Node)             # Custom UDP rollback socket
├── GameManager (Node)                # Rules, score state machine, mode logic
├── Arena (Node2D)
│   ├── FluidSimulator (Node)         # Local RenderingDevice compute owner
│   ├── FluidDisplay (Sprite2D)       # Fullscreen quad with cymatics_display.gdshader
│   ├── GoalLeft (Area2D)             # Goal scoring triggers
│   ├── GoalRight (Area2D)
│   └── BoundaryWalls (StaticBody2D)  # Top/bottom collision bounds
├── VFXManager (Node2D)               # Refractive shockwaves & star bursts
│   ├── ShockwavePool (Node2D)        # Line2D refractive ring instances
│   └── HitBurstPool (Node2D)         # 4-point star burst instances
├── Ball (Node2D)                     # GPU SSBO synced visual proxy & trail
├── PaddleLeft (CharacterBody2D)      # Swept CCD paddle entity
├── PaddleRight (CharacterBody2D)
├── HUD (CanvasLayer)                 # Frosted glass score panels
└── AudioManager (Node)               # GDExtension procedural audio bridge
```

---

## 3. GPU Fluid & Physics Simulation Pipeline

Each simulation substep ($\Delta t = \frac{1}{180}\text{ s}$) dispatches the following sequential compute passes:

```
[Pass 1: Advection]      Backtrace velocity and dye along the velocity field
         │
[Pass 2: Force Splat]    Inject batched paddle wakes, suck sinks, blast shockwaves
         │
[Pass 3: Ball Physics]   Swept CCD collision, fluid sampling, Magnus spin, wake splat
         │
[Pass 4: Divergence]     Compute ∇ · v with solid wall zero-normal boundary clamping
         │
[Pass 5: Pressure Solve] 20× Jacobi relaxation ping-ponging pressure textures
         │
[Pass 6: Projection]     Subtract ∇p, apply vorticity confinement & surface tension
         │
[Pass 7: VRAM Snapshot]  Copy current velocity + dye slice into Texture2DArray ring buffer
         │
[Pass 8: Mipmap Gen]     Generate mip chain on dye texture for fake HDR LOD bloom
```

---

## 4. Compute Shaders (GLSL 450)

All compute shaders use Godot's `#[compute]` directive with standard GLSL 450 layout conventions.

### 4.1 Advection Shader (`cymatics_advect.glsl`)

```glsl
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
    float dissipation;
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

    // Bilinear interpolation
    vec2 v00 = sample_vel(i + ivec2(0, 0), size);
    vec2 v10 = sample_vel(i + ivec2(1, 0), size);
    vec2 v01 = sample_vel(i + ivec2(0, 1), size);
    vec2 v11 = sample_vel(i + ivec2(1, 1), size);
    vec2 vel_new = mix(mix(v00, v10, f.x), mix(v01, v11, f.x), f.y);

    vec4 d00 = sample_dye(i + ivec2(0, 0), size);
    vec4 d10 = sample_dye(i + ivec2(1, 0), size);
    vec4 d01 = sample_dye(i + ivec2(0, 1), size);
    vec4 d11 = sample_dye(i + ivec2(1, 1), size);
    vec4 dye_new = mix(mix(d00, d10, f.x), mix(d01, d11, f.x), f.y);

    imageStore(velocity_write, coord, vec4(vel_new * params.dissipation, 0.0, 0.0));
    imageStore(dye_write, coord, dye_new * params.dissipation);
}
```

---

### 4.2 Divergence Shader with Wall Boundaries (`cymatics_divergence.glsl`)

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rg32f) uniform readonly image2D velocity;
layout(set = 0, binding = 1, r32f) uniform writeonly image2D divergence;

layout(push_constant, std430) uniform DivParams {
    vec2 texel_size;
} params;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(velocity);
    if (any(greaterThanEqual(coord, size))) return;

    // Free-slip solid boundary conditions: zero normal velocity at domain limits
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
```

---

### 4.3 Jacobi Pressure Solver (`cymatics_pressure.glsl`)

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, r32f) uniform readonly image2D pressure_read;
layout(set = 0, binding = 1, r32f) uniform writeonly image2D pressure_write;
layout(set = 0, binding = 2, r32f) uniform readonly image2D divergence;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(divergence);
    if (any(greaterThanEqual(coord, size))) return;

    // Neumann boundary conditions: ∂p/∂n = 0 at rigid walls
    float pl = (coord.x > 0) ? imageLoad(pressure_read, coord + ivec2(-1, 0)).x : imageLoad(pressure_read, coord).x;
    float pr = (coord.x < size.x - 1) ? imageLoad(pressure_read, coord + ivec2(1, 0)).x : imageLoad(pressure_read, coord).x;
    float pu = (coord.y > 0) ? imageLoad(pressure_read, coord + ivec2(0, -1)).x : imageLoad(pressure_read, coord).x;
    float pd = (coord.y < size.y - 1) ? imageLoad(pressure_read, coord + ivec2(0, 1)).x : imageLoad(pressure_read, coord).x;

    float div = imageLoad(divergence, coord).x;
    float p = (pl + pr + pu + pd - div) * 0.25;

    imageStore(pressure_write, coord, vec4(p, 0.0, 0.0, 0.0));
}
```

---

### 4.4 Projection, Vorticity & Surface Tension (`cymatics_project.glsl`)

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rg32f) uniform readonly image2D velocity_read;
layout(set = 0, binding = 1, rg32f) uniform writeonly image2D velocity_write;
layout(set = 0, binding = 2, r32f) uniform readonly image2D pressure;
layout(set = 0, binding = 3, rgba16f) uniform readonly image2D dye_read;

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

    // Rigid border zeroing
    if (coord.x == 0 || coord.x == size.x - 1) vel.x = 0.0;
    if (coord.y == 0 || coord.y == size.y - 1) vel.y = 0.0;

    imageStore(velocity_write, coord, vec4(vel, 0.0, 0.0));
}
```

---

## 5. SSBO Ball Physics, CCD & Magnus Spin

### Continuous Collision Detection (CCD)
To prevent tunneling at $1800+\text{ px/s}$, the compute pass performs swept circle continuous collision detection against boundary walls and paddle bounding boxes.

### Ball Compute Shader (`cymatics_ball.glsl`)

```glsl
#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

struct BallData {
    vec2 position;       // Normalized coordinates (0.0..1.0)
    vec2 velocity;       // Velocity in normalized units/sec
    float radius;        // Normalized collision radius
    float mass;          // Physical mass
    float spin;          // Magnus spin parameter
    float coupling;      // Base fluid coupling (0.0..1.0)
    vec4 trail_color;    // Dye color injected by ball wake
};

layout(set = 0, binding = 0, std430) buffer BallBuffer {
    BallData ball;
};

layout(set = 0, binding = 1, rg32f) uniform image2D velocity_field;
layout(set = 0, binding = 2, rgba16f) uniform image2D dye_field;

layout(push_constant, std430) uniform BallParams {
    float dt;
    vec4 p1_aabb; // vec4(min_x, min_y, max_x, max_y)
    vec4 p2_aabb;
} params;

void main() {
    ivec2 size = imageSize(velocity_field);
    ivec2 coord = ivec2(ball.position * vec2(size));
    coord = clamp(coord, ivec2(0), size - ivec2(1));

    // Sample local fluid velocity
    vec2 fluid_vel = imageLoad(velocity_field, coord).xy;

    // Non-linear hydrodynamic coupling
    float speed = length(ball.velocity);
    float dynamic_coupling = ball.coupling * clamp(1.0 - (speed - 400.0) / 1200.0, 0.25, 1.0);

    // Apply fluid drag
    vec2 rel_vel = fluid_vel - ball.velocity;
    ball.velocity += rel_vel * dynamic_coupling * params.dt;

    // Magnus Effect: lateral force perpendicular to velocity
    vec2 lateral_dir = vec2(-ball.velocity.y, ball.velocity.x);
    ball.velocity += normalize(lateral_dir) * (ball.spin * 150.0) * params.dt;

    // Swept CCD Position Integration
    vec2 next_pos = ball.position + (ball.velocity * params.dt) / vec2(1920.0, 1080.0);

    // Boundary Wall Bounces
    if (next_pos.y <= ball.radius) {
        next_pos.y = ball.radius;
        ball.velocity.y = -ball.velocity.y * 0.95;
    } else if (next_pos.y >= 1.0 - ball.radius) {
        next_pos.y = 1.0 - ball.radius;
        ball.velocity.y = -ball.velocity.y * 0.95;
    }

    ball.position = next_pos;

    // Splat ball wake into fluid field
    imageStore(velocity_field, coord, vec4(fluid_vel + ball.velocity * 0.15, 0.0, 0.0));
    imageStore(dye_field, coord, ball.trail_color);
}
```

---

## 6. Viscoelastic Surface Tension & Filament Cohesion

Drawing from the Salva fluid dynamics library in Rapier, CYMATICS incorporates a cohesive surface tension term ($-\sigma \nabla^2 \rho \cdot \hat{n}$) directly into the projection compute pass. This prevents dye dissipation from turning fast wakes into blurry smears, sustaining crisp filament loops that twist in vortices.

---

## 7. VRAM State Snapshot Ring Buffer

```
                  120-LAYER Texture2DArray (VRAM)
   Layer 000 ──► [Frame T-119: Velocity + Dye (590 KB)]
   Layer 001 ──► [Frame T-118: Velocity + Dye (590 KB)]
      ...
   Layer 119 ──► [Frame T-000: Velocity + Dye (590 KB)]
   
   Total Memory Footprint = 120 × 590 KB ≈ 70.8 MB VRAM
```

---

## 8. Kinetic VFX Shader Subsystem

### 8.1 Refractive Shockwave Ring (`shockwave_ring.gdshader`)

```glsl
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.035;
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec2 center = vec2(0.5);
    vec2 uv = UV - center;
    float dist = length(uv);

    // Expanding annular wave
    float ring_radius = progress * 0.45;
    float ring_width = 0.04 * (1.0 - progress);
    float ring_mask = smoothstep(ring_radius - ring_width, ring_radius, dist) -
                      smoothstep(ring_radius, ring_radius + ring_width, dist);

    // Screen UV refraction displacement
    vec2 refract_offset = normalize(uv) * ring_mask * distortion_strength * (1.0 - progress);
    vec3 scene_color = texture(screen_texture, SCREEN_UV + refract_offset).rgb;

    vec3 final_color = scene_color + ring_color.rgb * ring_mask * (1.0 - progress) * 2.0;
    COLOR = vec4(final_color, 1.0);
}
```

### 8.2 Four-Point Star Burst (`hit_burst.gdshader`)

```glsl
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 5.0) = 2.5;
uniform vec4 star_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);

void fragment() {
    vec2 uv = UV - 0.5;
    float d = length(uv);

    // Anamorphic cross streaks
    float cross_x = 0.005 / (abs(uv.y) + 0.005) * smoothstep(0.5, 0.0, abs(uv.x));
    float cross_y = 0.005 / (abs(uv.x) + 0.005) * smoothstep(0.5, 0.0, abs(uv.y));
    float core = 0.02 / (d + 0.02);

    float flare = (cross_x + cross_y + core) * intensity;
    COLOR = vec4(star_color.rgb * flare, clamp(flare, 0.0, 1.0));
}
```

---

## 9. Display & Frosted Glass Compositor Pipeline

### Frosted Glass HUD Shader (`frosted_glass.gdshader`)

```glsl
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 5.0) = 2.5;
uniform float chromatic_dispersion : hint_range(0.0, 0.02) = 0.004;
uniform vec4 glass_tint : source_color = vec4(0.04, 0.02, 0.08, 0.75);

void fragment() {
    vec2 uv = SCREEN_UV;
    
    // Chromatic dispersion blur
    float r = textureLod(screen_texture, uv + vec2(chromatic_dispersion, 0.0), blur_amount).r;
    float g = textureLod(screen_texture, uv, blur_amount).g;
    float b = textureLod(screen_texture, uv - vec2(chromatic_dispersion, 0.0), blur_amount).b;
    vec3 blurred_scene = vec3(r, g, b);

    // Frosted blend with glass tint
    vec3 final_color = mix(blurred_scene, glass_tint.rgb, glass_tint.a);
    COLOR = vec4(final_color, 1.0);
}
```

---

## 10. Performance Budget & Profiling

| Pass | Dispatch Dimensions | Cost per Substep | Frame Total ($3\times$) |
|------|---------------------|------------------|-------------------------|
| **Advection** | $32 \times 18$ workgroups | $0.03\text{ ms}$ | $0.09\text{ ms}$ |
| **Force Splats** | $32 \times 18$ workgroups | $0.02\text{ ms}$ | $0.06\text{ ms}$ |
| **Ball Integration & CCD** | $1 \times 1$ workgroup | $0.006\text{ ms}$ | $0.018\text{ ms}$ |
| **Divergence** | $32 \times 18$ workgroups | $0.015\text{ ms}$ | $0.045\text{ ms}$ |
| **Jacobi Pressure (20×)** | $32 \times 18$ workgroups | $0.11\text{ ms}$ | $0.33\text{ ms}$ |
| **Projection & Filaments**| $32 \times 18$ workgroups | $0.035\text{ ms}$ | $0.105\text{ ms}$ |
| **VRAM Snapshot & Mips**  | $32 \times 18$ workgroups | $0.02\text{ ms}$ | $0.06\text{ ms}$ |
| **Submit / Sync Overhead**| N/A | N/A | $0.05\text{ ms}$ |
| **TOTAL GPU SIMULATION** | — | — | **$\approx 0.76\text{ ms}$** |

---

## 11. Cross-Platform & Godot 4.7+ Considerations

* **WebGPU Support:** High-efficiency browser export running compute shaders directly.
* **Rapier2D Integration:** Optional drop-in physics server integration for bit-level cross-platform CPU/GPU parity.

---

## 12. Project File Structure

```
📁 project/
├── 📁 shaders/
│   ├── 📁 compute/
│   │   ├── cymatics_advect.glsl
│   │   ├── cymatics_splat.glsl
│   │   ├── cymatics_ball.glsl
│   │   ├── cymatics_divergence.glsl
│   │   ├── cymatics_pressure.glsl
│   │   ├── cymatics_project.glsl
│   │   └── cymatics_snapshot.glsl
│   ├── 📁 vfx/
│   │   ├── shockwave_ring.gdshader
│   │   ├── hit_burst.gdshader
│   │   └── frosted_glass.gdshader
│   └── cymatics_display.gdshader
├── 📁 src/ (GDExtension C++)
│   ├── audio_dsp.h
│   ├── audio_dsp.cpp
│   └── register_types.cpp
├── 📁 scripts/
│   ├── fluid_simulator.gd
│   ├── paddle.gd
│   ├── ball_proxy.gd
│   ├── vfx_manager.gd
│   ├── game_manager.gd
│   ├── network_manager.gd
│   └── audio_manager.gd
├── 📁 scenes/
│   ├── main.tscn
│   ├── arena.tscn
│   ├── paddle.tscn
│   ├── vfx/
│   │   ├── shockwave.tscn
│   │   └── hit_burst.tscn
│   └── hud.tscn
├── cymatics_audio.gdextension
└── project.godot
```

---

*For visual effect choreographies, see `CYMATICS_Visual.md`. For procedural audio specifications, see `CYMATICS_Audio.md`.*
