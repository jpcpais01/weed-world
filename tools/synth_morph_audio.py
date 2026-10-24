#!/usr/bin/env python3
"""Synthesises the sounds of a Keling turning into another, from scratch so
they are original and free to ship. Writes Ogg Vorbis to assets/audio/morph/:

  morph_rise   the magic gathering: a soft swell, then a shimmering sweep
               rising with the glowing cut, and a twinkling climb of bells
               (pentatonic, so it never clashes with the music)
  morph_bloom  the reveal: a warm bell chord blooming over a soft low thump,
               and a tail of sparkles drifting down

    python3 tools/synth_morph_audio.py

Needs numpy, scipy and ffmpeg (with libvorbis) on the PATH.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "morph")
rng = np.random.default_rng(1024)

# Matches KelingMorph: the sweep runs 0.5 .. 1.3 s into morph_rise.
SWEEP = (0.5, 1.3)


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def bell(midi, seconds, decay=6.0, bright=0.3, detune=0.0):
    t = t_axis(seconds)
    f = hz(midi) * (1.0 + detune)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t * decay)
    x += bright * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * decay * 2.2)
    x += bright * 0.45 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * decay * 3.5)
    return x * np.minimum(1.0, t / 0.003)


def place(dst, src, at):
    i = int(at * SR)
    j = min(len(dst), i + len(src))
    dst[i:j] += src[: j - i]


def band_sweep(seconds, f0, f1, chunks=40, q=0.35):
    """Noise through a band that glides from f0 to f1 (log), chunk by chunk."""
    n = rng.normal(0, 1, int(seconds * SR))
    x = np.zeros_like(n)
    edges = np.linspace(0, len(n), chunks + 1).astype(int)
    for k in range(chunks):
        a, b = edges[k], edges[k + 1]
        fc = f0 * (f1 / f0) ** (k / (chunks - 1))
        sos = signal.butter(2, [fc * (1 - q), min(fc * (1 + q), SR * 0.45)], btype="band", fs=SR, output="sos")
        x[a:b] = signal.sosfilt(sos, n[max(0, a - 600):b])[-(b - a):]
    return x


def rise():
    total = 1.45
    x = np.zeros(int(total * SR))
    t = t_axis(total)
    # Gather: a breathy swell with a low hum underneath.
    swell = band_sweep(0.6, 300.0, 900.0, 16, 0.5) * np.sin(np.pi * np.clip(t_axis(0.6) / 0.6, 0, 1)) ** 2 * 0.5
    place(x, swell, 0.0)
    hum = np.sin(2 * np.pi * hz(50) * t) * 0.18 + np.sin(2 * np.pi * hz(57) * t) * 0.1
    hum *= np.clip(t / 0.4, 0, 1) * np.clip((total - t) / 0.3, 0, 1)
    x += hum
    # Sweep: shimmering noise rising with the cut, getting brighter.
    dur = SWEEP[1] - SWEEP[0] + 0.1
    sh = band_sweep(dur, 700.0, 6500.0, 36, 0.3)
    env = np.clip(t_axis(dur) / dur, 0, 1) ** 1.6
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 22.0 * t_axis(dur))
    place(x, sh * env * trem * 0.6, SWEEP[0])
    # Bells climbing up a pentatonic scale, speeding up as they go.
    scale = [69, 72, 74, 76, 79, 81, 84, 86, 88, 91]
    for k, m in enumerate(scale):
        u = k / (len(scale) - 1)
        at = 0.12 + (SWEEP[1] - 0.12) * (1 - (1 - u) ** 1.5)
        place(x, bell(m, 0.6, 7.0 + 4 * u, 0.3, rng.normal(0, 0.002)) * (0.22 + 0.25 * u), at)
    return x


def bloom():
    total = 1.6
    x = np.zeros(int(total * SR))
    t = t_axis(total)
    # Soft low thump (the landing), then the warm chord.
    thump_t = t_axis(0.5)
    f = 55 + 70 * np.exp(-thump_t * 18.0)
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-thump_t * 9.0) * np.minimum(1, thump_t / 0.004)
    place(x, thump * 0.9, 0.0)
    for k, m in enumerate([72, 76, 79, 84, 88]):
        place(x, bell(m, 1.4, 3.2 + k * 0.4, 0.22, rng.normal(0, 0.0015)) * (0.38 - 0.04 * k), 0.005 * k)
    # A bright whoosh of air as the petals burst out.
    air = band_sweep(0.5, 5000.0, 1800.0, 14, 0.4) * np.exp(-t_axis(0.5) * 7.0) * 0.5
    place(x, air, 0.0)
    # Sparkles drifting down, thinning out.
    for k in range(18):
        at = 0.06 + rng.uniform(0, 1) ** 1.8 * 1.2
        m = rng.choice([84, 86, 88, 91, 93, 96, 98])
        place(x, bell(m, 0.35, 16.0, 0.15) * rng.uniform(0.05, 0.14) * (1.0 - at / 1.4), at)
    return x


def write(name, x):
    x = x / max(1e-6, np.max(np.abs(x))) * 0.8
    fade = np.minimum(1.0, (len(x) - np.arange(len(x))) / (0.02 * SR))
    x = x * fade
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        wavfile.write(wav, SR, (x * 32767).astype(np.int16))
        out = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", out], check=True)
    print("wrote", os.path.relpath(out))


def main():
    write("morph_rise", rise())
    write("morph_bloom", bloom())


if __name__ == "__main__":
    main()
