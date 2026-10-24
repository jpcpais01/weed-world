#!/usr/bin/env python3
"""Synthesises Weed World's background music from scratch, so every note is
original and free to ship: three short, gentle pieces that drift in between
long stretches of forest sound (see world/music/forest_music.gd).

  glade_morning    kalimba arpeggios over a warm pad, D major, 76 bpm
  under_the_elder  slow felt piano and bass under the big tree, E minor, 58 bpm
  firefly_drift    music-box sparkle in F lydian, 68 bpm

Writes Ogg Vorbis to assets/audio/music/.

    python3 tools/synth_music.py

Needs numpy, scipy and ffmpeg (with libvorbis) on the PATH.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "music")


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


class Mix:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.l = np.zeros(self.n)
        self.r = np.zeros(self.n)

    def add(self, start, mono, gain=1.0, pan=0.0):
        i = int(start * SR)
        if i >= self.n:
            return
        j = min(self.n, i + len(mono))
        seg = mono[: j - i] * gain
        # equal-power pan, -1 left .. 1 right
        a = (pan + 1.0) * np.pi / 4.0
        self.l[i:j] += seg * np.cos(a)
        self.r[i:j] += seg * np.sin(a)


def env(n, attack, release, hold_to=None):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4))
    total = n / SR
    rel_start = total - release
    e *= np.clip((total - t) / max(release, 1e-4), 0.0, 1.0)
    return e


# --- instruments ------------------------------------------------------------

def pad_note(midi, seconds, rng, bright=1.0):
    """Warm, slowly breathing pad: additive saw with a soft roll-off,
    three detuned voices."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f0 = hz(midi)
    out = np.zeros(n)
    for det in (-0.06, 0.0, 0.07):
        f = f0 * 2 ** (det / 12.0)
        ph = rng.uniform(0, 2 * np.pi)
        for h in range(1, 14):
            fh = f * h
            if fh > 3800 * bright:
                break
            amp = (1.0 / h ** 1.7) * np.exp(-fh / (1400.0 * bright))
            out += amp * np.sin(2 * np.pi * fh * t + ph * h)
    # slow swell
    swell = 0.85 + 0.15 * np.sin(2 * np.pi * t / rng.uniform(5, 9) + rng.uniform(0, 6))
    return out * swell * env(n, min(2.5, seconds * 0.4), min(3.0, seconds * 0.45)) * 0.11


def kalimba(midi, rng, length=2.6):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = hz(midi)
    out = np.sin(2 * np.pi * f * t) * np.exp(-t * 2.2)
    out += 0.32 * np.sin(2 * np.pi * f * 5.95 * t) * np.exp(-t * 9.0)
    out += 0.12 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t * 4.0)
    click = np.exp(-t * 900.0) * rng.normal(0, 1, n) * 0.08
    att = np.minimum(1.0, t / 0.003)
    return (out + click) * att * 0.5


def music_box(midi, rng, length=3.2):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = hz(midi)
    out = np.sin(2 * np.pi * f * t) * np.exp(-t * 1.6)
    out += 0.4 * np.sin(2 * np.pi * f * 4.02 * t) * np.exp(-t * 6.0)
    out += 0.18 * np.sin(2 * np.pi * f * 6.98 * t) * np.exp(-t * 11.0)
    att = np.minimum(1.0, t / 0.002)
    return out * att * 0.33


def felt_piano(midi, rng, length=4.5, vel=1.0):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = hz(midi)
    out = np.zeros(n)
    B = 0.0004  # a touch of string stiffness
    for h in range(1, 9):
        fh = f * h * np.sqrt(1 + B * h * h)
        if fh > 5000:
            break
        amp = (1.0 / h ** 2.1) * vel
        dec = 0.9 + 0.55 * h + f / 600.0
        out += amp * np.sin(2 * np.pi * fh * t) * np.exp(-t * dec)
    # felt: soft hammer thump
    out += np.exp(-t * 60.0) * np.sin(2 * np.pi * f * 0.5 * t) * 0.15
    att = np.minimum(1.0, t / 0.008)
    return out * att * 0.42


def bass(midi, seconds):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = hz(midi)
    out = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * 2 * f * t) + 0.06 * np.sin(2 * np.pi * 3 * f * t)
    return out * env(n, 0.25, min(1.5, seconds * 0.4)) * 0.16


def glint(midi, rng):
    """A high, airy sparkle."""
    n = int(2.0 * SR)
    t = np.arange(n) / SR
    f = hz(midi)
    out = np.sin(2 * np.pi * f * t + 0.6 * np.sin(2 * np.pi * 5.0 * t)) * np.exp(-t * 2.8)
    return out * np.minimum(1.0, t / 0.01) * 0.07


# --- space --------------------------------------------------------------------

def reverb(mix, seconds=3.2, wet=0.32, seed=7):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    decay = np.exp(-t * 6.9 / seconds)
    outs = []
    for ch, src in enumerate((mix.l, mix.r)):
        ir = rng.normal(0, 1, n) * decay
        # darker tail
        sos = signal.butter(1, 3200, btype="low", fs=SR, output="sos")
        ir = signal.sosfilt(sos, ir)
        ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
        ir /= np.sqrt(np.sum(ir ** 2))
        w = signal.fftconvolve(src, ir)[: len(src)]
        outs.append(src * (1 - wet) + w * wet * 1.6)
    return outs


def finish(mix, name, fade_in=1.5, fade_out=6.0):
    l, r = reverb(mix)
    st = np.stack([l, r], axis=1)
    n = len(st)
    t = np.arange(n) / SR
    fade = np.minimum(1.0, t / fade_in) * np.clip((n / SR - t) / fade_out, 0, 1)
    st *= fade[:, None]
    # gentle bus lowpass and normalise to -3 dBFS peak
    sos = signal.butter(2, 9000, btype="low", fs=SR, output="sos")
    st = signal.sosfilt(sos, st, axis=0)
    st *= 0.7 / np.max(np.abs(st))
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        wavfile.write(wav, SR, (st * 32767).astype(np.int16))
        out = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", out], check=True)
    print("wrote", os.path.relpath(out), "%.1f s" % (n / SR))


# --- pieces -------------------------------------------------------------------

def glade_morning():
    rng = np.random.default_rng(76)
    bpm = 76.0
    beat = 60.0 / bpm
    bar = beat * 4
    # Dmaj9 | Bm11 | Gmaj7#11 | Asus2  (pads, bass, arpeggio tones)
    chords = [
        ([50, 57, 61, 64, 66], 38, [62, 66, 69, 73, 76, 78]),
        ([47, 54, 57, 62, 64], 35, [59, 62, 66, 69, 71, 74]),
        ([43, 50, 54, 59, 61], 31, [55, 59, 62, 66, 69, 73]),
        ([45, 52, 59, 61, 64], 33, [57, 61, 64, 66, 69, 71]),
    ]
    bars = 20
    mix = Mix(bars * bar + 8.0)
    patterns = [[0, 2, 4, 3, 1, 4, 2, 5], [0, 3, 2, 4, 1, 5, 3, 4], [1, 2, 4, 5, 3, 2, 0, 2]]
    melody = [None, 78, None, 76, 73, None, 71, None, 69, None, 71, 73, None, 69, 66, None]
    for b in range(bars):
        c = chords[(b // 2) % 4]
        start = b * bar
        if b % 2 == 0:
            for k, m in enumerate(c[0]):
                mix.add(start, pad_note(m, bar * 2 + 2.5, rng), 1.0, pan=(k - 2) * 0.25)
            mix.add(start, bass(c[1], bar * 2 + 0.5), 1.0)
        if 2 <= b < bars - 2:
            pat = patterns[(b // 4) % len(patterns)]
            for i, idx in enumerate(pat):
                if rng.random() < 0.12 and i % 2 == 1:
                    continue
                note = c[2][idx]
                swing = 0.02 if i % 2 == 1 else 0.0
                mix.add(start + i * beat * 0.5 + swing, kalimba(note, rng), 0.75 if i % 2 else 0.95, pan=rng.uniform(-0.5, 0.5))
        # a little tune on top, second time round
        if 10 <= b < 18:
            for i in range(4):
                m = melody[((b - 10) * 4 + i) % len(melody)]
                if m is not None:
                    mix.add(start + i * beat + 0.01, music_box(m + 12 if b >= 14 and i == 0 else m, rng), 0.55, pan=0.15)
        if b % 4 == 3:
            mix.add(start + bar * 0.75, glint(90 + rng.choice([0, 2, 4, 7]), rng), 1.0, pan=rng.uniform(-0.8, 0.8))
    finish(mix, "glade_morning")


def under_the_elder():
    rng = np.random.default_rng(58)
    bpm = 58.0
    beat = 60.0 / bpm
    bar = beat * 4
    # Em9 | Cmaj7 | Gadd9 | D/F#
    chords = [
        ([52, 59, 62, 66, 67], 28, [64, 67, 71, 74]),
        ([48, 55, 59, 64, 67], 36, [60, 64, 67, 71]),
        ([43, 50, 55, 57, 62], 31, [62, 67, 69, 71]),
        ([42, 50, 54, 57, 62], 30, [62, 66, 69, 74]),
    ]
    bars = 16
    mix = Mix(bars * bar + 8.0)
    tune = [
        [(0, 71), (2, 74), (3, 72)], [(0, 71), (2, 67)], [(0, 69), (1.5, 71), (2, 74)], [(0, 73), (2, 69)],
        [(0, 76), (2, 74), (3, 71)], [(0, 72), (1, 71), (2, 67)], [(0, 69), (2, 71)], [(0, 66), (2, 69), (3, 74)],
    ]
    for b in range(bars):
        c = chords[b % 4]
        start = b * bar
        for k, m in enumerate(c[0]):
            mix.add(start, pad_note(m, bar + 2.0, rng, bright=0.7), 0.7, pan=(k - 2) * 0.3)
        mix.add(start, bass(c[1], bar + 0.3), 1.1)
        # rolled piano chord on the downbeat, a soft echo on beat 3
        for k, m in enumerate(c[2]):
            mix.add(start + k * 0.045, felt_piano(m, rng, vel=0.8), 0.7, pan=-0.2 + k * 0.12)
        if b % 2 == 1:
            mix.add(start + beat * 2, felt_piano(c[2][-1] + 12, rng, vel=0.6), 0.45, pan=0.3)
        if 4 <= b < 12 + 2:
            for when, m in tune[(b - 4) % len(tune)]:
                mix.add(start + when * beat + rng.uniform(0, 0.02), felt_piano(m + 12, rng, length=5.0, vel=1.0), 0.75, pan=0.1)
    finish(mix, "under_the_elder", fade_out=7.0)


def firefly_drift():
    rng = np.random.default_rng(68)
    bpm = 68.0
    beat = 60.0 / bpm
    bar = beat * 4
    # Fmaj7#11 | G/F | Em7 | Am9
    chords = [
        ([41, 53, 57, 60, 64, 71], 29, [65, 69, 71, 72, 76, 79]),
        ([41, 55, 59, 62, 67], 29, [67, 71, 74, 79, 81]),
        ([40, 52, 55, 59, 62], 28, [64, 67, 71, 74, 76]),
        ([45, 52, 55, 59, 60, 64], 33, [64, 67, 69, 71, 72, 76]),
    ]
    bars = 18
    mix = Mix(bars * bar + 8.0)
    for b in range(bars):
        c = chords[b % 4]
        start = b * bar
        for k, m in enumerate(c[0]):
            mix.add(start, pad_note(m, bar + 2.5, rng, bright=1.2), 0.85, pan=(k - 2.5) * 0.22)
        if b >= 1:
            mix.add(start, bass(c[1], bar + 0.4), 0.9)
        if 1 <= b < bars - 1:
            # fireflies: music-box notes that wander up and down the chord
            steps = 8 if b % 4 != 3 else 6
            idx = rng.integers(0, len(c[2]))
            for i in range(steps):
                if rng.random() < 0.18:
                    continue
                idx = int(np.clip(idx + rng.choice([-2, -1, 1, 1, 2]), 0, len(c[2]) - 1))
                note = c[2][idx] + (12 if b >= 9 and i % 3 == 0 else 0)
                mix.add(start + i * bar / steps + rng.uniform(-0.015, 0.015), music_box(note, rng), 0.6, pan=rng.uniform(-0.7, 0.7))
        if b % 2 == 0:
            for k in range(3):
                mix.add(start + rng.uniform(0, bar), glint(88 + int(rng.choice([0, 4, 7, 11, 14])), rng), 0.9, pan=rng.uniform(-0.9, 0.9))
    finish(mix, "firefly_drift")


if __name__ == "__main__":
    glade_morning()
    under_the_elder()
    firefly_drift()
