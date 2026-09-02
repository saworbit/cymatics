#!/usr/bin/env python
"""Procedural three-stem soundtrack ("synth") for That's a Paddlin'.

    python tools/gen_music.py          # write the stems
    python tools/gen_music.py --list   # names only

Writes to assets/audio/music/stems/:

    synth_pad.wav    A  slow detuned-saw chords            (stereo)
    synth_pulse.wav  B  filtered 16th-note bass arpeggio   (mono)
    synth_drive.wav  C  kick / hat / snare                 (mono)

All three are exactly the same length (8 bars of 4/4 at 112 BPM = 756000
frames at 44.1 kHz), bar-aligned, and loop seamlessly: note tails past the
loop end are folded back onto the start, and each carries a `smpl` loop
chunk.  WAV rather than OGG because Vorbis pads frames and the AudioManager
keeps the three players sample-locked.

Key: A minor.  Progression (2 bars each): Am  F  C  G.

Original, deterministic (seeded), CC0.  Shares its DSP primitives with
tools/gen_sfx.py.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sfx as g  # noqa: E402

SR = g.SR
BPM = 112.0
BARS = 8
BEATS = BARS * 4
BEAT = 60.0 / BPM
LOOP_FRAMES = int(round(BEATS * BEAT * SR))  # 756000
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "music", "stems")
TAIL = 2.5  # seconds rendered past the loop end and folded back in
SEED = 0x5EED5

rng = np.random.default_rng(SEED)


def midi(n: float) -> float:
    return 440.0 * 2 ** ((n - 69) / 12.0)


# A2 = 45, F2 = 41, C3 = 48, G2 = 43 (roots), voicings as MIDI numbers.
PROG = [
    (45, [57, 60, 64, 69]),   # Am: A3 C4 E4 A4
    (41, [57, 60, 65, 69]),   # F : A3 C4 F4 A4
    (48, [55, 60, 64, 67]),   # C : G3 C4 E4 G4
    (43, [55, 59, 62, 67]),   # G : G3 B3 D4 G4
]


def beat_frame(b: float) -> int:
    return int(round(b * BEAT * SR))


def place(buf: np.ndarray, seg: np.ndarray, at_frame: int) -> None:
    end = min(at_frame + seg.size, buf.size)
    if end > at_frame:
        buf[at_frame:end] += seg[: end - at_frame]


def fold(buf: np.ndarray) -> np.ndarray:
    """Add everything past LOOP_FRAMES back onto the start (seamless wrap)."""
    core = np.copy(buf[:LOOP_FRAMES])
    tail = buf[LOOP_FRAMES:]
    core[: tail.size] += tail[: LOOP_FRAMES]
    return core


def render_len() -> int:
    return LOOP_FRAMES + int(TAIL * SR)


def lp_track(x: np.ndarray, cut: np.ndarray, blocks: int = 256) -> np.ndarray:
    """Block-wise low-pass with a per-sample cutoff array; filter state carries
    across blocks so there are no clicks at block edges."""
    from scipy import signal
    out = np.zeros_like(x)
    edges = np.linspace(0, x.size, blocks + 1).astype(int)
    zi = None
    for b in range(blocks):
        a, e = edges[b], edges[b + 1]
        if e <= a:
            continue
        sos = signal.butter(2, float(cut[a]), btype="low", fs=SR, output="sos")
        if zi is None:
            zi = signal.sosfilt_zi(sos) * x[a]
        out[a:e], zi = signal.sosfilt(sos, x[a:e], zi=zi)
    return out


# ---------------------------------------------------------------- A: pad
def pad_voice(freq: float, dur: float, detune_cents: float, phase: float) -> np.ndarray:
    ratio = 2 ** (detune_cents / 1200.0)
    v = g.saw(freq * ratio, dur) * 0.5 + g.saw(freq / ratio, dur) * 0.5
    v += g.sine(freq * 0.5, dur, phase) * 0.35
    return v


def stem_pad() -> np.ndarray:
    N = render_len()
    chans = []
    for ch, cents in enumerate((6.0, -6.0)):
        buf = np.zeros(N)
        for i, (_root, notes) in enumerate(PROG):
            start_b = i * 8.0
            dur = 8.0 * BEAT + 1.6  # release spills into the next chord / the wrap
            chord = np.zeros(g.n(dur))
            for k, m in enumerate(notes):
                chord += pad_voice(midi(m), dur, cents * (1.0 + 0.15 * k), 0.4 * k + ch) * (0.85 ** k)
            env = g.adsr(dur, 0.9, 1.5, 0.8, 1.6)
            place(buf, chord * env, beat_frame(start_b))
        # Slow filter breathing (one cycle per loop, opening on the second half).
        lfo = 0.5 + 0.5 * np.sin(2 * np.pi * np.arange(N) / LOOP_FRAMES - np.pi / 2)
        out = lp_track(buf, 700.0 + 1500.0 * lfo)
        out = g.hp(out, 60.0)
        chans.append(fold(out))
    x = np.stack(chans, axis=1)
    # Gentle stereo widening: cross-feed a slightly delayed copy.
    d = g.n(0.009)
    wide = np.copy(x)
    wide[d:, 0] += x[:-d, 1] * 0.18
    wide[d:, 1] += x[:-d, 0] * 0.18
    return wide


# ---------------------------------------------------------------- B: pulse
def stem_pulse() -> np.ndarray:
    N = render_len()
    buf = np.zeros(N)
    step = BEAT / 4.0
    pattern = [0, 7, 12, 7, 0, 7, 12, 19, 0, 7, 12, 7, 0, 12, 7, 5]  # semitones above root, 16 steps per bar
    for i, (root, _notes) in enumerate(PROG):
        for bar in range(2):
            for s in range(16):
                accent = 1.0 if s % 4 == 0 else (0.75 if s % 2 == 0 else 0.6)
                m = root + pattern[s] + (12 if (bar == 1 and s in (13, 15)) else 0)
                f = midi(m)
                dur = step * 1.15
                note = g.saw(f, dur) * 0.6 + g.sine(f, dur) * 0.5 + np.sign(g.sine(f * 2.0, dur)) * 0.12
                env = g.adsr(dur, 0.002, step * 0.5, 0.35, step * 0.3)
                # Per-note filter pluck: bright attack falling into the body.
                note = g.sweep_lp(note * env, 2600.0 * accent, 320.0, 12)
                at = beat_frame((i * 8 + bar * 4) + s / 4.0)
                place(buf, note * accent, at)
    buf = g.hp(buf, 35.0)
    return fold(g.soft_clip(buf, 1.3))


# ---------------------------------------------------------------- C: drive
def kick() -> np.ndarray:
    dur = 0.32
    body = g.sine(g.geo(dur, 170.0, 44.0), dur) * g.expdec(dur, 0.09)
    click = g.hp(g.noise(0.008), 2500.0) * g.expdec(0.008, 0.002) * 0.5
    return g.soft_clip(g.mix(body, click), 1.6)


def snare() -> np.ndarray:
    dur = 0.24
    tone = g.sine(g.geo(dur, 240.0, 170.0), dur) * g.expdec(dur, 0.04) * 0.6
    rattle = g.bp(g.noise(dur), 900.0, 7500.0) * g.expdec(dur, 0.06)
    return g.soft_clip(g.mix(tone, rattle), 1.4) * 0.85


def hat(open_: bool) -> np.ndarray:
    dur = 0.22 if open_ else 0.05
    x = g.hp(g.noise(dur), 6500.0) * g.expdec(dur, 0.07 if open_ else 0.012)
    x += g.bp(g.noise(dur), 9000.0, 14000.0) * g.expdec(dur, 0.05 if open_ else 0.01) * 0.5
    return x * (0.5 if open_ else 0.42)


def stem_drive() -> np.ndarray:
    N = render_len()
    buf = np.zeros(N)
    k, sn, hc, ho = kick(), snare(), hat(False), hat(True)
    for bar in range(BARS):
        b0 = bar * 4.0
        kicks = [0.0, 1.5, 2.0, 3.5] if bar % 2 == 0 else [0.0, 1.5, 2.0, 2.75, 3.5]
        if bar == BARS - 1:
            kicks = [0.0, 1.5, 2.0, 3.0, 3.5, 3.75]
        for kb in kicks:
            place(buf, k * (1.0 if kb in (0.0, 2.0) else 0.8), beat_frame(b0 + kb))
        for sb in (1.0, 3.0):
            place(buf, sn, beat_frame(b0 + sb))
        if bar == BARS - 1:
            place(buf, sn * 0.5, beat_frame(b0 + 3.5))
            place(buf, sn * 0.6, beat_frame(b0 + 3.75))
        for s in range(16):
            open_ = s in (2, 10)
            vel = 1.0 if s % 4 == 0 else (0.7 if s % 2 == 0 else 0.45)
            place(buf, (ho if open_ else hc) * vel, beat_frame(b0 + s / 4.0))
    return fold(g.soft_clip(buf, 1.2))


# ---------------------------------------------------------------- output
STEMS = [
    ("synth_pad", stem_pad, -6.0),
    ("synth_pulse", stem_pulse, -4.0),
    ("synth_drive", stem_drive, -3.0),
]


def main(argv) -> int:
    if "--list" in argv:
        for name, _, _ in STEMS:
            print(name)
        return 0
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, gen, peak_db in STEMS:
        x = gen()
        assert x.shape[0] == LOOP_FRAMES, (name, x.shape)
        # compress=0: keep PCM so the loop wrap is bit-exact across the three stems.
        g.write_wav(name, x, loop=True, out_dir=OUT_DIR, peak_db=peak_db, compress=0)
        chans = 1 if x.ndim == 1 else x.shape[1]
        print(f"{name:14s} {x.shape[0]} frames  {x.shape[0] / SR:6.3f}s  {chans}ch  peak {peak_db:+.0f} dBFS")
    print(f"wrote {len(STEMS)} stems ({BARS} bars @ {BPM:g} BPM, {LOOP_FRAMES} frames) to {os.path.normpath(OUT_DIR)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
