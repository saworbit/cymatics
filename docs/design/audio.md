# CYMATICS — Audio Design Specification

> **Version:** 2.0  
> **Date:** 2026-08-29  
> **Engine:** Godot 4.7.2+  
> **Philosophy:** The plasma itself sings.  
> **Architecture:** GDExtension C++ DSP Core + GDScript Orchestrator  
> **Sample Rate:** 48,000 Hz | **Block Size:** 512–1024 frames (~10.6–21.3 ms)

---

## Table of Contents

1. [Design Philosophy & Synesthesia](#1-design-philosophy--synesthesia)
2. [Why Native GDExtension for Procedural Audio?](#2-why-native-gdextension-for-procedural-audio)
3. [Audio Subsystem Architecture](#3-audio-subsystem-architecture)
4. [The Plasma Drone (Stochastic Fluid Energy)](#4-the-plasma-drone-stochastic-fluid-energy)
5. [Ball FM Synthesis (Speed & Vorticity Mapping)](#5-ball-fm-synthesis-speed--vorticity-mapping)
6. [Paddle Granular Dispersion](#6-paddle-granular-dispersion)
7. [Impact & Blast Synthesis](#7-impact--blast-synthesis)
8. [Dynamic Dye Score Chords](#8-dynamic-dye-score-chords)
9. [Rally Escalation Audio](#9-rally-escalation-audio)
10. [GDExtension C++ Implementation Reference](#10-gdextension-c-implementation-reference)
11. [Rollback Sync & Audio Buffer Management](#11-rollback-sync--audio-buffer-management)
12. [Mastering & Dynamic Sidechain Ducking](#12-mastering--dynamic-sidechain-ducking)

---

## 1. Design Philosophy & Synesthesia

In CYMATICS, sound is not composed as static layered background music tracks; it is an **emergent physical voice** of the hydrodynamic simulation.

* The pitch of the ball is its physical momentum.
* The timbre and dissonance of the ball are governed by the local fluid curl ($\nabla \times v$).
* The ambient drone is the integrated kinetic energy ($\frac{1}{2}\int \|v\|^2 \,dA$) of all 36,864 fluid cells.
* The wake of the paddle is a granular synthesis of liquid displacement.

A competitive player can play with their eyes closed and determine ball position, speed, spin, and field turbulence purely through acoustic localization and timbre shifts.

---

## 2. Why Native GDExtension for Procedural Audio?

### The GDScript Per-Sample Bottleneck
Godot's `AudioStreamGeneratorPlayback.push_frame()` allows pushing audio samples one frame at a time. However:
- Running 5 simultaneous procedural synthesizers (Drone, Ball FM, 64-grain Paddle, Impacts, Score Chords) requires generating **$48,000 \times 5 = 240,000+$ sample iterations per second**.
- Executing this inside interpreted GDScript `_process()` leads to CPU spikes, frame drops, and catastrophic audio crackling (buffer underruns).

### The Godot 4.7.2+ Architecture
1. **C++ GDExtension DSP Core (`CymaticsAudioDSP`):**
   - High-throughput, vectorized (SIMD) sample generation running on the dedicated Godot audio thread.
   - Zero allocations during active playback.
   - Block-based processing filling buffers in chunks of 512 samples ($10.6\text{ ms}$).
2. **GDScript Control Layer (`AudioManager`):**
   - Passes high-level simulation parameters (average kinetic energy, ball speed, curl, paddle velocity) to the GDExtension node once per physics frame ($60\text{ Hz}$).

---

## 3. Audio Subsystem Architecture

```
   ┌────────────────────────────────────────────────────────────┐
   │                 AudioManager (GDScript)                    │
   │   Collects Fluid/Ball metrics at 60 Hz physics tick        │
   └─────────────────────────────┬──────────────────────────────┘
                                 │ Set Parameters (Atomic Floats)
   ┌─────────────────────────────▼──────────────────────────────┐
   │           CymaticsAudioDSP (GDExtension C++ Node)          │
   │               Runs on Godot Audio Thread                   │
   ├──────────────────┬──────────────────┬──────────────────────┤
   │   PlasmaDrone    │     BallTone     │    PaddleGranular    │
   │  Biquad Bandpass │  2-Op FM Synth   │   64-Grain Resonator │
   │   Brown Noise    │  (Pitch + Curl)  │   (Droplet Textures) │
   ├──────────────────┴──────────────────┴──────────────────────┤
   │   ImpactSynth (Subtractive Kick) / ScoreChord (Additive)   │
   └─────────────────────────────┬──────────────────────────────┘
                                 │ 48 kHz Stereo Stream
   ┌─────────────────────────────▼──────────────────────────────┐
   │                   Godot Audio Bus System                   │
   │   Master ──► Gameplay (Ducked) + Impacts (Sidechain Trig)  │
   └────────────────────────────────────────────────────────────┘
```

---

## 4. The Plasma Drone (Stochastic Fluid Energy)

### Concept & Math
A continuous ambient bed representing total hydrodynamic kinetic energy.
- **Source:** Generated brown noise ($1/f^2$ power falloff).
- **Filter:** Resonant 2-pole Biquad bandpass filter.
- **Modulation:**
  - Cutoff Frequency: $f_c = \text{lerp}(80\text{ Hz}, 2000\text{ Hz}, \text{clamp}(E_{\text{kinetic}} / 5000, 0, 1))$
  - Resonance ($Q$): $Q = \text{lerp}(1.0, 4.5, \text{clamp}(E_{\text{kinetic}} / 10000, 0, 1))$

```
   Idle / Menu:     80 Hz Cutoff, Q=1.0  ──► Deep sub-bass cosmic hum
   Active Rally:   800 Hz Cutoff, Q=2.5  ──► Rushing wind tunnel / ocean swell
   Overdrive:     1600 Hz Cutoff, Q=4.0  ──► Screaming turbulent jet stream
```

---

## 5. Ball FM Synthesis (Speed & Vorticity Mapping)

### 2-Operator Frequency Modulation
The ball emits a continuous tone where the carrier frequency tracks velocity, and the modulation index tracks fluid vorticity (curl).

$$y(t) = A(t) \cdot \sin\left(\omega_c t + I_{\text{mod}} \cdot \sin(\omega_m t)\right)$$

* **Carrier Frequency ($\omega_c$):** $\omega_c = 2\pi \cdot \text{lerp}(110\text{ Hz}, 880\text{ Hz}, \frac{v_{\text{ball}}}{1200\text{ px/s}})$ (musical range $A_2 \to A_5$).
* **Modulation Frequency ($\omega_m$):** $\omega_m = 0.5 \cdot \omega_c$ (harmonic sub-octave relation).
* **Modulation Index ($I_{\text{mod}}$):** $I_{\text{mod}} = |\nabla \times v| \cdot 2.5$.
* **Stereo Pan:** Mapped to screen $X$ coordinate ($-1.0 = \text{left goal}, +1.0 = \text{right goal}$).

| Fluid Curl ($\nabla \times v$) | Mod Index ($I_{\text{mod}}$) | Acoustic Character |
|--------------------------------|------------------------------|--------------------|
| $0.0$ (Laminar) | $0.0$ | Pure sine flute; calm and clear |
| $0.5$ (Gentle Wake) | $1.25$ | Clarinet/reed warmth |
| $1.5$ (Vortex Core) | $3.75$ | Rich brass harmonic buzz |
| $3.0+$ (Chaotic Turbulence) | $7.5+$ | Metallic, dissonant bell roar |

---

## 6. Paddle Granular Dispersion

### Granular Water Texture
Paddles cutting through the fluid field spawn micro-grains of pitched resonant droplets:
- Grains dynamically allocated in a pre-warmed pool of 64 `AudioGrain` structs in C++.
- Grain spawn rate $\propto \|v_{\text{paddle}}\|$.
- Grain pitch randomized between $200\text{ Hz} \to 800\text{ Hz} + 0.5 \cdot \|v_{\text{paddle}}\|$.
- Exponential decay envelope over $20\text{–}60\text{ ms}$.

---

## 7. Impact & Blast Synthesis

### Blast Shockwave
- **Kick Sweep:** Fast pitch drop from $220\text{ Hz} \to 35\text{ Hz}$ over $250\text{ ms}$ with quadratic decay.
- **Cavitation Burst:** High-pass filtered white noise burst decaying over $120\text{ ms}$.
- **Sidechain Duck:** Instantly attenuates the Gameplay bus by $-6\text{ dB}$, recovering over $300\text{ ms}$.

### Wall & Paddle Impacts
- Resonant bandpass ping tuned to ball impact velocity ($300\text{ Hz} \to 1200\text{ Hz}$).
- Wall bounces ring longer ($T_{60} \approx 200\text{ ms}$); paddle impacts ring shorter and sharper ($T_{60} \approx 60\text{ ms}$).

---

## 8. Dynamic Dye Score Chords

When a goal is scored, the synthesizer samples the RGB dye vector at the goal plane to construct an additive musical triad:
- **P1 Goal (Cyan-Dominant):** Major triad ($1.0 : 1.25 : 1.50$) on $220\text{ Hz}$ base. Bright, resolved.
- **P2 Goal (Magenta-Dominant):** Minor triad ($1.0 : 1.20 : 1.50$) on $330\text{ Hz}$ base. Deep, dark.

---

## 9. Rally Escalation Audio

```
   Rally Hits 0-3  ──► Standard mix, serene plasma drone.
   Rally Hits 4-6  ──► Ball tone adds 2nd harmonic; drone cutoff rises to 600 Hz.
   Rally Hits 7-10 ──► Overdrive: Detuned chorus (±4 cents) on ball; rhythmic pulsing LFO.
   Rally Hits 11+  ──► Cymatic Lock: High frequencies cut at 400 Hz; 60 BPM sub-bass heartbeat.
```

---

## 10. GDExtension C++ Implementation Reference

### Header (`audio_dsp.h`)

```cpp
#pragma once

#include <godot_cpp/classes/audio_stream_player.hpp>
#include <godot_cpp/classes/audio_stream_generator.hpp>
#include <godot_cpp/classes/audio_stream_generator_playback.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

struct AudioGrain {
    float phase = 0.0f;
    float freq = 440.0f;
    float amp = 0.0f;
    float decay = 0.98f;
    float pan = 0.0f;
    bool active = false;
};

class CymaticsAudioDSP : public Node {
    GDCLASS(CymaticsAudioDSP, Node);

private:
    Ref<AudioStreamGeneratorPlayback> playback;
    int sample_rate = 48000;
    
    // Plasma Drone State
    float drone_cutoff = 100.0f;
    float drone_resonance = 1.0f;
    float bq_x1 = 0.0f, bq_x2 = 0.0f, bq_y1 = 0.0f, bq_y2 = 0.0f;
    float brown_acc = 0.0f;

    // Ball Tone FM State
    float ball_freq = 220.0f;
    float ball_mod_index = 0.0f;
    float ball_pan = 0.0f;
    float phase_carrier = 0.0f;
    float phase_mod = 0.0f;

    // Paddle Granular Pool
    static const int MAX_GRAINS = 64;
    AudioGrain grains[MAX_GRAINS];

protected:
    static void _bind_methods();

public:
    CymaticsAudioDSP();
    ~CymaticsAudioDSP();

    void set_playback_handle(Ref<AudioStreamGeneratorPlayback> p_playback);
    void update_fluid_drone(float avg_ke);
    void update_ball_tone(float speed, float curl, float norm_x);
    void spawn_paddle_grain(float speed, float norm_x);
    void process_audio_block(int frames_to_generate);
    void clear_buffers();
};

}
```

### Source Implementation (`audio_dsp.cpp`)

```cpp
#include "audio_dsp.h"
#include <cmath>
#include <cstdlib>

using namespace godot;

CymaticsAudioDSP::CymaticsAudioDSP() {
    for (int i = 0; i < MAX_GRAINS; ++i) {
        grains[i].active = false;
    }
}

CymaticsAudioDSP::~CymaticsAudioDSP() {}

void CymaticsAudioDSP::set_playback_handle(Ref<AudioStreamGeneratorPlayback> p_playback) {
    playback = p_playback;
}

void CymaticsAudioDSP::update_fluid_drone(float avg_ke) {
    float t = std::min(std::max(avg_ke / 5000.0f, 0.0f), 1.0f);
    drone_cutoff = 80.0f + t * (2000.0f - 80.0f);
    drone_resonance = 1.0f + t * 3.5f;
}

void CymaticsAudioDSP::update_ball_tone(float speed, float curl, float norm_x) {
    float t_speed = std::min(std::max(speed / 1200.0f, 0.0f), 1.0f);
    ball_freq = 110.0f + t_speed * (880.0f - 110.0f);
    ball_mod_index = std::abs(curl) * 2.5f;
    ball_pan = std::min(std::max(norm_x * 2.0f - 1.0f, -1.0f), 1.0f);
}

void CymaticsAudioDSP::spawn_paddle_grain(float speed, float norm_x) {
    for (int i = 0; i < MAX_GRAINS; ++i) {
        if (!grains[i].active) {
            grains[i].active = true;
            grains[i].phase = 0.0f;
            grains[i].freq = 200.0f + ((float)rand() / RAND_MAX) * 600.0f + speed * 0.4f;
            grains[i].amp = 0.04f * std::min(speed / 600.0f, 1.0f);
            grains[i].decay = 0.96f;
            grains[i].pan = norm_x * 2.0f - 1.0f;
            break;
        }
    }
}

void CymaticsAudioDSP::process_audio_block(int frames_to_generate) {
    if (playback.is_null()) return;

    const float TAU = 6.28318530718f;

    // Biquad Bandpass Coefficients
    float w0 = TAU * drone_cutoff / (float)sample_rate;
    float alpha = std::sin(w0) / (2.0f * drone_resonance);
    float b0 = alpha, b1 = 0.0f, b2 = -alpha;
    float a0 = 1.0f + alpha, a1 = -2.0f * std::cos(w0), a2 = 1.0f - alpha;

    for (int f = 0; f < frames_to_generate; ++f) {
        // 1. Brown Noise Drone
        float white = ((float)rand() / RAND_MAX) * 2.0f - 1.0f;
        brown_acc = (brown_acc + 0.02f * white) / 1.02f;
        float drone_in = brown_acc * 3.5f;

        float drone_out = (b0 * drone_in + b1 * bq_x1 + b2 * bq_x2 - a1 * bq_y1 - a2 * bq_y2) / a0;
        bq_x2 = bq_x1; bq_x1 = drone_in;
        bq_y2 = bq_y1; bq_y1 = drone_out;

        // 2. Ball FM Synth
        float mod_freq = ball_freq * 0.5f;
        phase_mod += mod_freq * TAU / (float)sample_rate;
        float modulator = std::sin(phase_mod) * ball_mod_index;

        phase_carrier += (ball_freq + modulator) * TAU / (float)sample_rate;
        float ball_sample = std::sin(phase_carrier) * 0.20f;

        float ball_l = ball_sample * (1.0f - ball_pan) * 0.5f;
        float ball_r = ball_sample * (1.0f + ball_pan) * 0.5f;

        // 3. Granular Accumulation
        float grain_l = 0.0f, grain_r = 0.0f;
        for (int i = 0; i < MAX_GRAINS; ++i) {
            if (grains[i].active) {
                grains[i].phase += grains[i].freq * TAU / (float)sample_rate;
                float g_sample = std::sin(grains[i].phase) * grains[i].amp;
                grain_l += g_sample * (1.0f - grains[i].pan) * 0.5f;
                grain_r += g_sample * (1.0f + grains[i].pan) * 0.5f;
                grains[i].amp *= grains[i].decay;
                if (grains[i].amp < 0.001f) grains[i].active = false;
            }
        }

        // Stereo Master Mix
        Vector2 out_frame(
            drone_out * 0.25f + ball_l + grain_l * 0.5f,
            drone_out * 0.25f + ball_r + grain_r * 0.5f
        );

        playback->push_frame(out_frame);
    }
}

void CymaticsAudioDSP::clear_buffers() {
    bq_x1 = bq_x2 = bq_y1 = bq_y2 = 0.0f;
    brown_acc = 0.0f;
    phase_carrier = phase_mod = 0.0f;
    for (int i = 0; i < MAX_GRAINS; ++i) grains[i].active = false;
}
```

---

## 11. Rollback Sync & Audio Buffer Management

Because procedural audio state is computed in real time from physical vectors, rolling back simulation frames requires zero file reloading.

When the `RollbackManager` executes a rollback:
1. `AudioManager` calls `CymaticsAudioDSP.clear_buffers()` to flush stale prediction frames from the generator ring buffer.
2. The DSP state immediately catches up on the next audio tick using the restored `GameState` variables.

---

## 12. Mastering & Dynamic Sidechain Ducking

```
  Bus Configuration:
  Master (0 dB)
  ├── Gameplay (-3 dB) ──► Sidechain Duck Target (-6 dB during Blasts)
  ├── Impacts  (-1 dB) ──► Sidechain Trigger Source
  └── UI       (-2 dB) ──► Clean Passthrough
```

* **Dynamic Range Target:** $-16\text{ LUFS}$ integrated loudness.
* **Master Bus Limiter:** Ceiling $-0.1\text{ dB}$ to prevent inter-sample digital clipping during multi-grain comb filtering.

---

*For technical shader implementation, see `CYMATICS_Technical_Spec.md`.*
