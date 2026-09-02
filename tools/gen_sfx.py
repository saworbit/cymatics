#!/usr/bin/env python
"""Deterministic plasma / sci-fi SFX synthesiser for That's a Paddlin'.

Writes 44.1 kHz 16-bit WAV files (mono; stereo for stingers) into
assets/audio/sfx/gen/.  Everything here is original, CC0.

    python tools/gen_sfx.py            # regenerate the whole set
    python tools/gen_sfx.py --list     # print the file names only
    python tools/gen_sfx.py lock_pulse # only the named files (RNG state then
                                       # differs from a full run; do a full run
                                       # before committing)

Seamless loops carry a `smpl` chunk (Godot's WAV importer picks the loop up
with the default "Detect From WAV" mode) and are also flagged in the .import.
"""
from __future__ import annotations

import os
import re
import struct
import sys

import numpy as np
from scipy import signal

SR = 44100
SEED = 0xC7A7
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "sfx", "gen")
PEAK_DB = -3.0

rng = np.random.default_rng(SEED)


# ---------------------------------------------------------------- primitives
def t(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def n(dur: float) -> int:
    return int(dur * SR)


def sine(freq, dur: float, phase: float = 0.0) -> np.ndarray:
    """Sine with a constant or per-sample frequency array (pitch envelopes)."""
    tt = t(dur)
    if np.isscalar(freq):
        return np.sin(2 * np.pi * freq * tt + phase)
    f = np.asarray(freq, dtype=float)
    if f.size != tt.size:
        f = np.interp(tt, np.linspace(0, dur, f.size), f)
    return np.sin(2 * np.pi * np.cumsum(f) / SR + phase)


def saw(freq, dur: float) -> np.ndarray:
    tt = t(dur)
    f = freq if np.isscalar(freq) else np.interp(tt, np.linspace(0, dur, np.size(freq)), freq)
    ph = np.cumsum(np.full(tt.size, f) if np.isscalar(f) else f) / SR
    return 2.0 * (ph - np.floor(ph + 0.5))


def noise(dur: float) -> np.ndarray:
    return rng.standard_normal(n(dur))


def brown(dur: float, leak: float = 0.995) -> np.ndarray:
    x = noise(dur)
    y = signal.lfilter([1.0], [1.0, -leak], x)
    return y / (np.max(np.abs(y)) + 1e-9)


def expdec(dur: float, tau: float, start: float = 1.0) -> np.ndarray:
    return start * np.exp(-t(dur) / tau)


def adsr(dur: float, a: float, d: float, s: float, r: float) -> np.ndarray:
    N = n(dur)
    env = np.zeros(N)
    ia, idd, ir = n(a), n(d), n(r)
    ia = max(ia, 1)
    env[:ia] = np.linspace(0, 1, ia)
    end_d = min(ia + idd, N)
    env[ia:end_d] = np.linspace(1, s, end_d - ia)
    env[end_d:] = s
    if ir > 0 and ir < N:
        env[N - ir:] *= np.linspace(1, 0, ir)
    return env


def lin(dur: float, a: float, b: float) -> np.ndarray:
    return np.linspace(a, b, n(dur))


def geo(dur: float, a: float, b: float) -> np.ndarray:
    return np.geomspace(a, b, n(dur))


def _sos(kind, cut, order=2):
    return signal.butter(order, cut, btype=kind, fs=SR, output="sos")


def lp(x, hz, order=2):
    return signal.sosfilt(_sos("low", min(hz, SR * 0.49), order), x)


def hp(x, hz, order=2):
    return signal.sosfilt(_sos("high", max(hz, 10.0), order), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("band", [max(lo, 10.0), min(hi, SR * 0.49)], order), x)


def sweep_lp(x: np.ndarray, hz_from: float, hz_to: float, blocks: int = 64) -> np.ndarray:
    """Block-wise time-varying low-pass (cheap filter sweep)."""
    out = np.zeros_like(x)
    edges = np.linspace(0, x.size, blocks + 1).astype(int)
    cuts = np.geomspace(hz_from, hz_to, blocks)
    zi = None
    for i in range(blocks):
        seg = x[edges[i]:edges[i + 1]]
        if seg.size == 0:
            continue
        sos = _sos("low", cuts[i])
        if zi is None:
            zi = signal.sosfilt_zi(sos) * seg[0]
        seg_out, zi = signal.sosfilt(sos, seg, zi=zi)
        out[edges[i]:edges[i + 1]] = seg_out
    return out


def reverb(x: np.ndarray, mix: float = 0.25, decay: float = 0.7, tail: float = 0.3) -> np.ndarray:
    """Schroeder reverb: 4 parallel combs into 2 series allpasses."""
    x = np.concatenate([x, np.zeros(n(tail))])
    combs = [1116, 1188, 1277, 1356]
    wet = np.zeros_like(x)
    for d in combs:
        a = np.zeros(d + 1)
        a[0] = 1.0
        a[d] = -decay
        wet += signal.lfilter([1.0], a, x)
    wet /= len(combs)
    for d, g in ((556, 0.5), (441, 0.5)):
        b = np.zeros(d + 1)
        b[0] = -g
        b[d] = 1.0
        a = np.zeros(d + 1)
        a[0] = 1.0
        a[d] = -g
        wet = signal.lfilter(b, a, wet)
    return x * (1.0 - mix) + wet * mix


def delay_mix(x: np.ndarray, ms: float, gain: float) -> np.ndarray:
    d = n(ms / 1000.0)
    y = np.copy(x)
    y[d:] += x[:-d] * gain
    return y


def fade(x: np.ndarray, in_ms: float = 2.0, out_ms: float = 8.0) -> np.ndarray:
    x = np.copy(x)
    fi, fo = n(in_ms / 1000.0), n(out_ms / 1000.0)
    fi = min(fi, x.size // 2)
    fo = min(fo, x.size // 2)
    if fi > 0:
        x[:fi] *= np.linspace(0, 1, fi)
    if fo > 0:
        x[-fo:] *= np.linspace(1, 0, fo)
    return x


def normalize(x: np.ndarray, peak_db: float = PEAK_DB) -> np.ndarray:
    peak = np.max(np.abs(x)) + 1e-9
    return x * (10 ** (peak_db / 20.0) / peak)


def loopify(x: np.ndarray, xfade: float) -> np.ndarray:
    """Crossfade the tail into the head so the file loops seamlessly."""
    xf = n(xfade)
    body = np.copy(x[: x.size - xf])
    ramp = np.linspace(0, 1, xf)
    body[:xf] = x[:xf] * ramp + x[x.size - xf:] * (1.0 - ramp)
    return body


def pad(x: np.ndarray, dur: float) -> np.ndarray:
    N = n(dur)
    if x.size >= N:
        return x[:N]
    return np.concatenate([x, np.zeros(N - x.size)])


def mix(*parts: np.ndarray) -> np.ndarray:
    N = max(p.size for p in parts)
    out = np.zeros(N)
    for p in parts:
        out[: p.size] += p
    return out


def stereo(x: np.ndarray, width_ms: float = 0.6, verb: float = 0.18) -> np.ndarray:
    left = reverb(x, verb, 0.72, 0.4)
    right = reverb(delay_mix(x, width_ms, 0.0), verb, 0.7, 0.4)
    d = n(width_ms / 1000.0)
    right = np.concatenate([np.zeros(d), right[:-d]])
    N = max(left.size, right.size)
    return np.stack([pad(left, N / SR), pad(right, N / SR)], axis=1)


def soft_clip(x: np.ndarray, drive: float = 1.5) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


# ---------------------------------------------------------------- WAV writer
def write_wav(name: str, x: np.ndarray, loop: bool = False, loop_begin: int = 0, out_dir: str | None = None, peak_db: float = PEAK_DB, compress: int | None = None) -> None:
    """16-bit PCM WAV. `loop` adds a `smpl` chunk from `loop_begin` to the end."""
    out_dir = out_dir or OUT_DIR
    os.makedirs(out_dir, exist_ok=True)
    x = np.asarray(x, dtype=float)
    if x.ndim == 1:
        chans = 1
        if not loop:
            x = fade(x)
    else:
        chans = x.shape[1]
        if not loop:
            x = np.stack([fade(x[:, c]) for c in range(chans)], axis=1)
    x = normalize(x, peak_db)
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2").tobytes()
    frames = x.shape[0]
    fmt = struct.pack("<HHIIHH", 1, chans, SR, SR * chans * 2, chans * 2, 16)
    chunks = [b"fmt " + struct.pack("<I", len(fmt)) + fmt]
    if loop:
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<IIIIII", 0, 0, int(loop_begin), frames - 1, 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    chunks.append(b"data" + struct.pack("<I", len(pcm)) + pcm)
    body = b"WAVE" + b"".join(chunks)
    with open(os.path.join(out_dir, name + ".wav"), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)
    if loop or compress is not None:
        patch_import(os.path.join(out_dir, name + ".wav.import"), loop_begin, compress)


def patch_import(path: str, loop_begin: int = 0, compress: int | None = None) -> bool:
    """Force forward looping in an existing Godot .import (written by the editor
    or a headless `--import`).  The `smpl` chunk already covers "Detect From
    WAV"; this pins it so a re-import with different defaults cannot lose it."""
    if not os.path.exists(path):
        return False
    with open(path, "r", encoding="utf-8") as f:
        txt = f.read()
    new = txt
    new = re.sub(r"edit/loop_mode=\d+", "edit/loop_mode=2", new)
    new = re.sub(r"edit/loop_begin=-?\d+", f"edit/loop_begin={int(loop_begin)}", new)
    new = re.sub(r"edit/loop_end=-?\d+", "edit/loop_end=-1", new)
    if compress is not None:
        new = re.sub(r"compress/mode=\d+", f"compress/mode={int(compress)}", new)
    if new != txt:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(new)
    return True


# ---------------------------------------------------------------- designs
def paddle_hit(variant: int) -> np.ndarray:
    dur = 0.18
    base = 150.0 * (1.0 + 0.06 * variant)
    thud = sine(geo(dur, base * 2.4, base * 0.8), dur) * expdec(dur, 0.045)
    body = lp(noise(dur), 900 + 200 * variant) * expdec(dur, 0.03) * 0.9
    click = hp(noise(0.012), 3500 + 600 * variant) * expdec(0.012, 0.003) * 0.7
    rubber = sine(geo(dur, 420 + 40 * variant, 260), dur) * expdec(dur, 0.02) * 0.5
    return soft_clip(mix(thud, body, click, rubber), 1.8)


def wall_hit(variant: int) -> np.ndarray:
    dur = 0.3
    f0 = 1180.0 * (1.0 + 0.09 * variant)
    partials = [(1.0, 1.0), (2.76, 0.45), (5.4, 0.22), (8.93, 0.12)]
    ring = np.zeros(n(dur))
    for k, (r, a) in enumerate(partials):
        ring += sine(f0 * r, dur, phase=k * 0.7) * a * expdec(dur, 0.09 / (1 + k * 0.6))
    strike = bp(noise(0.04), 2000, 9000) * expdec(0.04, 0.008) * 0.8
    knock = sine(geo(0.08, 320, 180), 0.08) * expdec(0.08, 0.02) * 0.5
    return reverb(mix(ring, strike, knock), 0.18, 0.6, 0.05)


def brick_hit(variant: int) -> np.ndarray:
    dur = 0.22
    f0 = 2400.0 * (1.0 + 0.12 * variant)
    glass = np.zeros(n(dur))
    for k, r in enumerate((1.0, 1.47, 2.09, 3.31)):
        glass += sine(f0 * r, dur, phase=k) * (0.9 ** k) * expdec(dur, 0.05 / (1 + k))
    crack = hp(noise(0.03), 4000) * expdec(0.03, 0.006)
    return reverb(mix(glass * 0.7, crack), 0.15, 0.55, 0.05)


def brick_shatter() -> np.ndarray:
    dur = 0.55
    burst = bp(noise(dur), 1800, 9000) * expdec(dur, 0.09)
    debris = np.zeros(n(dur))
    for _ in range(14):
        st = rng.uniform(0.03, 0.4)
        f = rng.uniform(2200, 6500)
        seg = sine(f, 0.06) * expdec(0.06, 0.012) * rng.uniform(0.2, 0.5)
        s = n(st)
        debris[s:s + seg.size] += seg[: max(0, min(seg.size, debris.size - s))]
    low = sine(geo(0.2, 260, 90), 0.2) * expdec(0.2, 0.05) * 0.8
    return reverb(mix(burst, debris, low), 0.22, 0.7, 0.15)


def blast() -> np.ndarray:
    dur = 0.6
    whoosh = sweep_lp(noise(dur), 6000, 300) * adsr(dur, 0.01, 0.15, 0.2, 0.3)
    boom = sine(geo(dur, 140, 38), dur) * expdec(dur, 0.16)
    punch = sine(geo(0.08, 900, 120), 0.08) * expdec(0.08, 0.02) * 0.7
    tear = bp(noise(0.12), 600, 2400) * expdec(0.12, 0.03) * 0.6
    return soft_clip(reverb(mix(whoosh * 0.8, boom, punch, tear), 0.2, 0.65, 0.1), 1.6)


def blast_ready() -> np.ndarray:
    dur = 0.07
    tick = sine(geo(dur, 2600, 1900), dur) * expdec(dur, 0.012)
    return mix(tick, hp(noise(0.01), 5000) * expdec(0.01, 0.002) * 0.5)


def super_hit() -> np.ndarray:
    dur = 1.8
    sub = sine(geo(dur, 110, 32), dur) * adsr(dur, 0.005, 0.6, 0.35, 0.8)
    shimmer = np.zeros(n(dur))
    for k, f in enumerate((1760, 2637, 3520, 4400, 5274)):
        shimmer += sine(f * (1 + 0.002 * k), dur, phase=k) * adsr(dur, 0.15 + 0.05 * k, 0.4, 0.3, 0.9) * (0.8 ** k)
    shimmer = shimmer * (0.6 + 0.4 * sine(5.5, dur))
    air = sweep_lp(noise(dur), 8000, 500) * adsr(dur, 0.02, 0.5, 0.2, 0.9) * 0.6
    smack = sine(geo(0.1, 1200, 90), 0.1) * expdec(0.1, 0.03)
    return soft_clip(reverb(mix(sub, shimmer * 0.35, air, smack), 0.3, 0.8, 0.3), 1.4)


def parry() -> np.ndarray:
    dur = 0.5
    crack = hp(noise(0.02), 3500) * expdec(0.02, 0.004)
    glass = np.zeros(n(0.12))
    for k, f in enumerate((3200, 4700, 6100)):
        glass += sine(f, 0.12, phase=k) * expdec(0.12, 0.02) * (0.7 ** k)
    chime = np.zeros(n(dur))
    for k, f in enumerate((1318.5, 1975.5, 2637.0, 3951.0)):
        chime += sine(f, dur, phase=k * 0.4) * adsr(dur, 0.004, 0.2, 0.3, 0.25) * (0.75 ** k)
    return reverb(mix(crack, glass, chime * 0.7), 0.3, 0.75, 0.2)


def suck_loop() -> np.ndarray:
    dur = 2.4
    base = lp(noise(dur), 1100)
    breath = base * (0.7 + 0.3 * sine(1.7, dur)) * (0.85 + 0.15 * sine(0.43, dur, 1.0))
    tone = sine(75 + 6 * sine(0.8, dur), dur) * 0.35
    whistle = bp(noise(dur), 1800, 2600) * 0.25 * (0.6 + 0.4 * sine(2.3, dur, 2.0))
    return loopify(hp(mix(breath, tone, whistle), 60), 0.4)


def stream_loop() -> np.ndarray:
    dur = 2.4
    jet = bp(noise(dur), 900, 7000) * (0.8 + 0.2 * sine(3.1, dur))
    hiss = hp(noise(dur), 5000) * 0.35 * (0.7 + 0.3 * sine(0.9, dur, 0.4))
    core = lp(noise(dur), 400) * 0.5
    return loopify(mix(jet, hiss, core), 0.4)


def hydro_rush_loop() -> np.ndarray:
    dur = 2.4
    water = bp(brown(dur, 0.99), 250, 3200)
    gurgle = np.zeros(n(dur))
    for _ in range(26):
        st = rng.uniform(0.0, dur - 0.06)
        f = rng.uniform(500, 1500)
        seg = sine(geo(0.05, f, f * 1.8), 0.05) * expdec(0.05, 0.012) * rng.uniform(0.15, 0.35)
        s = n(st)
        gurgle[s:s + seg.size] += seg[: min(seg.size, gurgle.size - s)]
    return loopify(mix(water, gurgle, hp(noise(dur), 4000) * 0.15), 0.4)


def drone_loop(turbulent: bool) -> np.ndarray:
    dur = 20.0
    b = brown(dur, 0.998)
    lfo1 = sine(0.05, dur)
    lfo2 = sine(0.083, dur, 1.3)
    if turbulent:
        lo = bp(b, 40, 220)
        mid = bp(noise(dur), 300, 1400) * (0.5 + 0.5 * lfo1) * 0.35
        hi = bp(noise(dur), 1500, 4500) * (0.5 + 0.5 * lfo2) * 0.25
        hum = sine(55 + 4 * lfo1, dur) * 0.35 + sine(82.4 + 3 * lfo2, dur) * 0.25
        x = mix(lo, mid, hi, hum)
    else:
        lo = bp(b, 30, 160)
        mid = bp(b, 200, 700) * (0.5 + 0.5 * lfo1) * 0.5
        hum = sine(41.2 + 1.5 * lfo1, dur) * 0.4 + sine(61.7, dur) * 0.15
        x = mix(lo, mid, hum)
    x = x * (0.85 + 0.15 * sine(0.031, dur, 0.5))
    return loopify(x, 1.5)


def heartbeat_loop() -> np.ndarray:
    dur = 1.0
    x = np.zeros(n(dur))

    def thump(at: float, gain: float, f: float):
        seg = mix(sine(geo(0.22, f, f * 0.45), 0.22) * expdec(0.22, 0.05) * gain, lp(noise(0.05), 200) * expdec(0.05, 0.01) * gain * 0.4)
        s = n(at)
        x[s:s + seg.size] += seg[: min(seg.size, x.size - s)]

    thump(0.0, 1.0, 95.0)
    thump(0.18, 0.7, 80.0)
    return loopify(soft_clip(x, 1.3), 0.05)


def chord(freqs, dur: float, bright: float = 1.0, attack: float = 0.01, release: float = 0.4, detune: float = 0.003) -> np.ndarray:
    out = np.zeros(n(dur))
    for k, f in enumerate(freqs):
        env = adsr(dur, attack, dur * 0.5, 0.4, release)
        v = sine(f, dur, phase=k * 0.3) + sine(f * (1 + detune), dur, phase=k * 0.9) * 0.6
        v += sine(f * 2, dur, phase=k) * 0.35 * bright + sine(f * 3, dur) * 0.15 * bright
        v += saw(f * 0.5, dur) * 0.12
        out += v * env * (0.9 ** k)
    return lp(out, 4500 + 3500 * bright)


def goal_p1() -> np.ndarray:
    dur = 1.0
    arp = np.zeros(n(dur))
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        seg = chord([f, f * 2], 0.7, 1.0, 0.004, 0.35) * 0.6
        s = n(0.06 * i)
        arp[s:s + seg.size] += seg[: min(seg.size, arp.size - s)]
    pad_ = chord([261.63, 329.63, 392.0], dur, 0.8, 0.02, 0.5) * 0.5
    sparkle = hp(noise(0.3), 6000) * expdec(0.3, 0.05) * 0.25
    return stereo(mix(arp, pad_, sparkle), 0.7, 0.28)


def goal_p2() -> np.ndarray:
    dur = 1.0
    stack = chord([220.0, 261.63, 329.63, 415.3], dur, 0.5, 0.015, 0.45) * 0.7
    low = sine(geo(dur, 110, 55), dur) * adsr(dur, 0.01, 0.3, 0.5, 0.5) * 0.8
    grit = bp(noise(dur), 200, 900) * adsr(dur, 0.01, 0.2, 0.2, 0.5) * 0.3
    return stereo(mix(stack, low, grit), 0.9, 0.32)


def fanfare(notes, step: float, dur: float, bright: float = 1.0) -> np.ndarray:
    x = np.zeros(n(dur))
    for i, f in enumerate(notes):
        seg = chord([f, f * 1.5, f * 2], min(step * 2.2, dur - step * i), bright, 0.006, 0.3) * 0.7
        s = n(step * i)
        x[s:s + seg.size] += seg[: min(seg.size, x.size - s)]
    return x


def set_won() -> np.ndarray:
    dur = 1.5
    line = fanfare((392.0, 523.25, 659.25, 783.99), 0.16, dur, 1.0)
    hit = sine(geo(0.25, 200, 70), 0.25) * expdec(0.25, 0.07)
    line = mix(line, pad(hit, 0.0))
    return stereo(line, 0.8, 0.3)


def match_won() -> np.ndarray:
    dur = 3.0
    line = fanfare((523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5), 0.22, dur, 1.0)
    final = chord([523.25, 659.25, 783.99, 1046.5, 1318.5], 1.7, 1.0, 0.02, 0.9)
    fin = np.zeros(n(dur))
    s = n(1.3)
    fin[s:s + final.size] += final[: min(final.size, fin.size - s)]
    sub = sine(geo(0.5, 160, 50), 0.5) * expdec(0.5, 0.15)
    tail = np.zeros(n(dur))
    tail[s:s + sub.size] += sub[: min(sub.size, tail.size - s)]
    glitter = hp(noise(1.5), 7000) * adsr(1.5, 0.3, 0.6, 0.3, 0.5) * 0.15
    gl = np.zeros(n(dur))
    gl[s:s + glitter.size] += glitter[: min(glitter.size, gl.size - s)]
    return stereo(mix(line, fin * 0.9, tail, gl), 1.0, 0.35)


def match_lost() -> np.ndarray:
    dur = 2.0
    line = fanfare((392.0, 349.23, 311.13, 261.63), 0.34, dur, 0.4)
    drop = sine(geo(dur, 130, 40), dur) * adsr(dur, 0.05, 0.8, 0.4, 0.8) * 0.8
    murk = lp(noise(dur), 400) * adsr(dur, 0.2, 0.8, 0.3, 0.8) * 0.3
    return stereo(mix(line, drop, murk), 1.2, 0.4)


def rally_tier(tier: int) -> np.ndarray:
    dur = 0.45
    semis = tier
    base = 659.25 * (2 ** (semis / 12.0))
    a = chord([base, base * 2], 0.3, 1.0, 0.004, 0.2)
    b = chord([base * 1.5, base * 3], 0.32, 1.0, 0.004, 0.22)
    x = np.zeros(n(dur))
    x[: a.size] += a
    s = n(0.11)
    x[s:s + b.size] += b[: min(b.size, x.size - s)]
    tick = hp(noise(0.01), 6000) * expdec(0.01, 0.002) * 0.4
    return reverb(mix(x * 0.7, tick), 0.25, 0.7, 0.15)


def overdrive_riser() -> np.ndarray:
    dur = 0.8
    riser = sweep_lp(hp(noise(dur), 200), 400, 9000) * lin(dur, 0.2, 1.0)
    tone = sine(geo(dur, 180, 1400), dur) * lin(dur, 0.1, 0.8) * 0.5
    tone = tone * (0.6 + 0.4 * sine(lin(dur, 6, 40), dur))
    hit = mix(sine(geo(0.22, 600, 60), 0.22) * expdec(0.22, 0.06), bp(noise(0.1), 1000, 5000) * expdec(0.1, 0.02) * 0.6)
    x = np.zeros(n(dur + 0.25))
    x[: riser.size] += riser * 0.7
    x[: tone.size] += tone
    s = n(dur - 0.02)
    x[s:s + hit.size] += hit[: min(hit.size, x.size - s)]
    return soft_clip(reverb(x, 0.2, 0.7, 0.1), 1.5)


def lock_enter() -> np.ndarray:
    dur = 1.1
    sub = sine(geo(dur, 220, 30), dur) * adsr(dur, 0.004, 0.4, 0.4, 0.5)
    slam = lp(noise(0.12), 300) * expdec(0.12, 0.03) * 0.8
    ring = sine(1760, dur) * adsr(dur, 0.01, 0.5, 0.1, 0.5) * 0.12
    return soft_clip(reverb(mix(sub, slam, ring), 0.25, 0.8, 0.2), 1.4)


def powerup_spawn() -> np.ndarray:
    dur = 0.7
    x = np.zeros(n(dur))
    for k in range(6):
        f = 880 * (2 ** (k * 2 / 12.0))
        seg = sine(f, 0.35, phase=k) * adsr(0.35, 0.004, 0.1, 0.4, 0.2) * (0.85 ** k)
        s = n(0.07 * k)
        x[s:s + seg.size] += seg[: min(seg.size, x.size - s)]
    shimmer = bp(noise(dur), 4000, 10000) * lin(dur, 0.0, 1.0) * adsr(dur, 0.1, 0.2, 0.5, 0.25) * 0.25
    return reverb(mix(x * 0.6, shimmer), 0.3, 0.75, 0.2)


def powerup_collect() -> np.ndarray:
    dur = 0.5
    pop = mix(sine(geo(0.07, 900, 300), 0.07) * expdec(0.07, 0.015), lp(noise(0.03), 1500) * expdec(0.03, 0.006) * 0.6)
    sparkle = np.zeros(n(dur))
    for k, f in enumerate((2093, 2637, 3136, 4186)):
        seg = sine(f, 0.3, phase=k) * adsr(0.3, 0.004, 0.08, 0.3, 0.15) * (0.8 ** k)
        s = n(0.03 + 0.04 * k)
        sparkle[s:s + seg.size] += seg[: min(seg.size, sparkle.size - s)]
    return reverb(mix(pop, sparkle * 0.5), 0.25, 0.7, 0.15)


def powerup_expire() -> np.ndarray:
    dur = 0.6
    fizz = bp(noise(dur), 1500, 6000) * adsr(dur, 0.01, 0.2, 0.5, 0.35) * 0.5
    tone = sine(geo(dur, 1200, 300), dur) * adsr(dur, 0.01, 0.3, 0.3, 0.3) * 0.5
    tone = tone * (0.5 + 0.5 * sine(18, dur))
    return reverb(mix(fizz, tone), 0.2, 0.6, 0.1)


def stun() -> np.ndarray:
    dur = 0.7
    zap = np.sign(sine(geo(0.12, 4000, 900), 0.12)) * expdec(0.12, 0.04) * 0.6
    zap += hp(noise(0.12), 3000) * expdec(0.12, 0.03)
    wob = sine(400 + 180 * sine(9.0, dur), dur) * adsr(dur, 0.02, 0.3, 0.4, 0.35) * 0.5
    wob += sine(200 + 90 * sine(9.0, dur, 1.0), dur) * adsr(dur, 0.02, 0.3, 0.4, 0.35) * 0.3
    crackle = hp(noise(dur), 4000) * (rng.random(n(dur)) > 0.97) * adsr(dur, 0.01, 0.4, 0.2, 0.3) * 0.5
    return soft_clip(reverb(mix(zap, wob, crackle), 0.15, 0.6, 0.1), 1.6)


def stun_bolt_fire() -> np.ndarray:
    dur = 0.22
    laser = sine(geo(dur, 2600, 500), dur) * expdec(dur, 0.06)
    laser += saw(geo(dur, 1300, 250), dur) * expdec(dur, 0.05) * 0.4
    click = hp(noise(0.01), 5000) * expdec(0.01, 0.002) * 0.6
    return soft_clip(mix(laser, click), 1.4)


def multiball_split() -> np.ndarray:
    dur = 0.6
    x = np.zeros(n(dur))
    for k in range(3):
        f = rng.uniform(600, 900)
        splish = sine(geo(0.12, f, f * 2.2), 0.12) * expdec(0.12, 0.03) * 0.7
        splish += bp(noise(0.12), 1500, 6000) * expdec(0.12, 0.025)
        s = n(0.14 * k)
        x[s:s + splish.size] += splish[: min(splish.size, x.size - s)]
    return reverb(x, 0.25, 0.65, 0.15)


def hazard_vortex() -> np.ndarray:
    dur = 1.5
    swirl = sweep_lp(noise(dur), 300, 4000) * adsr(dur, 0.2, 0.5, 0.6, 0.6)
    swirl = swirl * (0.6 + 0.4 * sine(geo(dur, 2.0, 9.0), dur))
    tone = sine(geo(dur, 90, 260), dur) * adsr(dur, 0.2, 0.5, 0.5, 0.6) * 0.5
    return reverb(mix(swirl * 0.8, tone), 0.3, 0.75, 0.3)


def stage_intro() -> np.ndarray:
    dur = 1.5
    hit = mix(sine(geo(0.3, 300, 45), 0.3) * expdec(0.3, 0.09), lp(noise(0.15), 500) * expdec(0.15, 0.04) * 0.8)
    swell = chord([110.0, 164.81, 220.0, 329.63], dur, 0.6, 0.35, 0.5) * 0.5
    air = sweep_lp(noise(dur), 800, 6000) * adsr(dur, 0.6, 0.3, 0.5, 0.5) * 0.3
    return stereo(soft_clip(mix(hit, swell, air), 1.3), 1.0, 0.35)


def stage_complete() -> np.ndarray:
    dur = 1.6
    line = fanfare((440.0, 554.37, 659.25, 880.0, 1108.7), 0.14, dur, 1.0)
    rise = sweep_lp(noise(0.8), 500, 8000) * lin(0.8, 0.0, 1.0) * 0.3
    return stereo(mix(line, rise), 0.8, 0.3)


def ui_navigate() -> np.ndarray:
    dur = 0.05
    return mix(sine(geo(dur, 1400, 1100), dur) * expdec(dur, 0.01), hp(noise(0.008), 4000) * expdec(0.008, 0.002) * 0.5)


def ui_confirm() -> np.ndarray:
    dur = 0.3
    a = sine(1318.5, 0.12) * adsr(0.12, 0.003, 0.05, 0.4, 0.05)
    b = sine(1975.5, 0.25) * adsr(0.25, 0.003, 0.1, 0.3, 0.12)
    x = np.zeros(n(dur))
    x[: a.size] += a
    s = n(0.07)
    x[s:s + b.size] += b[: min(b.size, x.size - s)]
    return reverb(x, 0.2, 0.6, 0.05)


def ui_back() -> np.ndarray:
    dur = 0.12
    return mix(sine(geo(dur, 520, 380), dur) * expdec(dur, 0.035), lp(noise(0.02), 1200) * expdec(0.02, 0.005) * 0.4)


def menu_open() -> np.ndarray:
    dur = 0.45
    wh = sweep_lp(noise(dur), 600, 5000) * adsr(dur, 0.12, 0.15, 0.3, 0.18) * 0.7
    tone = sine(geo(dur, 300, 700), dur) * adsr(dur, 0.1, 0.2, 0.2, 0.15) * 0.3
    return reverb(mix(wh, tone), 0.25, 0.65, 0.1)


def pause_thump() -> np.ndarray:
    dur = 0.25
    return lp(mix(sine(geo(dur, 180, 60), dur) * expdec(dur, 0.06), lp(noise(0.06), 400) * expdec(0.06, 0.015) * 0.5), 900)


def resume_thump() -> np.ndarray:
    dur = 0.25
    x = sine(geo(dur, 60, 180), dur) * np.exp(-(dur - t(dur)) / 0.06)
    x += lp(noise(dur), 600) * np.exp(-(dur - t(dur)) / 0.02) * 0.4
    return lp(x, 1200)


def countdown_tick() -> np.ndarray:
    dur = 0.09
    block = sine(geo(dur, 1900, 1500), dur) * expdec(dur, 0.012)
    block += sine(geo(dur, 780, 700), dur) * expdec(dur, 0.02) * 0.6
    return mix(block, lp(noise(0.01), 3000) * expdec(0.01, 0.003) * 0.5)


# ---------------------------------------------------------------- phase 2 designs
def blast_charge_loop() -> tuple[np.ndarray, int]:
    """Rising tension over 0.7 s, then a steady 0.35 s tail that loops while the
    button is held.  Code adds a pitch/volume ramp on top.  Returns (samples,
    loop_begin)."""
    rise = 0.7
    tail = 0.35
    f = geo(rise, 82.0, 165.0)
    body = saw(f, rise) * 0.6 + sine(f * 2.0, rise) * 0.3 + sine(f * 0.5, rise) * 0.4
    body = sweep_lp(body, 350.0, 3800.0) * (0.55 + 0.45 * sine(geo(rise, 7.0, 26.0), rise))
    air = sweep_lp(hp(noise(rise), 300), 500.0, 7000.0) * lin(rise, 0.05, 0.6)
    shimmer = sine(geo(rise, 1320.0, 2640.0), rise) * lin(rise, 0.0, 0.25) * (0.5 + 0.5 * sine(geo(rise, 9.0, 30.0), rise))
    rise_x = mix(body, air, shimmer) * adsr(rise, 0.03, 0.1, 1.0, 0.0)
    ft = 165.0
    tail_body = saw(ft, tail) * 0.6 + sine(ft * 2.0, tail) * 0.3 + sine(ft * 0.5, tail) * 0.4
    tail_body = lp(tail_body, 3800.0) * (0.55 + 0.45 * sine(26.0, tail))
    tail_air = lp(hp(noise(tail), 300) * 0.6, 7000.0)
    tail_sh = sine(2640.0, tail) * 0.25 * (0.5 + 0.5 * sine(30.0, tail))
    tail_x = loopify(mix(tail_body, tail_air, tail_sh), 0.06)
    # Short crossfade from the rise into the loop region so the hand-off is clean.
    xf = n(0.012)
    ramp = np.linspace(0.0, 1.0, xf)
    joined = np.concatenate([rise_x[:-xf], rise_x[-xf:] * (1.0 - ramp) + tail_x[:xf] * ramp, tail_x[xf:]])
    return soft_clip(joined, 1.4), rise_x.size - xf


def blast_charge_release(tier: int) -> np.ndarray:
    """Tiered boom: 1 = tight punch, 2 = punch + sub, 3 = full sub drop with tear."""
    dur = (0.45, 0.8, 1.2)[tier - 1]
    sub_hi = (150.0, 130.0, 120.0)[tier - 1]
    sub_lo = (55.0, 42.0, 32.0)[tier - 1]
    tau = (0.09, 0.18, 0.3)[tier - 1]
    punch = sine(geo(0.07, 1100.0, 140.0), 0.07) * expdec(0.07, 0.018) * 0.9
    boom = sine(geo(dur, sub_hi, sub_lo), dur) * expdec(dur, tau)
    whoosh = sweep_lp(noise(dur), 7000.0, 250.0) * adsr(dur, 0.005, dur * 0.3, 0.15, dur * 0.4) * (0.5 + 0.2 * tier)
    parts = [punch, boom, whoosh]
    if tier >= 2:
        tear = bp(noise(0.16), 500.0, 3000.0) * expdec(0.16, 0.035) * 0.7
        parts.append(tear)
    if tier >= 3:
        crackle = hp(noise(0.6), 3000.0) * (rng.random(n(0.6)) > 0.96) * expdec(0.6, 0.18) * 0.5
        drop = sine(geo(0.5, 320.0, 60.0), 0.5) * expdec(0.5, 0.09) * 0.5
        parts += [crackle, drop]
    return soft_clip(reverb(mix(*parts), 0.18 + 0.05 * tier, 0.7, 0.1 + 0.05 * tier), 1.4 + 0.2 * tier)


def suck_capture() -> np.ndarray:
    """Reverse swell into a "grab" whoomp."""
    pre = 0.11
    swell = lp(noise(pre), 900.0) * np.exp(-(pre - t(pre)) / 0.03) * 0.7
    swell += sine(geo(pre, 180.0, 420.0), pre) * np.exp(-(pre - t(pre)) / 0.04) * 0.5
    dur = 0.32
    whoomp = sine(geo(dur, 380.0, 62.0), dur) * expdec(dur, 0.07)
    thud = lp(noise(0.06), 500.0) * expdec(0.06, 0.012) * 0.6
    snap = hp(noise(0.008), 4000.0) * expdec(0.008, 0.002) * 0.4
    x = np.concatenate([swell, soft_clip(mix(whoomp, thud, snap), 1.5)])
    return reverb(x, 0.15, 0.6, 0.08)


def orbit_loop() -> np.ndarray:
    """Whirling capture bed; code raises pitch the longer the ball is held."""
    dur = 1.2
    vib = 1.0 + 0.012 * sine(5.8, dur)
    tone = sine(196.0 * vib, dur) * 0.5 + sine(392.0 * vib, dur, 0.7) * 0.25 + sine(588.0 * vib, dur, 1.3) * 0.12
    whirl = bp(noise(dur), 700.0, 2600.0) * (0.35 + 0.65 * (0.5 + 0.5 * sine(4.0, dur))) * 0.6
    ring = sine(1568.0, dur) * 0.08 * (0.5 + 0.5 * sine(8.0, dur, 0.5))
    breath = lp(noise(dur), 300.0) * 0.3 * (0.7 + 0.3 * sine(2.0, dur))
    return loopify(hp(mix(tone, whirl, ring, breath), 50.0), 0.25)


def slingshot_release() -> np.ndarray:
    """Whip crack into a doppler-ish whoosh that drops in pitch as it recedes."""
    crack = hp(noise(0.012), 6000.0) * expdec(0.012, 0.0025)
    snap = sine(geo(0.05, 3200.0, 420.0), 0.05) * expdec(0.05, 0.012) * 0.9
    dur = 0.5
    wh = sweep_lp(hp(noise(dur), 250.0), 5000.0, 500.0) * adsr(dur, 0.006, 0.12, 0.35, 0.3)
    wh = wh * (0.7 + 0.3 * sine(geo(dur, 40.0, 12.0), dur))
    dop = sine(geo(dur, 900.0, 260.0), dur) * adsr(dur, 0.01, 0.15, 0.3, 0.3) * 0.35
    return soft_clip(reverb(mix(crack, snap, wh * 0.9, dop), 0.16, 0.6, 0.1), 1.5)


def goal_shatter() -> np.ndarray:
    """Glass shatter into a sub boom (1.2 s, stereo)."""
    dur = 1.2
    burst = bp(noise(0.5), 2000.0, 11000.0) * expdec(0.5, 0.07)
    debris = np.zeros(n(dur))
    for _ in range(28):
        st = rng.uniform(0.02, 0.75)
        f = rng.uniform(2400.0, 8200.0)
        seg = sine(geo(0.09, f, f * 0.92), 0.09) * expdec(0.09, 0.02) * rng.uniform(0.15, 0.45)
        s0 = n(st)
        debris[s0:s0 + seg.size] += seg[: max(0, min(seg.size, debris.size - s0))]
    boom = np.zeros(n(dur))
    b = sine(geo(0.9, 130.0, 34.0), 0.9) * expdec(0.9, 0.28)
    b = mix(b, lp(noise(0.15), 350.0) * expdec(0.15, 0.04) * 0.7)
    s0 = n(0.05)
    boom[s0:s0 + b.size] += b[: min(b.size, boom.size - s0)]
    crunch = bp(noise(0.25), 300.0, 1800.0) * expdec(0.25, 0.05) * 0.5
    return stereo(soft_clip(mix(burst * 0.8, debris * 0.7, boom, crunch), 1.5), 0.9, 0.3)


def brick_shard_tinkle() -> np.ndarray:
    """Falling glass fragments."""
    dur = 0.55
    x = np.zeros(n(dur))
    for k in range(12):
        st = 0.01 + 0.035 * k + rng.uniform(0.0, 0.02)
        f = rng.uniform(3200.0, 8500.0)
        seg = sine(geo(0.08, f, f * 0.96), 0.08) * expdec(0.08, 0.015) * rng.uniform(0.25, 0.6) * (0.93 ** k)
        s0 = n(st)
        x[s0:s0 + seg.size] += seg[: max(0, min(seg.size, x.size - s0))]
    dust = hp(noise(dur), 6000.0) * expdec(dur, 0.12) * 0.12
    return reverb(mix(x, dust), 0.22, 0.65, 0.1)


def serve_beat(step: int) -> np.ndarray:
    """Three-note READY pulse; step 3 rings longer and brighter."""
    f = (523.25, 659.25, 783.99)[step - 1]
    dur = 0.16 if step < 3 else 0.32
    x = sine(f, dur) * adsr(dur, 0.004, dur * 0.4, 0.35, dur * 0.4)
    x += sine(f * 2.0, dur, 0.5) * adsr(dur, 0.004, dur * 0.3, 0.25, dur * 0.4) * (0.3 + 0.15 * step)
    x += sine(f * 3.0, dur, 1.0) * adsr(dur, 0.004, dur * 0.25, 0.15, dur * 0.4) * 0.1 * step
    click = hp(noise(0.006), 5000.0) * expdec(0.006, 0.0015) * 0.35
    return reverb(mix(x, click), 0.18 + 0.06 * step, 0.6, 0.08)


def serve_warning() -> np.ndarray:
    """Urgent double tick."""
    def tick(f: float) -> np.ndarray:
        d = 0.045
        v = np.sign(sine(f, d)) * 0.5 + sine(f * 2.0, d) * 0.4
        return lp(v, 6000.0) * expdec(d, 0.012)
    a = tick(1750.0)
    b = tick(2000.0)
    x = np.zeros(n(0.22))
    x[: a.size] += a
    s0 = n(0.095)
    x[s0:s0 + b.size] += b[: min(b.size, x.size - s0)]
    return reverb(x, 0.12, 0.5, 0.05)


def lock_pulse() -> np.ndarray:
    """Soft sonar ping for the lost-ball pulse ring."""
    dur = 0.6
    x = sine(880.0, dur) * adsr(dur, 0.006, 0.25, 0.25, 0.3)
    x += sine(1320.0, dur, 0.6) * adsr(dur, 0.006, 0.2, 0.15, 0.3) * 0.35
    x += sine(440.0, dur, 1.1) * adsr(dur, 0.01, 0.3, 0.3, 0.3) * 0.3
    return lp(reverb(x, 0.4, 0.82, 0.35), 5000.0)


def perfect_star() -> np.ndarray:
    """Bright crystalline chime with a sparkle tail."""
    dur = 0.75
    chime = np.zeros(n(dur))
    for k, f in enumerate((2093.0, 3135.96, 4186.0, 5274.0, 6271.9)):
        chime += sine(f * (1.0 + 0.0015 * k), dur, phase=k * 0.5) * adsr(dur, 0.003 + 0.01 * k, 0.25, 0.25, 0.35) * (0.78 ** k)
    chime = chime * (0.75 + 0.25 * sine(11.0, dur, 0.3))
    strike = hp(noise(0.015), 4000.0) * expdec(0.015, 0.003) * 0.6
    sparkle = hp(noise(dur), 8000.0) * (rng.random(n(dur)) > 0.9) * adsr(dur, 0.02, 0.3, 0.3, 0.3) * 0.35
    body = sine(1046.5, 0.3) * adsr(0.3, 0.003, 0.1, 0.3, 0.15) * 0.4
    return reverb(mix(chime * 0.7, strike, sparkle, body), 0.32, 0.78, 0.25)


def wall_ripple() -> np.ndarray:
    """Short watery slap layered under wall hits."""
    dur = 0.2
    slap = lp(brown(0.09, 0.98), 1400.0) * expdec(0.09, 0.02)
    wobble = bp(noise(dur), 400.0, 1800.0) * (0.5 + 0.5 * sine(geo(dur, 34.0, 18.0), dur)) * expdec(dur, 0.05) * 0.8
    plip = sine(geo(0.05, 950.0, 380.0), 0.05) * expdec(0.05, 0.012) * 0.7
    return reverb(mix(slap, wobble, plip), 0.15, 0.55, 0.06)


# ---------------------------------------------------------------- catalogue
def catalogue():
    """(name, generator, loop) in a fixed order; the RNG is seeded once."""
    items = []
    for i in range(3):
        items.append((f"paddle_hit_{i + 1}", lambda i=i: paddle_hit(i), False))
    for i in range(3):
        items.append((f"wall_hit_{i + 1}", lambda i=i: wall_hit(i), False))
    for i in range(2):
        items.append((f"brick_hit_{i + 1}", lambda i=i: brick_hit(i), False))
    items += [
        ("brick_shatter", brick_shatter, False),
        ("blast", blast, False),
        ("blast_ready", blast_ready, False),
        ("super", super_hit, False),
        ("parry", parry, False),
        ("suck_loop", suck_loop, True),
        ("stream_loop", stream_loop, True),
        ("hydro_rush_loop", hydro_rush_loop, True),
        ("drone_calm_loop", lambda: drone_loop(False), True),
        ("drone_turbulent_loop", lambda: drone_loop(True), True),
        ("heartbeat_loop", heartbeat_loop, True),
        ("goal_p1", goal_p1, False),
        ("goal_p2", goal_p2, False),
        ("set_won", set_won, False),
        ("match_won", match_won, False),
        ("match_lost", match_lost, False),
    ]
    for i in range(4):
        items.append((f"rally_tier_{i + 1}", lambda i=i: rally_tier(i + 1), False))
    items += [
        ("overdrive_riser", overdrive_riser, False),
        ("lock_enter", lock_enter, False),
        ("powerup_spawn", powerup_spawn, False),
        ("powerup_collect", powerup_collect, False),
        ("powerup_expire", powerup_expire, False),
        ("stun", stun, False),
        ("stun_bolt_fire", stun_bolt_fire, False),
        ("multiball_split", multiball_split, False),
        ("hazard_vortex", hazard_vortex, False),
        ("stage_intro", stage_intro, False),
        ("stage_complete", stage_complete, False),
        ("ui_navigate", ui_navigate, False),
        ("ui_confirm", ui_confirm, False),
        ("ui_back", ui_back, False),
        ("menu_open", menu_open, False),
        ("pause", pause_thump, False),
        ("resume", resume_thump, False),
        ("countdown_tick", countdown_tick, False),
        # Phase 2 (signature moments).
        ("blast_charge_loop", blast_charge_loop, True),
        ("blast_charge_release_1", lambda: blast_charge_release(1), False),
        ("blast_charge_release_2", lambda: blast_charge_release(2), False),
        ("blast_charge_release_3", lambda: blast_charge_release(3), False),
        ("suck_capture", suck_capture, False),
        ("orbit_loop", orbit_loop, True),
        ("slingshot_release", slingshot_release, False),
        ("goal_shatter", goal_shatter, False),
        ("brick_shard_tinkle", brick_shard_tinkle, False),
        ("serve_beat_1", lambda: serve_beat(1), False),
        ("serve_beat_2", lambda: serve_beat(2), False),
        ("serve_beat_3", lambda: serve_beat(3), False),
        ("serve_warning", serve_warning, False),
        ("lock_pulse", lock_pulse, False),
        ("perfect_star", perfect_star, False),
        ("wall_ripple", wall_ripple, False),
    ]
    return items


def main(argv) -> int:
    items = catalogue()
    if "--list" in argv:
        for name, _, loop in items:
            print(name + (" (loop)" if loop else ""))
        return 0
    only = [a for a in argv if not a.startswith("--")]
    for name, gen, loop in items:
        if only and name not in only:
            continue
        out = gen()
        loop_begin = 0
        if isinstance(out, tuple):
            out, loop_begin = out
        write_wav(name, out, loop, loop_begin)
        dur = out.shape[0] / SR
        extra = f"loop from {loop_begin / SR:.2f}s" if loop and loop_begin else ("loop" if loop else "")
        print(f"{name:24s} {dur:5.2f}s {extra}")
    print(f"wrote {len(only) if only else len(items)} files to {os.path.normpath(OUT_DIR)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
