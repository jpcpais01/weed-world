#!/usr/bin/env python3
"""Synthesises the pause menu's little sounds, from scratch so they are
original and free to ship: a wooden tick when the selection moves, a soft
pluck when a value changes, a pop for switches, a leafy whoosh with a chime
when the menu opens (and a falling one when it closes), a two-note confirm
and a soft back. Writes Ogg Vorbis to assets/audio/ui/.

    python3 tools/synth_ui_audio.py

Needs numpy, scipy and ffmpeg (with libvorbis) on the PATH.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "ui")
rng = np.random.default_rng(2610)


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def bell(midi, seconds, decay=6.0, bright=0.3):
    t = t_axis(seconds)
    f = hz(midi)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t * decay)
    x += bright * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t * decay * 2.5)
    x += bright * 0.4 * np.sin(2 * np.pi * f * 5.98 * t) * np.exp(-t * decay * 4.0)
    return x * np.minimum(1.0, t / 0.002)


def wood(f, seconds=0.09, decay=55.0):
    t = t_axis(seconds)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t * decay)
    x += 0.5 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * decay * 1.8)
    noise = rng.normal(0, 1, len(t)) * np.exp(-t * 400.0) * 0.25
    sos = signal.butter(2, [f * 0.8, f * 4.0], btype="band", fs=SR, output="sos")
    return x + signal.sosfilt(sos, noise)


def whoosh(seconds, rising=True):
    t = t_axis(seconds)
    n = rng.normal(0, 1, len(t))
    x = np.zeros_like(n)
    # sweep a band through the noise in a few overlapping chunks
    chunks = 24
    edges = np.linspace(0, len(t), chunks + 1).astype(int)
    for k in range(chunks):
        a, b = edges[k], edges[k + 1]
        u = k / (chunks - 1)
        fc = 500 + 2600 * (u if rising else 1 - u)
        sos = signal.butter(2, [fc * 0.6, fc * 1.6], btype="band", fs=SR, output="sos")
        seg = signal.sosfilt(sos, n[max(0, a - 400):b])[-(b - a):]
        x[a:b] = seg
    shape = np.sin(np.pi * np.clip(t / seconds, 0, 1)) ** 1.5
    return x * shape * 0.35


def place(dst, src, at):
    i = int(at * SR)
    j = min(len(dst), i + len(src))
    dst[i:j] += src[: j - i]


def write(name, x):
    x = x / max(1e-6, np.max(np.abs(x))) * 0.8
    fade = np.minimum(1.0, (len(x) - np.arange(len(x))) / (0.01 * SR))
    x = x * fade
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        wavfile.write(wav, SR, (x * 32767).astype(np.int16))
        out = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", out], check=True)
    print("wrote", os.path.relpath(out))


def main():
    write("move", wood(1250.0, 0.08, 70.0))
    x = bell(81, 0.35, decay=14.0, bright=0.25) * 0.8
    place(x, wood(1700.0, 0.05, 90.0) * 0.4, 0.0)
    write("change", x)
    pop = t_axis(0.12)
    f = 420 + 900 * np.exp(-pop * 40.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    write("toggle", np.sin(ph) * np.exp(-pop * 32.0) * np.minimum(1, pop / 0.002))
    x = np.zeros(int(0.9 * SR))
    place(x, whoosh(0.5, True), 0.0)
    place(x, bell(86, 0.6, 7.0, 0.3) * 0.45, 0.16)
    place(x, bell(90, 0.6, 7.0, 0.3) * 0.35, 0.24)
    write("open", x)
    x = np.zeros(int(0.7 * SR))
    place(x, whoosh(0.45, False), 0.0)
    place(x, bell(83, 0.5, 9.0, 0.25) * 0.35, 0.1)
    write("close", x)
    x = np.zeros(int(0.6 * SR))
    place(x, bell(79, 0.5, 9.0, 0.3), 0.0)
    place(x, bell(86, 0.5, 8.0, 0.3), 0.07)
    write("confirm", x)
    x = np.zeros(int(0.5 * SR))
    place(x, bell(81, 0.4, 11.0, 0.2) * 0.8, 0.0)
    place(x, bell(76, 0.4, 11.0, 0.2) * 0.8, 0.06)
    write("back", x)


if __name__ == "__main__":
    main()
