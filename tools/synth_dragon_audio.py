#!/usr/bin/env python3
"""Synthesises Dragon Breath's sounds from scratch, so all of them are
original and free to ship. Writes Ogg Vorbis files to assets/audio/dragon/.

    python3 tools/synth_dragon_audio.py

Needs numpy, scipy and ffmpeg (with libvorbis), like synth_water_audio.py,
whose building blocks it borrows.

  charge  the long draw: air rushing in, rising, with a glassy shimmer that
          swells as the light gathers at the lips
  roar    the blast and the dragon's call: a burst of breath, a deep watery
          whale-song cry that rises and falls, and bubbles in its throat
  rush    the dragon swimming past: a river's rush through the air, swelling
          and ebbing with its strokes, drops pattering off it
  splash  the plunge: a deep whump, a roar of spray, a shower raining back
          down and a twinkle of glassy chimes as the rainbow comes out
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth_water_audio as w
from synth_water_audio import SR, bandpass, lowpass, highpass, env, place, drop, drops, wash, thump, reverb, finish, t_axis

w.OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "dragon")
rng = np.random.default_rng(1025)


def sweep_noise(seconds, f0, f1, q=0.6, curve=1.0):
    """Noise through a band that glides from f0 to f1 (shaped frame by frame)."""
    from scipy import signal
    n = int(seconds * SR)
    f, tt, z = signal.stft(rng.standard_normal(n), SR, nperseg=1024)
    k = np.clip(tt / seconds, 0, 1) ** curve
    centre = f0 * (f1 / f0) ** k
    width = centre * q
    mask = np.exp(-0.5 * ((f[:, None] - centre[None, :]) / width[None, :]) ** 2)
    _, y = signal.istft(z * mask, SR, nperseg=1024)
    return y[:n] / (np.max(np.abs(y)) or 1.0)


def glide_tone(seconds, freqs, times, partials=((1, 1.0), (2, 0.35), (3, 0.12)), vibrato=(5.0, 0.012)):
    """A tone whose pitch follows (times, freqs), with a few partials and vibrato."""
    t = t_axis(seconds)
    f = np.interp(t, times, freqs) * (1 + vibrato[1] * np.sin(2 * np.pi * vibrato[0] * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return sum(a * np.sin(ph * k) for k, a in partials)


def charge():
    secs = 2.3
    n = int(secs * SR)
    x = np.zeros(n)
    t = t_axis(secs)
    swell = np.clip(t / secs, 0, 1) ** 1.6
    # Air drawn in through the lips, rising in pitch as the chest fills.
    place(x, sweep_noise(secs, 350, 2600, 0.7, 0.8) * (0.25 + 0.75 * swell) * 0.9, 0.0)
    # A glassy shimmer gathering (a soft chord that brightens).
    chord = sum(glide_tone(secs, [f, f * 1.5], [0, secs], ((1, 1.0), (2, 0.2)), (6.5, 0.006)) for f in (523.0, 784.0, 1046.0))
    place(x, chord * swell ** 2 * 0.09, 0.0)
    # A few bubbles of water in the throat.
    for _ in range(8):
        place(x, drop(np.exp(rng.uniform(np.log(300), np.log(700))), rng.uniform(0.02, 0.04), 1.0) * 0.18, rng.uniform(0.6, 2.1))
    x *= np.minimum(1.0, (secs - t) / 0.06)
    return finish(reverb(x, 0.6, 0.2, 3500), -5)


def roar():
    secs = 2.6
    x = np.zeros(int(secs * SR))
    # The blast of breath.
    place(x, wash(0.08, 500, 7000, 0.002, 0.04) * 1.2, 0.0)
    place(x, wash(1.4, 180, 4200, 0.01, 0.42, 0.08) * 1.1, 0.0)
    place(x, thump(80, 0.5, 0.12) * 0.9, 0.0)
    # The dragon's call: deep and round, rising, then falling away.
    call = glide_tone(1.9, [120, 196, 230, 175, 130], [0, 0.3, 0.75, 1.4, 1.9], ((1, 1.0), (2, 0.5), (3, 0.28), (4, 0.12), (5, 0.06)), (5.5, 0.018))
    # Formants make it a throat, not an organ.
    voiced = bandpass(call, 140, 900) * 0.8 + bandpass(call, 900, 2400) * 0.35
    growl = 1.0 + 0.25 * np.sin(2 * np.pi * 31 * t_axis(1.9))
    voiced *= growl * env(len(voiced), 0.18, 0.5, 0.9)
    place(x, voiced * 0.7, 0.12)
    # Water in its throat and spray off its whiskers.
    gulp = np.zeros(int(1.2 * SR))
    for _ in range(14):
        place(gulp, drop(np.exp(rng.uniform(np.log(160), np.log(520))), rng.uniform(0.03, 0.07), 0.9) * rng.uniform(0.3, 1.0), rng.uniform(0.0, 1.0))
    place(x, lowpass(gulp, 1400) * 0.5, 0.25)
    place(x, wash(1.6, 1800, 7000, 0.3, 0.4) * 0.18, 0.4)
    return finish(reverb(x, 1.0, 0.25, 3000), -2)


def rush():
    secs = 4.6
    n = int(secs * SR)
    t = t_axis(secs)
    # A river rushing through the air, swelling with each stroke of the body.
    body = bandpass(rng.standard_normal(n), 220, 2600) * 0.8 + bandpass(rng.standard_normal(n), 1800, 6000) * 0.25
    strokes = 0.7 + 0.3 * np.sin(2 * np.pi * 1.1 * t) + 0.12 * np.sin(2 * np.pi * 2.7 * t + 1.0)
    shape = np.minimum(1.0, t / 0.35) * np.minimum(1.0, (secs - t) / 1.2)
    x = body * strokes * shape
    drops(x, 0.2, secs - 0.6, 46, 500, 1800, 0.22, 1.0)
    return finish(reverb(x, 0.6, 0.15, 2800), -6, 0.05)


def splash():
    secs = 3.8
    x = np.zeros(int(secs * SR))
    place(x, thump(70, 0.6, 0.14) * 1.4, 0.0)
    place(x, wash(0.1, 400, 6500, 0.001, 0.04) * 1.3, 0.0)
    place(x, wash(1.3, 160, 3000, 0.01, 0.3, 0.1) * 1.2, 0.005)
    # The shower falling back down.
    place(x, wash(2.4, 1600, 7000, 0.3, 0.7, 0.4) * 0.3, 0.3)
    drops(x, 0.3, 2.6, 60, 420, 1700, 0.3, 1.2)
    # Glassy chimes as the rainbow appears.
    for i in range(9):
        f = 1046.0 * 2 ** (rng.choice([0, 4, 7, 9, 12, 16, 19]) / 12)
        tone = glide_tone(1.3, [f, f], [0, 1.3], ((1, 1.0), (2.76, 0.25), (5.4, 0.08)), (4.0, 0.002))
        place(x, tone * env(len(tone), 0.004, 0.32) * 0.07, 0.9 + i * 0.13 + rng.uniform(0, 0.05))
    return finish(reverb(x, 1.2, 0.25, 3200), -2)


def main():
    for name, fn in [("charge", charge), ("roar", roar), ("rush", rush), ("splash", splash)]:
        w.save(name, fn())


if __name__ == "__main__":
    main()
