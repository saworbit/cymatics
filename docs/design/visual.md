# CYMATICS — Visual Design Specification

> **Version:** 2.1  
> **Date:** 2026-08-29  
> **Engine:** Godot 4.7.2+  
> **Renderer:** Forward+ / Mobile / WebGPU (Linear Internal Workflow, sRGB Display)  
> **Target Framerates:** 60 FPS minimum, 120 / 240 FPS high-refresh rate target  
> **Native Resolutions:** $1920 \times 1080$ (PC/Console), $1280 \times 720$ (Switch/Mobile), Dynamic Scaling (Web)

---

## Table of Contents

1. [Visual Identity & Aesthetic Philosophy](#1-visual-identity--aesthetic-philosophy)
2. [Scientific Color Space & Palettes](#2-scientific-color-space--palettes)
3. [The Fluid Display Pipeline](#3-the-fluid-display-pipeline)
4. [Kinetic VFX Shader Subsystem](#4-kinetic-vfx-shader-subsystem)
5. [Frosted Glass UI & Glassmorphism](#5-frosted-glass-ui--glassmorphism)
6. [Paddle, Ball & Hazard Visuals](#6-paddle-ball--hazard-visuals)
7. [Dynamic Camera Choreography](#7-dynamic-camera-choreography)
8. [Platform Presets (Godot 4.7+ WebGPU Target)](#8-platform-presets-godot-47-webgpu-target)
9. [Accessibility & Photosensitivity Standards](#9-accessibility--photosensitivity-standards)

---

## 1. Visual Identity & Aesthetic Philosophy

CYMATICS visualizes the physics of turbulent fluid dynamics and wave mechanics through a modern, high-fidelity lens. 

```
   ┌────────────────────────────────────────────────────────┐
   │                   VISUAL PILLARS                       │
   ├──────────────────┬──────────────────┬──────────────────┤
   │    Scientific    │     Hypnotic     │    Readable      │
   │ Microscopic view │ Living, organic  │ Clean streamlines│
   │ of active plasma │ eddy structures  │ & high contrast  │
   └──────────────────┴──────────────────┴──────────────────┘
```

### Visual Influences
* **Astronomical Accretion Disks:** Gravitational lensing and polar coordinate swirls.
* **Schlieren & Shadowgraph Imagery:** High-speed shockwave fronts and thermal refractive gradients.
* **Modern Kinetic VFX:** Anamorphic star flares, frosted glass refractions, and cohesive viscoelastic filaments.

---

## 2. Scientific Color Space & Palettes

| Role | Color Name | Hex Code | Linear RGB | Functional Purpose |
|------|------------|----------|------------|--------------------|
| **Deep Space** | Void Indigo | `#0a0514` | `(0.04, 0.02, 0.08)` | Background absorption barrier & UI panels |
| **Plasma Core**| Cosmic Violet | `#1a0b2e` | `(0.10, 0.04, 0.18)` | Neutral, unexcited fluid field |
| **Player 1**   | Electric Cyan | `#00e5ff` | `(0.00, 0.90, 1.00)` | High-luminance P1 dye, trail & UI primary |
| **P1 Glow**    | Superluminal Cyan | `#80f8ff` | `(0.50, 0.97, 1.00)` | P1 overdrive bloom core |
| **Player 2**   | Hot Magenta | `#ff00aa` | `(1.00, 0.00, 0.67)` | Mid-luminance P2 dye, trail & UI primary |
| **P2 Glow**    | Plasma Rose | `#ff80cc` | `(1.00, 0.50, 0.80)` | P2 overdrive bloom core |
| **Ball Core**  | Thermal White | `#ffffff` | `(1.00, 1.00, 1.00)` | Maximum kinetic energy emitter |
| **Ball Wake**  | Incandescent Amber | `#ffcc00` | `(1.00, 0.80, 0.00)` | Thermal ribbon filament trail |
| **Cavitation** | Shockwave White | `#ffffff` | `(1.00, 1.00, 1.00)` | Radial blast compression front |

---

## 3. The Fluid Display Pipeline

```
  [256×144 Compute Simulation Textures]
  (Velocity: RG32F | Dye: RGBA16F)
                │
                ▼ (Mipmap Chain Generation: RD.texture_generate_mipmaps)
  [Texture2DRD Viewport Binding]
                │
                ▼ (Linear Sampling + Bicubic Edge Filter)
  [cymatics_display.gdshader CanvasItem Quad]
  - Velocity-Driven Chromatic Aberration
  - Mipmap LOD Fake HDR Bloom (Mips 2.0 & 4.0)
  - Reinhard Tone Mapping & Gamma Correction (γ = 2.2)
                │
                ▼
  [1920×1080 Viewport Display]
```

### Display Shader (`cymatics_display.gdshader`)

```glsl
shader_type canvas_item;

uniform sampler2D dye_texture : filter_linear_mipmap;
uniform sampler2D velocity_texture : filter_linear;
uniform float bloom_intensity : hint_range(0.0, 3.0) = 1.25;
uniform float chromatic_aberration : hint_range(0.0, 5.0) = 2.2;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float film_grain : hint_range(0.0, 0.1) = 0.035;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 vel = texture(velocity_texture, uv).xy;
    float speed = length(vel);

    // 1. Hydrodynamic Chromatic Aberration
    float aberration = speed * chromatic_aberration * 0.0035;
    float r = texture(dye_texture, uv + vec2(aberration, 0.0)).r;
    float g = texture(dye_texture, uv).g;
    float b = texture(dye_texture, uv - vec2(aberration, 0.0)).b;
    vec3 color = vec3(r, g, b);

    // 2. Mip-Based Wide-Kernel HDR Bloom
    vec3 bloom_near = textureLod(dye_texture, uv, 2.0).rgb * 0.6;
    vec3 bloom_far  = textureLod(dye_texture, uv, 4.0).rgb * 0.4;
    vec3 bloom = (bloom_near + bloom_far) * bloom_intensity;
    color += bloom;

    // 3. Smooth Physical Vignette
    float vig = 1.0 - dot(uv - 0.5, uv - 0.5) * (vignette_strength * 2.0);
    color *= clamp(vig, 0.0, 1.0);

    // 4. Temporal Film Grain
    float noise = fract(sin(dot(uv * TIME, vec2(12.9898, 78.233))) * 43758.5453);
    color += (noise - 0.5) * film_grain;

    // 5. Reinhard Tone Mapping & Gamma Correction
    color = color / (1.0 + color);
    color = pow(color, vec3(1.0 / 2.2));

    COLOR = vec4(color, 1.0);
}
```

---

## 4. Kinetic VFX Shader Subsystem

### 4.1 Refractive Shockwave Ring (`shockwave_ring.gdshader`)
Used when Blasts are fired or when high-speed balls impact the arena perimeter.

```glsl
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.04;
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec2 center = vec2(0.5);
    vec2 uv = UV - center;
    float dist = length(uv);

    // Annular shockwave profile
    float radius = progress * 0.45;
    float width = 0.04 * (1.0 - progress);
    float mask = smoothstep(radius - width, radius, dist) - smoothstep(radius, radius + width, dist);

    // Screen UV refraction displacement
    vec2 refract_offset = normalize(uv) * mask * distortion_strength * (1.0 - progress);
    vec3 scene_color = texture(screen_texture, SCREEN_UV + refract_offset).rgb;

    vec3 final_color = scene_color + ring_color.rgb * mask * (1.0 - progress) * 2.0;
    COLOR = vec4(final_color, 1.0);
}
```

### 4.2 Four-Point Harmonic Star Burst (`hit_burst.gdshader`)
Flashed on perfect Parries and goal-scoring impacts.

```glsl
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 5.0) = 2.5;
uniform vec4 star_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);

void fragment() {
    vec2 uv = UV - 0.5;
    float d = length(uv);

    // Anamorphic cross diffraction spikes
    float cross_x = 0.005 / (abs(uv.y) + 0.005) * smoothstep(0.5, 0.0, abs(uv.x));
    float cross_y = 0.005 / (abs(uv.x) + 0.005) * smoothstep(0.5, 0.0, abs(uv.y));
    float core = 0.02 / (d + 0.02);

    float flare = (cross_x + cross_y + core) * intensity;
    COLOR = vec4(star_color.rgb * flare, clamp(flare, 0.0, 1.0));
}
```

### 4.3 Polar Coordinate Vortex (`dark_vortex.gdshader`)
Applied to the paddle centroid during **Suck** operations to create an astronomical gravitational lens.

```glsl
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float swirl_strength : hint_range(0.0, 10.0) = 4.0;
uniform float radius : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);

    if (dist < radius) {
        float percent = (radius - dist) / radius;
        float theta = percent * percent * swirl_strength;
        float s = sin(theta);
        float c = cos(theta);
        uv = vec2(dot(uv, vec2(c, -s)), dot(uv, vec2(s, c)));
    }

    vec2 final_uv = uv + vec2(0.5);
    vec3 scene = texture(screen_texture, SCREEN_UV + (final_uv - UV) * 0.2).rgb;
    COLOR = vec4(scene, 1.0);
}
```

---

## 5. Frosted Glass UI & Glassmorphism

### Physical Frosted Glass Shader (`frosted_glass.gdshader`)

```glsl
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 5.0) = 2.5;
uniform float chromatic_dispersion : hint_range(0.0, 0.02) = 0.004;
uniform vec4 glass_tint : source_color = vec4(0.04, 0.02, 0.08, 0.75);

void fragment() {
    vec2 uv = SCREEN_UV;
    
    // Chromatic dispersion multi-sampling
    float r = textureLod(screen_texture, uv + vec2(chromatic_dispersion, 0.0), blur_amount).r;
    float g = textureLod(screen_texture, uv, blur_amount).g;
    float b = textureLod(screen_texture, uv - vec2(chromatic_dispersion, 0.0), blur_amount).b;
    vec3 blurred_scene = vec3(r, g, b);

    // Composite with dark glass tint
    vec3 final_color = mix(blurred_scene, glass_tint.rgb, glass_tint.a);
    COLOR = vec4(final_color, 1.0);
}
```

---

## 6. Paddle, Ball & Hazard Visuals

### Viscoelastic Plasma Filaments (Ball Trail)
Fast shots ($>800\text{ px/s}$) generate cohesive viscoelastic filaments powered by surface-tension constraints in the compute shader, creating magnetic solar prominence loops that twist and billow in vortices.

---

## 7. Dynamic Camera Choreography

```gdscript
class_name CymaticsCamera
extends Camera2D

func apply_blast_kick(direction: Vector2, charge_pct: float) -> void:
    var kick_vector := direction * (12.0 * charge_pct)
    var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(self, "offset", kick_vector, 0.05)
    tween.tween_property(self, "offset", Vector2.ZERO, 0.20)

func update_rally_zoom(rally_hits: int) -> void:
    var target_zoom := 1.0 + (min(rally_hits, 15) * 0.006)
    zoom = lerp(zoom, Vector2(target_zoom, target_zoom), 0.03)

func trigger_goal_impact() -> void:
    var tween := create_tween()
    tween.tween_property(self, "zoom", Vector2(0.92, 0.92), 0.10)
    tween.tween_property(self, "zoom", Vector2(1.0, 1.0), 0.35)
```

---

## 8. Platform Presets (Godot 4.7+ WebGPU Target)

| Preset | Target Platform | Simulation Grid | Marker Particles | Bloom & VFX Quality |
|--------|-----------------|-----------------|------------------|---------------------|
| **Ultra** | PC (RTX / RX) | $512 \times 288$ | 4,096 | Full Refraction + Star Bursts |
| **High** | PC Standard / PS5 | $256 \times 144$ | 2,048 | Standard 2-Pass Refraction |
| **Medium** | Switch (Docked) / Steam Deck | $256 \times 144$ | 1,024 | Single Pass Refraction |
| **Low** | Switch (Handheld) / Mobile | $128 \times 72$ | 512 | Mipmap LOD bloom only |
| **Web Demo** | Browser (WebGPU) | $128 \times 72$ | 512 | Mipmap LOD bloom only |

---

## 9. Accessibility & Photosensitivity Standards

* **Epilepsy & Flash Protection:** Option to replace fullscreen white flashes with high-contrast colored geometric outlines; minimum rise time of $100\text{ ms}$.
* **Colorblind Modes:** Verified contrast ratios for Deuteranopia, Protanopia, Tritanopia, and Monochrome stripe overlays.
* **Motion Sickness Toggles:** Full lock option for camera kick and rally zooms.

---

*For technical shader compute specifications, see `CYMATICS_Technical_Spec.md`.*
