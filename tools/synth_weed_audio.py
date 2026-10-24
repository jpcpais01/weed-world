#!/usr/bin/env python3
"""Synthesises the little sounds of rolling a joint, from scratch so every
sound is original and free to ship: the pouch, the paper, a sniff, the bud
crumbling, rolling, the lick, the twist, tap-taps and a ta-da twinkle.
Writes Ogg Vorbis files to assets/audio/weed/.

    python3 tools/synth_weed_audio.py

Needs numpy, scipy and ffmpeg (with libvorbis) on the PATH.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "weed")
rng = np.random.default_rng(1420)


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
    j = min(len(buf), i + len(clip))
    buf[i:j] += clip[: j - i]


def grain(length, lo, hi, decay):
    n = int(length * SR)
    g = bandpass(rng.standard_normal(n), lo, hi)
    return g * env(n, 0.0005, decay)


def bell(freq, seconds, decay, partials=((1.0, 1.0), (2.76, 0.35), (5.4, 0.12))):
    t = t_axis(seconds)
    x = np.zeros_like(t)
    for mult, amp in partials:
        x += amp * np.sin(2 * np.pi * freq * mult * t) * np.exp(-t / (decay / mult ** 0.5))
    return x * env(len(t), 0.003, 10.0)


def finish(x, peak_db=-3.0, fade=0.02):
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

def pouch():
    """A soft leather pouch: a couple of cloth rustles and a little thump."""
    x = np.zeros(int(0.42 * SR))
    for at, a in [(0.0, 0.8), (0.07, 1.0), (0.16, 0.6)]:
        n = int(0.09 * SR)
        place(x, bandpass(rng.standard_normal(n), 700, 3800) * env(n, 0.01, 0.03) * a, at)
    t = t_axis(0.2)
    place(x, np.sin(2 * np.pi * 95 * t) * np.exp(-t / 0.05) * 0.8, 0.12)
    return finish(x, -6)


def bling():
    """A bright little twinkle (something magical appears)."""
    x = np.zeros(int(0.6 * SR))
    for k, f in enumerate([1568.0, 2093.0, 2637.0]):
        place(x, bell(f, 0.5, 0.18) * (0.9 - 0.15 * k), 0.035 * k)
    n = len(x)
    x += highpass(rng.standard_normal(n), 6000) * env(n, 0.01, 0.12) * 0.08
    return finish(x, -7)


def paper():
    """A sheet of paper: a quick crisp crinkle."""
    x = np.zeros(int(0.45 * SR))
    for _ in range(26):
        at = rng.uniform(0.0, 0.3) ** 1.4
        place(x, grain(rng.uniform(0.004, 0.02), 2200, 9000, rng.uniform(0.003, 0.012)) * rng.uniform(0.3, 1.0), at)
    n = len(x)
    x += bandpass(rng.standard_normal(n), 1500, 7000) * env(n, 0.02, 0.09) * 0.25
    return finish(x, -6)


def sniff():
    """Two quick sniffs through a big nose."""
    x = np.zeros(int(0.7 * SR))
    for at, a in [(0.0, 0.85), (0.2, 1.0)]:
        n = int(0.16 * SR)
        noise = rng.standard_normal(n)
        # The nostrils' whistle rises as the breath speeds up.
        lo = bandpass(noise, 900, 2600)
        hi = bandpass(noise, 2400, 6500)
        k = np.linspace(0, 1, n)
        place(x, (lo * (1 - k) + hi * k) * env(n, 0.035, 0.05, 0.03) * a, at)
    return finish(x, -5)


def happy():
    """A happy little two-note chime."""
    x = np.zeros(int(0.8 * SR))
    place(x, bell(1318.5, 0.6, 0.22), 0.0)
    place(x, bell(1760.0, 0.6, 0.28), 0.11)
    return finish(x, -9)


def crumble():
    """Dry bud crumbling between finger and thumb, in little rubs."""
    dur = 1.45
    x = np.zeros(int(dur * SR))
    t = 0.0
    while t < dur - 0.02:
        # Rubs come about three times a second; crackles bunch up in each.
        rub = 0.5 + 0.5 * np.sin(2 * np.pi * 3.0 * t) ** 2
        place(x, grain(rng.uniform(0.002, 0.009), 1400, 7500, rng.uniform(0.0015, 0.005)) * rng.uniform(0.2, 1.0) * rub, t)
        t += rng.exponential(0.012 / rub)
    n = len(x)
    bed = bandpass(rng.standard_normal(n), 800, 4000) * 0.12
    bed *= 0.6 + 0.4 * np.sin(2 * np.pi * 3.0 * t_axis(dur)) ** 2
    x += bed
    return finish(x, -7)


def pat():
    """Two soft pats (dusting off the fingers)."""
    x = np.zeros(int(0.32 * SR))
    for at in (0.0, 0.11):
        n = int(0.06 * SR)
        place(x, lowpass(rng.standard_normal(n), 900) * env(n, 0.002, 0.015), at)
    return finish(x, -10)


def roll():
    """Rolling paper between the fingers: soft strokes and crinkles."""
    dur = 1.55
    n = int(dur * SR)
    t = t_axis(dur)
    strokes = np.abs(np.sin(2 * np.pi * 1.75 * t)) ** 1.5
    x = bandpass(rng.standard_normal(n), 1200, 6500) * strokes * 0.5
    for _ in range(40):
        place(x, grain(rng.uniform(0.003, 0.012), 2500, 9000, 0.004) * rng.uniform(0.2, 0.8), rng.uniform(0.0, dur - 0.02))
    x *= env(n, 0.05, 0.6, dur - 0.5)
    return finish(x, -8)


def lick():
    """A wet little 'mlem' and the slide along the gum strip."""
    dur = 0.65
    x = np.zeros(int(dur * SR))
    t = t_axis(0.09)
    mm = (np.sin(2 * np.pi * 190 * t) + 0.4 * np.sin(2 * np.pi * 380 * t) + 0.2 * np.sin(2 * np.pi * 570 * t)) * env(len(t), 0.01, 0.03)
    place(x, mm * 0.6, 0.0)
    place(x, grain(0.01, 1500, 5000, 0.004) * 0.8, 0.07)
    n = int(0.45 * SR)
    slide = bandpass(rng.standard_normal(n), 1800, 5200)
    slide *= 0.7 + 0.3 * np.sin(2 * np.pi * 24 * t_axis(0.45))
    place(x, slide * env(n, 0.04, 0.12, 0.2) * 0.55, 0.1)
    return finish(x, -7)


def glint():
    """A shimmer that runs up: the seam sealing."""
    dur = 0.6
    t = t_axis(dur)
    f = 1800 + 2600 * (t / dur) ** 0.7
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.05, 0.15, 0.25) * 0.35
    for k in range(5):
        place(x, bell(2400 + 450 * k, 0.3, 0.1) * 0.4, 0.06 + 0.08 * k)
    return finish(x, -11)


def twist():
    """The paper tip twisted shut: a tight little crinkle."""
    x = np.zeros(int(0.5 * SR))
    for _ in range(18):
        at = rng.uniform(0.0, 0.38)
        g = grain(rng.uniform(0.004, 0.015), 2800, 4600, 0.006)
        place(x, g * rng.uniform(0.4, 1.0), at)
    return finish(x, -8)


def tap():
    """A soft woody 'tok'."""
    t = t_axis(0.14)
    x = (np.sin(2 * np.pi * 780 * t) * np.exp(-t / 0.018) + 0.5 * np.sin(2 * np.pi * 1290 * t) * np.exp(-t / 0.01))
    click = grain(0.006, 1500, 6000, 0.0015)
    x[: len(click)] += click * 0.6
    return finish(lowpass(x, 3500), -9, fade=0.005)


def tada():
    """Ta-da! A twinkling arpeggio with a sparkly tail."""
    dur = 1.4
    x = np.zeros(int(dur * SR))
    for k, f in enumerate([1046.5, 1318.5, 1568.0, 2093.0]):
        place(x, bell(f, 1.1, 0.45) * (0.8 + 0.1 * k), 0.065 * k)
    for _ in range(14):
        place(x, bell(rng.uniform(2600, 4200), 0.25, 0.07) * rng.uniform(0.1, 0.3), rng.uniform(0.25, 1.0))
    return finish(x, -5)


if __name__ == "__main__":
    for name, make in [("pouch", pouch), ("bling", bling), ("paper", paper), ("sniff", sniff), ("happy", happy),
                       ("crumble", crumble), ("pat", pat), ("roll", roll), ("lick", lick), ("glint", glint),
                       ("twist", twist), ("tap", tap), ("tada", tada)]:
        save(name, make())
