#!/usr/bin/env python3
"""Synthesises the smoke gifts' sounds from scratch, so all of them are
original and free to ship. Writes Ogg Vorbis files to assets/audio/gifts/.

    python3 tools/synth_gift_audio.py

Needs numpy, scipy and ffmpeg (with libvorbis), like synth_water_audio.py,
whose building blocks it borrows. Loops (slow_hum, cloud_wind,
fireflies_loop) are cross-faded end into start so they repeat seamlessly;
the game turns looping on when it loads them.

  moon_rise        an airy choir swells under a rising arpeggio of chimes
  moon_bounce      a soft, round boing with a twinkle
  moon_land        a cushioned thud, a puff of dust and a few star tinks
  slow_in          a reversed swell, then a deep falling "bwoom"
  slow_out         a rushing upward whoosh as time snaps back
  slow_hum         the stretched world: a low drone and a slow clock tick
  cloud_form       a long breath, a fluffy poof, a little rising chime
  cloud_wind       gentle wind round a cloud, swelling and easing
  cloud_pop        the cloud puffs apart with a falling sparkle
  fireflies_cast   a breath that turns into a swirl of glassy pings
  fireflies_loop   sparse twinkles over soft crickets
  fireflies_found  a sweet run of chimes
  bloom_ring       a rising "fwoop" as the smoke ring goes up
  bloom_boom       a deep soft whump under a magical shimmer and a chord
  bloom_pop        an organic bloop with a creak and a chime
  bloom_boing      a rubbery mushroom boing
  bloom_wilt       a rustle and a slow fall of chimes
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth_water_audio as w
from synth_water_audio import SR, bandpass, lowpass, highpass, env, place, wash, thump, reverb, finish, t_axis

w.OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "gifts")
rng = np.random.default_rng(2510)


def chime(freq, decay, partials=((1, 1.0), (2.0, 0.35), (3.01, 0.12), (4.2, 0.05))):
    t = t_axis(decay * 6)
    x = sum(a * np.sin(2 * np.pi * freq * k * t) * np.exp(-t / (decay / (1 + 0.6 * (k - 1)))) for k, a in partials)
    return x * np.minimum(t / 0.002, 1.0)


def bell(freq, decay):
    return chime(freq, decay, ((1, 1.0), (2.76, 0.45), (5.4, 0.2), (8.93, 0.08)))


def glide(seconds, f0, f1, curve=1.0, partials=((1, 1.0), (2, 0.25))):
    t = t_axis(seconds)
    k = (t / seconds) ** curve
    f = f0 * (f1 / f0) ** k
    ph = 2 * np.pi * np.cumsum(f) / SR
    return sum(a * np.sin(ph * m) for m, a in partials)


def sweep_noise(seconds, f0, f1, q=0.6, curve=1.0):
    from scipy import signal
    n = int(seconds * SR)
    f, tt, z = signal.stft(rng.standard_normal(n), SR, nperseg=1024)
    k = np.clip(tt / seconds, 0, 1) ** curve
    centre = f0 * (f1 / f0) ** k
    width = centre * q
    mask = np.exp(-0.5 * ((f[:, None] - centre[None, :]) / width[None, :]) ** 2)
    _, y = signal.istft(z * mask, SR, nperseg=1024)
    y = y[:n]
    if len(y) < n:
        y = np.pad(y, (0, n - len(y)))
    return y / (np.max(np.abs(y)) or 1.0)


def pad_chord(seconds, freqs, attack, release):
    t = t_axis(seconds)
    x = np.zeros(len(t))
    for f in freqs:
        for det in (-0.004, 0.0, 0.005):
            x += np.sin(2 * np.pi * f * (1 + det) * t + rng.uniform(0, 6.28))
    shape = np.clip(t / attack, 0, 1) ** 1.5 * np.clip((seconds - t) / release, 0, 1)
    return lowpass(x, 2400) * shape / len(freqs)


def loopify(x, fade):
    """Cross-fades the last `fade` seconds into the start: a seamless loop."""
    n = int(fade * SR)
    out = x[:-n].copy()
    ramp = np.linspace(0, 1, n)
    out[:n] = out[:n] * ramp + x[-n:] * (1 - ramp)
    return out


# --- Moon Jump -------------------------------------------------------------

def moon_rise():
    secs = 3.2
    x = np.zeros(int(secs * SR))
    place(x, pad_chord(3.0, [261.6, 329.6, 392.0, 493.9], 1.4, 1.2) * 0.5, 0.0)
    place(x, highpass(wash(3.0, 3000, 9000, 1.2, 0.9), 2500) * 0.08, 0.0)
    for i, f in enumerate([523.3, 659.3, 784.0, 987.8, 1174.7, 1568.0]):
        place(x, bell(f, 0.7) * 0.16, 0.35 + i * 0.22)
    return finish(reverb(x, 1.6, 0.35, 4200), -3)


def moon_bounce():
    x = np.zeros(int(0.7 * SR))
    t = t_axis(0.5)
    f = 170 + 230 * (1 - np.exp(-t / 0.08)) + 18 * np.sin(2 * np.pi * 9 * t) * np.exp(-t / 0.2)
    b = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.14) * np.minimum(t / 0.004, 1)
    place(x, b * 0.6, 0.0)
    place(x, bell(1975, 0.25) * 0.12, 0.05)
    return finish(reverb(x, 0.6, 0.2), -4)


def moon_land():
    x = np.zeros(int(1.0 * SR))
    place(x, thump(95, 0.35, 0.07) * 0.8, 0.0)
    place(x, lowpass(wash(0.6, 200, 2200, 0.01, 0.18), 1800) * 0.35, 0.0)
    for i in range(3):
        place(x, bell(rng.uniform(1800, 3200), 0.22) * 0.12, 0.03 + i * 0.07 + rng.uniform(0, 0.03))
    return finish(reverb(x, 0.7, 0.2), -3)


# --- Slow Time -------------------------------------------------------------

def slow_in():
    secs = 2.6
    x = np.zeros(int(secs * SR))
    swell = sweep_noise(0.7, 600, 4000, 0.5, 1.5) * np.linspace(0, 1, int(0.7 * SR)) ** 2.5
    place(x, swell * 0.45, 0.0)
    t = t_axis(1.9)
    boom = glide(1.9, 110, 38, 0.6, ((1, 1.0), (2, 0.3), (3, 0.1))) * np.exp(-t / 0.7) * np.minimum(t / 0.01, 1)
    place(x, boom * 0.9, 0.68)
    place(x, sweep_noise(1.9, 3500, 250, 0.6, 0.5) * np.exp(-t / 0.6) * 0.35, 0.68)
    for i, f in enumerate([1318.5, 987.8, 784.0, 587.3]):
        place(x, bell(f, 0.9) * 0.1, 0.75 + i * 0.25)
    return finish(reverb(x, 1.8, 0.35, 3000), -2)


def slow_out():
    secs = 1.7
    x = np.zeros(int(secs * SR))
    n = int(1.2 * SR)
    up = sweep_noise(1.2, 250, 4200, 0.55, 1.4) * np.linspace(0, 1, n) ** 1.8
    place(x, up * 0.6, 0.0)
    t = t_axis(1.2)
    place(x, glide(1.2, 60, 220, 1.6) * (t / 1.2) ** 2 * 0.5, 0.0)
    place(x, lowpass(wash(0.5, 300, 5000, 0.005, 0.12), 6000) * 0.5, 1.18)
    return finish(reverb(x, 0.8, 0.2), -3)


def slow_hum():
    secs = 7.0
    t = t_axis(secs)
    x = (np.sin(2 * np.pi * 55 * t) * 0.5 + np.sin(2 * np.pi * 82.5 * t + 1.0) * 0.3 + np.sin(2 * np.pi * 110.2 * t) * 0.12)
    x *= 0.75 + 0.25 * np.sin(2 * np.pi * t / 3.5)
    x += lowpass(rng.standard_normal(len(t)), 300) * 0.15
    for k in range(5):
        tick = bandpass(rng.standard_normal(int(0.12 * SR)), 300, 1400) * env(int(0.12 * SR), 0.002, 0.03)
        place(x, tick * 0.5, 0.2 + k * 1.4)
        place(x, thump(70, 0.25, 0.06) * 0.35, 0.2 + k * 1.4)
    return finish(loopify(x, 1.0), -4, 0.0)


# --- Cloud Ride ------------------------------------------------------------

def cloud_form():
    secs = 1.8
    x = np.zeros(int(secs * SR))
    place(x, sweep_noise(0.9, 400, 1500, 0.8, 1.0) * env(int(0.9 * SR), 0.25, 0.3) * 0.4, 0.0)
    place(x, lowpass(wash(0.9, 80, 1200, 0.02, 0.28), 900) * 0.8, 0.7)
    place(x, thump(120, 0.4, 0.09) * 0.3, 0.7)
    place(x, bell(784.0, 0.6) * 0.1, 0.85)
    place(x, bell(987.8, 0.6) * 0.1, 0.98)
    return finish(reverb(x, 1.0, 0.25), -3)


def cloud_wind():
    secs = 7.0
    n = int(secs * SR)
    t = t_axis(secs)
    x = bandpass(rng.standard_normal(n), 250, 1600) * (0.6 + 0.4 * np.sin(2 * np.pi * t / 3.5 + 1.0))
    x += highpass(bandpass(rng.standard_normal(n), 1500, 4000), 1200) * 0.25 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 1.75))
    return finish(loopify(x, 1.0), -6, 0.0)


def cloud_pop():
    x = np.zeros(int(1.2 * SR))
    place(x, lowpass(wash(0.7, 100, 1500, 0.005, 0.2), 1100) * 0.9, 0.0)
    for i, f in enumerate([1567.98, 1318.5, 987.8]):
        place(x, bell(f, 0.35) * 0.12, 0.08 + i * 0.1)
    return finish(reverb(x, 0.8, 0.25), -3)


# --- Firefly Swarm ---------------------------------------------------------

def pings(buf, start, spread, count, lo, hi, gain):
    for _ in range(count):
        at = start + spread * rng.uniform(0, 1)
        f = np.exp(rng.uniform(np.log(lo), np.log(hi)))
        place(buf, chime(f, rng.uniform(0.06, 0.18)) * rng.uniform(0.3, 1.0) * gain, at)


def fireflies_cast():
    secs = 2.4
    x = np.zeros(int(secs * SR))
    place(x, sweep_noise(0.8, 500, 2600, 0.7) * env(int(0.8 * SR), 0.1, 0.3) * 0.35, 0.0)
    pings(x, 0.25, 1.6, 40, 1800, 5200, 0.12)
    place(x, pad_chord(2.0, [659.3, 830.6, 987.8], 0.6, 1.0) * 0.18, 0.3)
    return finish(reverb(x, 1.4, 0.35, 5000), -4)


def fireflies_loop():
    secs = 7.0
    n = int(secs * SR)
    t = t_axis(secs)
    x = np.zeros(n)
    chirp_rate = 2.2
    carrier = np.sin(2 * np.pi * 4300 * t)
    gate = (np.sin(2 * np.pi * 30 * t) > 0.2) * (np.sin(2 * np.pi * chirp_rate * t) > 0.55)
    x += lowpass(carrier * gate, 6000) * 0.05
    carrier2 = np.sin(2 * np.pi * 3700 * t)
    gate2 = (np.sin(2 * np.pi * 24 * t) > 0.3) * (np.sin(2 * np.pi * 1.6 * t + 1.7) > 0.6)
    x += lowpass(carrier2 * gate2, 6000) * 0.035
    pings(x, 0.0, secs - 0.5, 18, 2000, 5000, 0.08)
    return finish(loopify(reverb(x, 1.2, 0.3, 6000), 1.0), -9, 0.0)


def fireflies_found():
    x = np.zeros(int(2.2 * SR))
    for i, f in enumerate([659.3, 830.6, 987.8, 1108.7, 1318.5, 1661.2]):
        place(x, bell(f, 0.8) * (0.2 - i * 0.015), i * 0.09)
    return finish(reverb(x, 1.5, 0.35, 5200), -3)


# --- Bloom Burst -----------------------------------------------------------

def bloom_ring():
    x = np.zeros(int(1.2 * SR))
    place(x, sweep_noise(0.9, 300, 2200, 0.6, 1.2) * env(int(0.9 * SR), 0.3, 0.25) * 0.5, 0.0)
    t = t_axis(0.5)
    place(x, glide(0.5, 180, 520, 0.8) * np.exp(-t / 0.18) * 0.35, 0.15)
    return finish(reverb(x, 0.7, 0.2), -4)


def bloom_boom():
    secs = 3.0
    x = np.zeros(int(secs * SR))
    t = t_axis(1.4)
    place(x, glide(1.4, 75, 40, 0.5, ((1, 1.0), (2, 0.25))) * np.exp(-t / 0.35) * np.minimum(t / 0.005, 1) * 1.0, 0.0)
    place(x, lowpass(wash(1.2, 60, 900, 0.005, 0.3), 700) * 0.6, 0.0)
    place(x, pad_chord(2.6, [349.2, 440.0, 523.3, 659.3], 0.3, 1.6) * 0.35, 0.1)
    pings(x, 0.15, 1.8, 30, 1500, 4800, 0.1)
    return finish(reverb(x, 1.8, 0.35, 4500), -2)


def bloom_pop():
    x = np.zeros(int(0.9 * SR))
    t = t_axis(0.25)
    place(x, glide(0.25, 140, 520, 0.6) * np.exp(-t / 0.07) * np.minimum(t / 0.003, 1) * 0.8, 0.0)
    creak = bandpass(rng.standard_normal(int(0.3 * SR)), 300, 1200) * (np.sin(2 * np.pi * 38 * t_axis(0.3)) > 0.4) * env(int(0.3 * SR), 0.01, 0.1)
    place(x, creak * 0.18, 0.02)
    place(x, bell(rng.choice([784.0, 880.0, 987.8, 1174.7]), 0.4) * 0.12, 0.06)
    return finish(reverb(x, 0.8, 0.2), -3)


def bloom_boing():
    x = np.zeros(int(0.8 * SR))
    t = t_axis(0.6)
    f = 140 + 120 * np.exp(-t / 0.25) + 35 * np.sin(2 * np.pi * 14 * t) * np.exp(-t / 0.18)
    b = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.2) * np.minimum(t / 0.004, 1)
    place(x, b * 0.75, 0.0)
    place(x, thump(85, 0.25, 0.05) * 0.45, 0.0)
    place(x, lowpass(wash(0.25, 150, 1200, 0.003, 0.05), 900) * 0.25, 0.0)
    return finish(reverb(x, 0.5, 0.15), -3)


def bloom_wilt():
    secs = 3.4
    x = np.zeros(int(secs * SR))
    place(x, highpass(wash(2.5, 2000, 7000, 0.3, 0.9), 1500) * 0.15, 0.0)
    for i, f in enumerate([1318.5, 1174.7, 987.8, 880.0, 784.0, 659.3, 587.3]):
        place(x, bell(f, 0.9) * 0.1, 0.1 + i * 0.3)
    return finish(reverb(x, 1.8, 0.35, 4000), -4)


def main():
    for name, fn in [("moon_rise", moon_rise), ("moon_bounce", moon_bounce), ("moon_land", moon_land),
            ("slow_in", slow_in), ("slow_out", slow_out), ("slow_hum", slow_hum),
            ("cloud_form", cloud_form), ("cloud_wind", cloud_wind), ("cloud_pop", cloud_pop),
            ("fireflies_cast", fireflies_cast), ("fireflies_loop", fireflies_loop), ("fireflies_found", fireflies_found),
            ("bloom_ring", bloom_ring), ("bloom_boom", bloom_boom), ("bloom_pop", bloom_pop),
            ("bloom_boing", bloom_boing), ("bloom_wilt", bloom_wilt)]:
        w.save(name, fn())


if __name__ == "__main__":
    main()
