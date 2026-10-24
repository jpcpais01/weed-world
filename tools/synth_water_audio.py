#!/usr/bin/env python3
"""Synthesises a Keling's water sounds from scratch so every one is original
and free to ship: footsteps in the shallows, wading, splashes, a cannonball
plunge, paddle strokes, sinking in, sloshing out and a puppy-style shake.
Writes Ogg Vorbis files to assets/audio/water/.

    python3 tools/synth_water_audio.py

Needs numpy, scipy and ffmpeg (with libvorbis) on the PATH.

Like the forest's water loops, these lean on shaped noise for the body of the
water, with only a few low, rounded drops on top: lots of bright synthetic
bubbles read as tinny.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "water")
rng = np.random.default_rng(2610)


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, f, order=2):
    sos = signal.butter(order, f, btype="low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, f, order=2):
    sos = signal.butter(order, f, btype="high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def env(n, attack, release, hold=0.0):
    """Attack / hold / exponential release envelope over n samples."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    r = np.exp(-np.clip(t - attack - hold, 0.0, None) / max(release, 1e-4))
    return a * r


def place(buf, clip, at):
    i = int(at * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(clip))
    buf[i:j] += clip[: j - i]


def drop(f0, decay, rise=0.5):
    """One rounded water drop: a sine whose pitch rises as the bubble closes."""
    t = t_axis(decay * 6)
    freq = f0 * (1 + rise * t / (decay * 6))
    att = np.minimum(t / 0.003, 1.0)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / decay) * att


def drops(buf, start, spread, count, f_lo, f_hi, gain, skew=1.6):
    """Scatter `count` drops over `spread` seconds, crowded towards the start."""
    for _ in range(count):
        at = start + spread * rng.uniform(0, 1) ** skew
        f0 = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi)))
        place(buf, drop(f0, rng.uniform(0.015, 0.045)) * rng.uniform(0.25, 1.0) ** 2 * gain, at)


def wash(seconds, lo, hi, attack, release, hold=0.0):
    """Filtered noise with an envelope: the body of moving water."""
    n = int(seconds * SR)
    return bandpass(rng.standard_normal(n), lo, hi) * env(n, attack, release, hold)


def thump(freq, seconds, decay):
    t = t_axis(seconds)
    sweep = freq * (1.0 - 0.35 * t / seconds)
    return np.sin(2 * np.pi * np.cumsum(sweep) / SR) * np.exp(-t / decay)


def reverb(x, seconds=0.5, mix=0.15, damp=2500):
    n = int(seconds * SR)
    tail = rng.standard_normal(n) * np.exp(-np.arange(n) / SR / (seconds / 5))
    tail = lowpass(tail, damp)
    wet = signal.fftconvolve(x, tail)[: len(x)]
    wet /= np.max(np.abs(wet)) or 1.0
    return x * (1 - mix) + wet * mix * np.max(np.abs(x))


def finish(x, peak_db=-3.0, fade=0.01):
    n = int(fade * SR)
    if n and len(x) > 2 * n:
        x[:n] *= np.linspace(0, 1, n)
        x[-n:] *= np.linspace(1, 0, n)
    peak = np.max(np.abs(x)) or 1.0
    return x / peak * 10 ** (peak_db / 20)


def save(name, x, quality=4):
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    wavfile.write(tmp, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    dst = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), dst], check=True)
    os.remove(tmp)
    print("wrote", dst, f"{len(x) / SR:.2f}s")


# ----------------------------------------------------------------------------
# The sounds

def step(k):
    """A small foot patting down in ankle-deep water: a light slap and a sprinkle."""
    x = np.zeros(int(0.32 * SR))
    lo = 500 + 120 * k
    place(x, wash(0.08, lo, 3600, 0.002, 0.025), 0.0)
    place(x, wash(0.22, 300, 1500, 0.01, 0.06) * 0.5, 0.01)
    drops(x, 0.02, 0.18, 3 + k, 420, 1100, 0.35)
    return finish(reverb(x, 0.25, 0.08), -5)


def wade(k):
    """Pushing a leg through deeper water: a swirling swash that rises and falls."""
    secs = 0.55
    x = np.zeros(int(secs * SR))
    n = len(x)
    swell = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    x += bandpass(rng.standard_normal(n), 160, 1100 + 150 * k) * swell * 0.9
    x += bandpass(rng.standard_normal(n), 900, 2600) * swell ** 3 * 0.25
    drops(x, 0.1, 0.35, 3, 260, 620, 0.3, 1.0)
    return finish(reverb(lowpass(x, 3000), 0.35, 0.12), -5)


def splash(k):
    """A medium splash: a slap, a spray of water and drops falling back."""
    secs = 0.8
    x = np.zeros(int(secs * SR))
    place(x, wash(0.06, 700, 5000, 0.001, 0.02) * 1.0, 0.0)
    place(x, wash(0.45, 250, 2800 - 300 * k, 0.005, 0.11), 0.004)
    place(x, thump(140 - 15 * k, 0.15, 0.04) * 0.5, 0.0)
    # Spray falling back onto the surface.
    place(x, wash(0.5, 1500, 5500, 0.08, 0.12) * 0.25, 0.12)
    drops(x, 0.08, 0.55, 9, 380, 1300, 0.4, 1.3)
    return finish(reverb(x, 0.4, 0.12), -4)


def plunge():
    """A Keling cannonball: a deep whump, a roar of spray, bubbles gulping up
    and a long patter of drops raining back down."""
    secs = 1.9
    x = np.zeros(int(secs * SR))
    place(x, thump(95, 0.4, 0.09) * 1.3, 0.0)
    place(x, wash(0.08, 400, 6000, 0.001, 0.03) * 1.2, 0.0)
    place(x, wash(0.9, 180, 2600, 0.01, 0.22, 0.05) * 1.1, 0.005)
    # The cavity collapsing: a low gulp of bubbles.
    gulp = np.zeros(int(0.7 * SR))
    for _ in range(7):
        place(gulp, drop(np.exp(rng.uniform(np.log(140), np.log(320))), rng.uniform(0.04, 0.08), 0.8) * rng.uniform(0.4, 1.0), rng.uniform(0.0, 0.5))
    place(x, lowpass(gulp, 900) * 0.7, 0.18)
    # Spray raining back over a second or so.
    rain = wash(1.4, 1800, 6500, 0.25, 0.35) * 0.22
    place(x, rain, 0.25)
    drops(x, 0.3, 1.3, 22, 420, 1500, 0.32, 1.4)
    return finish(reverb(x, 0.7, 0.18, 2200), -2)


def stroke(k):
    """A paddle stroke: a soft swish under the surface and a little lap."""
    secs = 0.42
    x = np.zeros(int(secs * SR))
    n = int(0.3 * SR)
    swish = bandpass(rng.standard_normal(n), 220, 900 + 120 * k) * np.sin(np.linspace(0, np.pi, n)) ** 2
    place(x, swish * 0.8, 0.0)
    place(x, wash(0.12, 600, 2400, 0.004, 0.03) * 0.45, 0.13)
    drops(x, 0.14, 0.2, 2, 330, 700, 0.3, 1.0)
    return finish(reverb(lowpass(x, 3200), 0.3, 0.12), -6)


def bloop():
    """Easing into deep water: a round, low bloop and a few rising bubbles."""
    secs = 0.7
    x = np.zeros(int(secs * SR))
    place(x, drop(190, 0.07, 0.9) * 1.0, 0.0)
    place(x, wash(0.35, 150, 900, 0.03, 0.08) * 0.6, 0.0)
    for at, f in [(0.12, 300), (0.2, 420), (0.27, 360), (0.36, 520)]:
        place(x, drop(f, 0.03, 0.7) * 0.45, at)
    return finish(reverb(lowpass(x, 2500), 0.4, 0.15), -5)


def slosh():
    """Finding your feet and wading out: water sheeting off and sloshing round."""
    secs = 1.0
    x = np.zeros(int(secs * SR))
    n = len(x)
    pour = bandpass(rng.standard_normal(n), 300, 2200) * env(n, 0.05, 0.25, 0.1)
    x += pour * 0.8
    x += bandpass(rng.standard_normal(n), 1600, 4800) * env(n, 0.15, 0.2, 0.1) * 0.2
    drops(x, 0.15, 0.7, 10, 400, 1200, 0.3, 1.0)
    return finish(reverb(x, 0.4, 0.12), -5)


def shake():
    """A puppy shake: a fast flutter of flung water and a spray of drops."""
    secs = 0.95
    x = np.zeros(int(secs * SR))
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    # The body whips back and forth ~7 times a second, flinging water each way.
    flutter = (0.5 + 0.5 * np.sin(2 * np.pi * 7.5 * t)) ** 3
    shape = np.sin(np.linspace(0, np.pi, n)) ** 0.7
    x[:n] += bandpass(rng.standard_normal(n), 900, 6000) * flutter * shape * 0.9
    x[:n] += bandpass(rng.standard_normal(n), 200, 900) * flutter * shape * 0.35
    drops(x, 0.1, 0.8, 16, 500, 1500, 0.25, 1.0)
    return finish(reverb(x, 0.35, 0.1), -6)


def main():
    for k in range(4):
        save(f"step_{k}", step(k))
    for k in range(3):
        save(f"wade_{k}", wade(k))
    for k in range(2):
        save(f"splash_{k}", splash(k))
    save("plunge", plunge())
    for k in range(3):
        save(f"stroke_{k}", stroke(k))
    save("bloop", bloop())
    save("slosh", slosh())
    save("shake", shake())


if __name__ == "__main__":
    main()
