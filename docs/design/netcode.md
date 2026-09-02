# CYMATICS — Netcode Specification

> **Status (2026-09-02): planned, not implemented.** There is no networking, rollback, or determinism in the current build. This document is a design target only.

> **Version:** 2.0  
> **Date:** 2026-08-29  
> **Engine:** Godot 4.7.2+  
> **Architecture:** Deterministic Input-Prediction & Rollback (GGPO-Style)  
> **Protocol:** Low-Overhead Custom UDP (`PacketPeerUDP`)  
> **Target Rates:** 60 Hz Network/Input Tick, 180 Hz Internal Physics Substeps

---

## Table of Contents

1. [Design Philosophy & Network Invariants](#1-design-philosophy--network-invariants)
2. [Why Custom Rollback over Engine RPCs?](#2-why-custom-rollback-over-engine-rpcs)
3. [Architecture Overview & Data Flow](#3-architecture-overview--data-flow)
4. [Determinism Guarantees (IEEE 754 & GPU Compute)](#4-determinism-guarantees-ieee-754--gpu-compute)
5. [Input Serialization & Redundant Packets](#5-input-serialization--redundant-packets)
6. [GPU VRAM Rollback Algorithm](#6-gpu-vram-rollback-algorithm)
7. [State Snapshot Management](#7-state-snapshot-management)
8. [Desync Detection & Recovery Protocol](#8-desync-detection--recovery-protocol)
9. [Spectator Architecture](#9-spectator-architecture)
10. [Latency Hiding & Visual Reconciliation](#10-latency-hiding--visual-reconciliation)
11. [GDScript Rollback Reference Implementation](#11-gdscript-rollback-reference-implementation)
12. [Stress Testing & Network Profiling](#12-stress-testing--network-profiling)

---

## 1. Design Philosophy & Network Invariants

In CYMATICS, a high-velocity ball travels across the 1920-pixel court in less than 1.5 seconds. A single frame ($16.6\text{ ms}$) separates a perfect parry from a conceded goal.

```
   ┌────────────────────────────────────────────────────────────┐
   │                   NETCODE INVARIANTS                       │
   ├────────────────────────────┬───────────────────────────────┤
   │ Zero Fluid Network Traffic │ Only 24-byte input states are │
   │                            │ sent over UDP.                │
   ├────────────────────────────┼───────────────────────────────┤
   │ GPU VRAM Ring Snapshots    │ 120-frame Texture2DArray in   │
   │                            │ VRAM allows instant rollback. │
   ├────────────────────────────┼───────────────────────────────┤
   │ Diegetic Glitch Masking    │ Reconciliations are framed as │
   │                            │ plasma interference ripples.  │
   └────────────────────────────┴───────────────────────────────┘
```

---

## 2. Why Custom Rollback over Engine RPCs?

Godot's built-in `MultiplayerAPI` relies on authoritative state replication via High-Level RPCs. For CYMATICS, this fails because:
1. **Bandwidth Impossibility:** Syncing a $256 \times 144$ fluid grid at 60 FPS requires $\approx 35.4\text{ MB/s}$ uncompressed — completely unfeasible over consumer internet.
2. **Input Lag Elimination:** Delay-based netcode introduces artificial input lag that ruins precision parrying. Rollback provides **instant local responsiveness** while predicting remote opponent moves.

---

## 3. Architecture Overview & Data Flow

```
   ┌──────────────────────┐    UDP Unreliable Socket    ┌──────────────────────┐
   │   Host Client (P1)   │ ◄─────────────────────────► │   Guest Client (P2)  │
   │                      │    Input Packets Only       │                      │
   └──────────┬───────────┘    (~1.4 KB/s Upstream)     └──────────┬───────────┘
              │                                                    │
   ┌──────────▼───────────┐                             ┌──────────▼───────────┐
   │   RollbackManager    │                             │   RollbackManager    │
   │ - Input Ring Buffer  │                             │ - Input Ring Buffer  │
   │ - State History (RAM)│                             │ - State History (RAM)│
   └──────────┬───────────┘                             └──────────┬───────────┘
              │                                                    │
   ┌──────────▼───────────┐                             ┌──────────▼───────────┐
   │ Local RenderingDevice│                             │ Local RenderingDevice│
   │ - Compute Simulation │                             │ - Compute Simulation │
   │ - 120-layer VRAM Array│                            │ - 120-layer VRAM Array│
   └──────────────────────┘                             └──────────────────────┘
```

---

## 4. Determinism Guarantees (IEEE 754 & GPU Compute)

For input-only rollback to work, both clients running the same sequence of inputs must produce identical game worlds.

| System | Determinism Strategy |
|--------|---------------------|
| **GPU Compute Fluid** | Fixed grid resolution ($256 \times 144$), fixed substep $\Delta t = \frac{1}{180}\text{ s}$. Avoid non-deterministic `atomicAdd` instructions; each cell is updated strictly by a single compute invocation. |
| **Ball Dynamics** | Integrated via fixed math in the SSBO compute pass (`cymatics_ball.glsl`). |
| **Paddle Movement** | Clamped to fixed integer precision sub-pixels prior to fluid force splatting. |
| **RNG Seeds** | Seeded `RandomNumberGenerator` with identical initial match seeds; purely cosmetic variations (film grain, marker particle spawn) are decoupled from physics. |

---

## 5. Input Serialization & Redundant Packets

### Input State Definition (`InputState`)
Every frame, each player generates a compact 24-byte input snapshot:

```
   Byte Offset    Field              Type         Description
   ──────────────────────────────────────────────────────────────────────────
   0x00 - 0x03    frame              int32        Simulation frame index
   0x04 - 0x07    player_id          uint32       Player identifier (0 or 1)
   0x08 - 0x0F    direction          vec2 (f32)   Paddle move vector (-1..1)
   0x10           flags              uint8        Bit 0: Suck | Bit 1: Blast
   0x11 - 0x14    blast_charge       float32      Charge duration (0.0..2.0s)
   0x15 - 0x17    padding            uint8[3]     Memory alignment
```

### Packet Redundancy
To survive packet loss on UDP connections without TCP resend latency, each transmitted UDP packet contains the **current frame's input plus the preceding 2 frames' inputs** (Triple Redundancy). A client can drop up to 2 consecutive packets without experiencing an input stall.

---

## 6. GPU VRAM Rollback Algorithm

```
  Normal Execution (Frame T):
  Input Captured ──► Dispatch Compute Passes ──► Snapshot to VRAM Layer (T % 120)

  Rollback Triggered (Frame T corrected back to Frame T - K):
  1. Restore VRAM Layer ((T - K) % 120) ──► Active Textures (<0.02 ms Blit)
  2. Restore CPU GameState (T - K) ───────► Ball SSBO & Paddles
  3. Fast-Forward Resimulate K frames ───► Dispatch Compute passes for f = (T-K)..T
  4. Trigger Glitch Shader ──────────────► Diegetically mask visual snap
```

### VRAM Texture Array Ring Buffer Specs
- **Texture Format:** `Texture2DArray` (120 layers)
- **Velocity Array:** $256 \times 144 \times 120 \times 8\text{ bytes} \approx 35.4\text{ MB}$
- **Dye Array:** $256 \times 144 \times 120 \times 8\text{ bytes} \approx 35.4\text{ MB}$
- **Total VRAM Footprint:** **$\approx 70.8\text{ MB}$**

Because all 120 frames reside directly on the GPU, rewinding the fluid state is an instantaneous GPU-to-GPU sub-resource copy requiring zero CPU memory bus bandwidth.

---

## 7. State Snapshot Management

### CPU GameState (`GameState`)
Stored every frame in a circular array of 120 slots (~128 bytes per snapshot):

```gdscript
class_name GameState
extends RefCounted

var frame: int
var ball_position: Vector2
var ball_velocity: Vector2
var ball_spin: float
var paddle_positions: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var paddle_velocities: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var blast_charges: Array[float] = [0.0, 0.0]
var momentum: Array[float] = [0.0, 0.0]
var scores: Array[int] = [0, 0]
```

---

## 8. Desync Detection & Recovery Protocol

Every 30 simulation frames ($0.5\text{s}$), clients calculate and exchange a fast 32-bit state hash:

$$\text{Hash} = \text{CRC32}(\text{ball\_pos} \oplus \text{ball\_vel} \oplus \text{p1\_pos} \oplus \text{p2\_pos} \oplus \text{score})$$

### Recovery Procedure if Hashes Disagree:
1. **Pause Buffer:** Both clients pause simulation for 2 frames ($33\text{ ms}$).
2. **Host Authority Sync:** Host transmits authoritative `GameState` packet.
3. **Guest Soft Convergence:** Guest overwrites ball SSBO and paddle coordinates. The local fluid texture is retained; fluid streamlines naturally converge to the true ball location within 6–10 simulation frames.
4. **Interference Pulse:** A full-screen 3-frame chromatic aberration and scanline pulse triggers, disguising the recovery as a diegetic plasma field fluctuation.

---

## 9. Spectator Architecture

Spectator clients connect directly to the host and receive broadcasted `InputState` streams with zero artificial input delay:
* Spectators simulate the entire fluid and ball pipeline locally.
* Zero host rendering or bandwidth penalty (host uploads only lightweight 24-byte input packets).
* Perfect 60/120 FPS broadcast feed with zero rollback artifacts or prediction mispredictions.

---

## 10. Latency Hiding & Visual Reconciliation

```
   Latency (Ping)     Input Delay Buffer     Rollback Frequency     Visual Quality
   ──────────────────────────────────────────────────────────────────────────────
   0 - 33 ms          2 frames (33 ms)       0% (Zero rollback)     Flawless
   34 - 70 ms         2 frames (33 ms)       <3% of frames          Imperceptible
   71 - 120 ms        3 frames (50 ms)       ~8% of frames          Smooth (Glitch Mask)
   > 150 ms           4 frames (66 ms)       >15% (Adaptive Stall)  Playable
```

* **Local Paddle Direct Rendering:** The local paddle renders at the immediate user input coordinate, while the simulation processes with a 2-frame delay buffer, giving the player $0\text{ ms}$ perceived input response time.
* **Ball Position Reconciliation:** If a rollback alters the ball's position by $>4\text{ pixels}$, the visual sprite smoothly snaps to the true position over 2 frames with a localized dye flash.

---

## 11. GDScript Rollback Reference Implementation

```gdscript
class_name RollbackManager
extends Node

const HISTORY_DEPTH := 120
const INPUT_DELAY := 2
const PREDICTION_TIMEOUT := 8

var current_frame := 0
var confirmed_frame := 0
var input_history: Array[Array] = []
var state_history: Array[GameState] = []

var udp_peer: PacketPeerUDP
var is_host := false

func _ready() -> void:
    for i in range(HISTORY_DEPTH):
        input_history.append([null, null])
        state_history.append(null)
    udp_peer = PacketPeerUDP.new()

func _physics_process(_delta: float) -> void:
    # 1. Process Incoming Remote Inputs
    _receive_packets()

    # 2. Capture and Send Local Inputs (with Delay Buffer)
    var local_input := _capture_local_input()
    local_input.frame = current_frame + INPUT_DELAY
    _store_input(local_input, 0 if is_host else 1)
    _send_input_packet(local_input)

    # 3. Simulate or Predict
    if _has_inputs_for_frame(current_frame):
        _simulate_frame(current_frame)
        confirmed_frame = current_frame
    else:
        _predict_and_simulate(current_frame)
        if current_frame - confirmed_frame > PREDICTION_TIMEOUT:
            _stall_simulation()
            return
    
    current_frame += 1

func _on_remote_input_received(remote_input: InputState) -> void:
    var f := remote_input.frame
    if f < current_frame - HISTORY_DEPTH or f >= current_frame + HISTORY_DEPTH:
        return

    var stored: InputState = input_history[f % HISTORY_DEPTH][remote_input.player_id]
    if stored != null and not stored.equals(remote_input):
        # Input mismatch detected: Execute Rollback
        _execute_rollback(f)

    input_history[f % HISTORY_DEPTH][remote_input.player_id] = remote_input

func _execute_rollback(target_frame: int) -> void:
    # 1. Restore GPU VRAM Snapshot (<0.02 ms)
    FluidSimulator.rollback_to_vram_layer(target_frame)

    # 2. Restore CPU GameState Snapshot
    var saved_state: GameState = state_history[target_frame % HISTORY_DEPTH]
    _restore_game_state(saved_state)

    # 3. Fast-Forward Resimulate to Current Frame
    for f in range(target_frame, current_frame):
        _simulate_frame(f)

    # 4. Mask with Diegetic Glitch Pulse
    get_viewport().get_camera_2d().apply_rollback_flash()

func _simulate_frame(frame_idx: int) -> void:
    var inputs: Array = input_history[frame_idx % HISTORY_DEPTH]
    PaddleLeft.apply_input(inputs[0])
    PaddleRight.apply_input(inputs[1])

    # Step GPU Fluid Compute and SSBO Ball Physics
    FluidSimulator.step_simulation(1.0 / 180.0, frame_idx)

    # Save State Snapshot
    state_history[frame_idx % HISTORY_DEPTH] = _capture_game_state(frame_idx)
```

---

## 12. Stress Testing & Network Profiling

### Automated Verification Benchmarks
* **Artificial Latency Simulation:** $120\text{ ms}$ round-trip ping + $5\%$ packet loss sustained for a 5-minute match. Expected outcome: zero game-breaking desyncs, $<2\%$ visible ball reconciliation snaps.
* **VRAM Memory Stability:** Continuous 1-hour match running the 120-layer `Texture2DArray` ping-pong without memory leaks or GPU command buffer exhaustion.

---

*For technical fluid compute specifications, see `CYMATICS_Technical_Spec.md`.*
