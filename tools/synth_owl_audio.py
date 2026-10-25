#!/usr/bin/env python3
"""Synthesises Owl Flight's sounds from scratch, so all of them are original
and free to ship. Writes Ogg Vorbis files to assets/audio/gifts/.

    python3 tools/synth_owl_audio.py

Needs numpy, scipy and ffmpeg (with libvorbis), like synth_water_audio.py,
whose building blocks it borrows.

  owl_gather  the long breath out and up: air rushing, rising, a spiral of
              glassy chimes climbing with it as the owl burns into being
  owl_hoot    the spirit owl's call: a deep, breathy "hoo, hoo-hooo" with a
              ghostly octave shimmer above it, ringing off the valley
  owl_flap    one great wingbeat: a soft whump of air
  owl_wind    the ride (loops): wind streaming past, rising and falling
  owl_vanish  the owl melting away: a falling cascade of chimes, a last far
              hoot and a sigh of wind
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth_water_audio as w
from synth_water_audio import SR, bandpass, lowpass, highpass, env, place, reverb, finish, t_axis

w.OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "gifts")
rng = np.random.default_rng(2510)


def sweep_noise(seconds, f0, f1, q=0.6, curve=1.0):
    """Noise through a band that glides from f0 to f1."""
    from scipy import signal
    n = int(seconds * SR)
    f, tt, z = signal.stft(rng.standard_normal(n), SR, nperseg=1024)
    k = np.clip(tt / seconds, 0, 1) ** curve
    centre = f0 * (f1 / f0) ** k
    width = centre * q
    mask = np.exp(-0.5 * ((f[:, None] - centre[None, :]) / width[None, :]) ** 2)
    _, y = signal.istft(z * mask, SR, nperseg=1024)
    y = y[:n]
    return np.pad(y, (0, n - len(y))) / (np.max(np.abs(y)) or 1.0)


def chime(freq, seconds, decay):
    t = t_axis(seconds)
    att = np.minimum(t / 0.004, 1.0)
    x = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t / (decay * 0.4))
    return x * np.exp(-t / decay) * att


def hoo(seconds, f0, drop=0.12, breath=0.55):
    """One owl note: a soft, rounded tone that sags in pitch, and breath."""
    t = t_axis(seconds)
    f = f0 * (1.0 - drop * (t / seconds) ** 1.5) * (1 + 0.006 * np.sin(2 * np.pi * 5.5 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.28 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
    shape = np.sin(np.pi * np.clip(t / seconds, 0, 1)) ** 0.7
    air = bandpass(rng.standard_normal(len(t)), f0 * 1.5, f0 * 6.0) * breath
    return (tone + air) * shape


def gather():
    secs = 2.4
    n = int(secs * SR)
    x = np.zeros(n)
    t = t_axis(secs)
    swell = np.sin(np.pi * np.clip(t / secs, 0, 1)) ** 0.8
    place(x, sweep_noise(secs, 260, 2400, 0.7, 0.9) * swell * 0.8, 0.0)
    # A spiral of chimes climbing a pentatonic scale.
    scale = [523.3, 587.3, 659.3, 784.0, 880.0]
    k = 0
    at = 0.35
    while at < 2.05:
        f = scale[k % 5] * 2 ** (k // 5)
        place(x, chime(f, 1.6, 0.6) * 0.16 * (0.5 + 0.5 * at / 2.0), at)
        at += 0.11 - 0.025 * (at / 2.0)
        k += 1
    # The owl burns into being: a soft rising glow tone.
    tt = t_axis(1.4)
    glow = np.sin(2 * np.pi * np.cumsum(220 + 220 * tt / 1.4) / SR) * np.sin(np.pi * tt / 1.4) * 0.25
    place(x, glow, 0.6)
    return finish(reverb(x, 1.6, 0.35, 3500), -4.0, 0.02)


def hoot():
    secs = 2.6
    x = np.zeros(int(secs * SR))
    f0 = 330.0
    place(x, hoo(0.28, f0) * 0.8, 0.05)
    place(x, hoo(0.22, f0 * 0.98) * 0.7, 0.5)
    place(x, hoo(0.75, f0 * 1.02, 0.16) * 1.0, 0.82)
    # A ghostly octave above, sung softly with the long note.
    t = t_axis(0.8)
    ghost = np.sin(2 * np.pi * np.cumsum(f0 * 2.01 * (1 - 0.1 * t / 0.8)) / SR) * np.sin(np.pi * t / 0.8) ** 2
    place(x, ghost * 0.22, 0.84)
    return finish(reverb(x, 1.8, 0.42, 2800), -3.0, 0.02)


def flap():
    secs = 0.6
    n = int(secs * SR)
    noise = lowpass(bandpass(rng.standard_normal(n), 90, 900), 700)
    t = t_axis(secs)
    shape = np.clip(t / 0.09, 0, 1) ** 1.5 * np.exp(-np.clip(t - 0.09, 0, None) / 0.12)
    x = noise * shape
    t2 = t_axis(0.3)
    x[: len(t2)] += np.sin(2 * np.pi * np.cumsum(70 - 30 * t2 / 0.3) / SR) * np.exp(-t2 / 0.08) * 0.5
    return finish(x, -5.0, 0.01)


def wind():
    secs = 8.0
    n = int(secs * SR)
    base = bandpass(rng.standard_normal(n + SR), 180, 1400)
    hiss = highpass(rng.standard_normal(n + SR), 2500) * 0.12
    t = np.arange(n + SR) / SR
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * t / secs) * np.sin(2 * np.pi * t * 2 / secs + 1.0)
    whistle = np.sin(2 * np.pi * np.cumsum(820 + 90 * np.sin(2 * np.pi * t / secs * 3)) / SR) * 0.035 * gust ** 3
    x = (base * gust + hiss * gust + whistle)
    # Loop seamlessly: crossfade the extra second back over the start.
    fade = np.linspace(0, 1, SR)
    out = x[:n].copy()
    out[:SR] = x[:SR] * fade + x[n:n + SR] * (1 - fade)
    peak = np.max(np.abs(out)) or 1.0
    return out / peak * 10 ** (-6.0 / 20)


def vanish():
    secs = 3.2
    x = np.zeros(int(secs * SR))
    scale = [1568.0, 1318.5, 1174.7, 987.8, 880.0, 784.0, 659.3, 587.3, 523.3]
    at = 0.0
    for k, f in enumerate(scale):
        place(x, chime(f, 1.8, 0.7) * 0.18, at)
        at += 0.09 + 0.012 * k
    place(x, hoo(0.6, 300.0, 0.18, 0.8) * 0.32, 1.1)
    t = t_axis(2.6)
    sigh = sweep_noise(2.6, 1800, 300, 0.8) * np.sin(np.pi * t / 2.6) ** 1.5 * 0.4
    place(x, sigh, 0.2)
    return finish(reverb(x, 2.0, 0.45, 3000), -4.0, 0.02)


def main():
    w.save("owl_gather", gather())
    w.save("owl_hoot", hoot())
    w.save("owl_flap", flap())
    w.save("owl_wind", wind())
    w.save("owl_vanish", vanish())


if __name__ == "__main__":
    main()
