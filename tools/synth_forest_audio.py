#!/usr/bin/env python3
"""Synthesises the Whispering Glade soundscape from scratch, so every sound is
original and free to ship: wind in the leaves, a babbling brook, waterfalls,
pond lapping, bees, crickets, a crackling campfire, frogs and a choir of
songbirds. Writes Ogg Vorbis files to assets/audio/forest/.

    python3 tools/synth_forest_audio.py            # everything
    python3 tools/synth_forest_audio.py --water    # brook, waterfall, pond only

Needs numpy, scipy and ffmpeg (with libvorbis) on the PATH.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "forest")
rng = np.random.default_rng(4207)


# ----------------------------------------------------------------------------
# Helpers

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


def pink(n):
    """Pink noise by spectral shaping."""
    w = rng.standard_normal(n)
    spec = np.fft.rfft(w)
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    spec /= np.sqrt(f)
    p = np.fft.irfft(spec, n)
    return p / np.max(np.abs(p))


def smooth_random(n, rate_hz, lo=0.0, hi=1.0):
    """A slowly wandering control signal."""
    k = max(int(n / SR * rate_hz) + 4, 4)
    pts = rng.uniform(lo, hi, k)
    x = np.linspace(0, k - 3, n)
    return np.interp(x, np.arange(k), pts) if k > 1 else np.full(n, pts[0])


def env_adsr(n, a, d, s_level, r):
    e = np.ones(n) * s_level
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = min(na, n)
    e[:na] = np.linspace(0, 1, na)
    if na + nd < n:
        e[na:na + nd] = np.linspace(1, s_level, nd)
    if nr > 0 and nr < n:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def reverb(x, seconds=0.9, mix=0.18, damp=3000):
    """Convolution with decaying filtered noise: a soft open-forest space."""
    n = int(seconds * SR)
    ir = rng.standard_normal(n) * np.exp(-np.linspace(0, 7, n))
    ir = lowpass(ir, damp)
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = signal.fftconvolve(x, ir)[: len(x)]
    return x * (1 - mix) + wet * mix


def loopify(x, fade=1.0):
    """Crossfade the tail into the head so the clip loops seamlessly."""
    nf = int(fade * SR)
    head = x[:nf]
    tail = x[-nf:]
    ramp = np.linspace(0, 1, nf)
    out = x[nf:].copy()
    out[-nf:] = tail * (1 - ramp) + head * ramp
    return out


def normalize(x, peak=0.9):
    m = np.max(np.abs(x))
    return x if m == 0 else x / m * peak


def save(name, x, quality=4):
    os.makedirs(OUT, exist_ok=True)
    if x.ndim == 1:
        data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    else:
        data = (np.clip(x.T, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wavfile.write(f.name, SR, data)
        tmp = f.name
    dst = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), dst], check=True)
    os.unlink(tmp)
    print("wrote", dst, os.path.getsize(dst) // 1024, "KB")


# ----------------------------------------------------------------------------
# Water

def rms_normalize(x, rms=0.1, peak=0.85):
    """Set the loudness by RMS (what the ear hears), with a peak ceiling."""
    x = x / max(np.sqrt(np.mean(x ** 2)), 1e-9) * rms
    m = np.max(np.abs(x))
    return x if m <= peak else x / m * peak


def soft_drops(seconds, rate, f_lo, f_hi, gen):
    """A few round, low drops: long gentle decays, no bright plinks."""
    n = int(seconds * SR)
    out = np.zeros(n)
    for _ in range(int(seconds * rate)):
        start = gen.integers(0, n)
        f0 = np.exp(gen.uniform(np.log(f_lo), np.log(f_hi)))
        dec = gen.uniform(0.02, 0.06)
        length = min(int(dec * 6 * SR), n - start)
        if length < 8:
            continue
        tt = np.arange(length) / SR
        freq = f0 * (1 + 0.6 * tt / (dec * 6))
        att = np.minimum(tt / 0.004, 1.0)
        out[start:start + length] += gen.uniform(0.2, 1.0) ** 2 * np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-tt / dec) * att
    return out


# The water loops are long (30 s) and soft: shaped noise does the work, with
# only a few low, rounded drops on top. The first versions leaned on hundreds
# of bright synthetic bubbles per second, which read as tinny and nagging.

def brook():
    gen = np.random.default_rng(101)
    secs = 30
    n = int((secs + 2) * SR)
    body = bandpass(pink(n), 180, 2400, 2) * smooth_random(n, 0.25, 0.75, 1.0)
    burble = lowpass(gen.standard_normal(n), 520, 2) * smooth_random(n, 2.2, 0.15, 1.0) * 1.6
    trickle = bandpass(gen.standard_normal(n), 900, 2600, 2) * smooth_random(n, 5.0, 0.0, 1.0) ** 3 * 0.25
    drops = soft_drops(secs + 2, 7, 260, 820, gen) * 0.5
    x = lowpass(body + burble + trickle + drops, 3200, 2)
    x = reverb(x, 0.7, 0.15, 2200)
    return rms_normalize(loopify(x, 2.0), 0.11)


def waterfall():
    gen = np.random.default_rng(202)
    secs = 30
    n = int((secs + 2) * SR)
    roar = bandpass(pink(n), 160, 2000, 2)
    rumble = lowpass(gen.standard_normal(n), 140, 3) * 0.5
    air = bandpass(gen.standard_normal(n), 1800, 4200, 2) * 0.05
    splash = bandpass(gen.standard_normal(n), 400, 1600, 2) * smooth_random(n, 3.0, 0.0, 1.0) ** 2 * 0.5
    x = (roar + rumble + air + splash) * smooth_random(n, 0.35, 0.82, 1.0)
    x = lowpass(reverb(x, 0.9, 0.22, 1800), 3600, 2)
    return rms_normalize(loopify(x, 2.0), 0.12)


def pond():
    gen = np.random.default_rng(303)
    secs = 30
    n = int((secs + 2) * SR)
    lap = np.zeros(n)
    # Slow, soft laps against the bank: low filtered swells, unevenly spaced.
    for _ in range(int(secs * 0.7)):
        s = gen.integers(0, n - 2 * SR)
        ln = int(gen.uniform(0.6, 1.4) * SR)
        e = np.sin(np.linspace(0, np.pi, ln)) ** 3
        lap[s:s + ln] += bandpass(gen.standard_normal(ln), 90, 650, 2) * e * gen.uniform(0.3, 1.0)
    drops = soft_drops(secs + 2, 0.25, 380, 700, gen) * 0.35
    x = lap + drops + lowpass(pink(n), 500, 2) * 0.06
    x = lowpass(reverb(x, 1.0, 0.22, 1600), 2400, 2)
    return rms_normalize(loopify(x, 2.0), 0.07)


# ----------------------------------------------------------------------------
# Air

def wind_leaves():
    """Stereo bed: broad wind with rustling leaves that swells with gusts."""
    secs = 30
    n = int((secs + 2) * SR)
    chans = []
    gust = smooth_random(n, 0.12, 0.25, 1.0)
    gust = lowpass(gust, 0.5, 1)
    for c in range(2):
        base = pink(n)
        centre = smooth_random(n, 0.2, 280, 700)
        # Time-varying band via two fixed bands mixed by the wander.
        low = bandpass(base, 120, 500)
        mid = bandpass(base, 400, 1200)
        mixw = (centre - 280) / 420
        air = (low * (1 - mixw) + mid * mixw) * (0.4 + gust * 0.8)
        # Leaves: high hiss chopped by thousands of tiny flutters.
        flutter = np.zeros(n)
        for _ in range(int(secs * 900)):
            s = rng.integers(0, n - 400)
            ln = rng.integers(60, 400)
            flutter[s:s + ln] += rng.uniform(0.2, 1.0) * np.hanning(ln)
        leaves = lowpass(bandpass(rng.standard_normal(n), 1600, 6000), 4500) * flutter * (0.06 + gust ** 2 * 0.45)
        chans.append(air + leaves * 0.35)
    x = np.stack(chans)
    x = np.stack([loopify(ch, 2.0) for ch in x])
    return normalize(x, 0.7)


def crickets():
    secs = 8
    n = int((secs + 1) * SR)
    x = np.zeros(n)
    tt = np.arange(n) / SR
    for k in range(5):
        f = rng.uniform(4200, 5200)
        period = rng.uniform(0.45, 0.9)
        offset = rng.uniform(0, period)
        pulses = rng.integers(2, 5)
        gate = np.zeros(n)
        start = offset
        while start < secs + 1:
            for p in range(pulses):
                s = int((start + p * 0.022) * SR)
                ln = int(0.012 * SR)
                if s + ln < n:
                    gate[s:s + ln] += np.hanning(ln)
            start += period * rng.uniform(0.9, 1.1)
        x += np.sin(2 * np.pi * f * tt) * gate * rng.uniform(0.3, 1.0)
    return normalize(loopify(reverb(x, 0.7, 0.3), 0.5), 0.5)


def bees():
    secs = 6
    n = int((secs + 1) * SR)
    tt = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(4):
        f0 = rng.uniform(190, 250)
        drift = smooth_random(n, 2.0, 0.9, 1.1) * (1 + 0.02 * np.sin(2 * np.pi * rng.uniform(5, 9) * tt))
        phase = np.cumsum(2 * np.pi * f0 * drift / SR)
        saw = signal.sawtooth(phase)
        near = smooth_random(n, 0.7, 0.1, 1.0) ** 2
        x += saw * near
    x = bandpass(x, 300, 3500) + bandpass(x, 600, 900) * 0.8
    return normalize(loopify(reverb(x, 0.4, 0.1), 0.5), 0.6)


def campfire():
    secs = 8
    n = int((secs + 1) * SR)
    hiss = highpass(rng.standard_normal(n), 3000) * 0.04 * smooth_random(n, 2, 0.5, 1.0)
    roar = lowpass(pink(n), 300) * 0.5 * smooth_random(n, 1.5, 0.6, 1.0)
    crack = np.zeros(n)
    for _ in range(int(secs * 14)):
        s = rng.integers(0, n - 800)
        ln = rng.integers(40, 600)
        burst = rng.standard_normal(ln) * np.exp(-np.linspace(0, rng.uniform(4, 9), ln))
        crack[s:s + ln] += burst * rng.uniform(0.1, 1.0) ** 2
    for _ in range(int(secs * 1.2)):
        s = rng.integers(0, n - 2000)
        ln = rng.integers(600, 2000)
        pop = np.sin(2 * np.pi * rng.uniform(900, 1800) * np.arange(ln) / SR) * np.exp(-np.linspace(0, 8, ln))
        crack[s:s + ln] += pop * rng.uniform(0.3, 0.8)
    crack = highpass(crack, 500)
    x = hiss + roar + crack * 0.6
    return normalize(loopify(reverb(x, 0.5, 0.12), 0.5), 0.8)


# ----------------------------------------------------------------------------
# Creatures

def tone(freqs, amps, harmonics=(1.0, 0.25, 0.08), vibrato=(0.0, 0.0)):
    """A pitched note following the frequency contour `freqs` (per sample)."""
    tt = np.arange(len(freqs)) / SR
    f = freqs * (1 + vibrato[1] * np.sin(2 * np.pi * vibrato[0] * tt))
    phase = 2 * np.pi * np.cumsum(f) / SR
    out = np.zeros(len(freqs))
    for k, h in enumerate(harmonics):
        out += h * np.sin(phase * (k + 1))
    return out * amps


def glide(f0, f1, secs, shape=1.0):
    n = int(secs * SR)
    u = np.linspace(0, 1, n) ** shape
    return f0 + (f1 - f0) * u


def note_env(n, attack=0.15, release=0.35):
    a = max(int(n * attack), 1)
    r = max(int(n * release), 1)
    e = np.ones(n)
    e[:a] = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    e[-r:] *= np.cos(np.linspace(0, np.pi / 2, r)) ** 2
    return e


def place(buf, clip, at):
    s = int(at * SR)
    e = min(s + len(clip), len(buf))
    buf[s:e] += clip[: e - s]


def bird_warbler():
    """A bubbling warbler song: a run of quick rising and falling notes ending
    in a trill."""
    buf = np.zeros(int(2.6 * SR))
    t = 0.05
    for i in range(rng.integers(7, 11)):
        d = rng.uniform(0.05, 0.1)
        f0 = rng.uniform(2800, 4800)
        f1 = f0 * rng.uniform(0.75, 1.35)
        fr = glide(f0, f1, d, rng.uniform(0.6, 1.6))
        place(buf, tone(fr, note_env(len(fr))), t)
        t += d + rng.uniform(0.02, 0.05)
    base = rng.uniform(3500, 4500)
    for i in range(rng.integers(8, 14)):
        fr = glide(base * 1.15, base * 0.85, 0.035)
        place(buf, tone(fr, note_env(len(fr), 0.2, 0.4)) * 0.8, t)
        t += 0.05
    return buf


def bird_robin():
    """Clear fluting phrases with long pitch glides, like a robin or thrush."""
    buf = np.zeros(int(2.4 * SR))
    t = 0.05
    for i in range(rng.integers(3, 6)):
        d = rng.uniform(0.12, 0.28)
        f0 = rng.uniform(1800, 3200)
        f1 = f0 * rng.choice([0.7, 1.3, 1.1, 0.85])
        fr = glide(f0, f1, d, 0.7)
        place(buf, tone(fr, note_env(len(fr), 0.12, 0.4), (1.0, 0.12, 0.03), (28, 0.02)), t)
        t += d + rng.uniform(0.06, 0.16)
    return buf


def bird_chickadee():
    """A sweet two-note 'fee-bee' whistle."""
    buf = np.zeros(int(1.2 * SR))
    f = rng.uniform(3600, 4000)
    a = glide(f, f * 0.98, 0.32)
    b = glide(f * 0.84, f * 0.82, 0.38)
    place(buf, tone(a, note_env(len(a), 0.1, 0.3), (1.0, 0.05)), 0.05)
    place(buf, tone(b, note_env(len(b), 0.1, 0.4), (1.0, 0.05)), 0.45)
    return buf


def bird_chirps():
    """Busy chip calls of a small flock."""
    buf = np.zeros(int(1.6 * SR))
    t = 0.02
    while t < 1.4:
        fr = glide(rng.uniform(5500, 7000), rng.uniform(3000, 4000), rng.uniform(0.02, 0.04), 0.5)
        place(buf, tone(fr, note_env(len(fr), 0.05, 0.5), (1.0, 0.2)) * rng.uniform(0.4, 1.0), t)
        t += rng.uniform(0.06, 0.22)
    return buf


def bird_dove():
    """A soft, low cooing in the distance."""
    buf = np.zeros(int(2.8 * SR))
    t = 0.05
    for d, f in [(0.35, 560), (0.55, 600), (0.3, 540), (0.3, 520), (0.3, 520)]:
        fr = glide(f * 0.92, f, d, 0.4)
        env = note_env(len(fr), 0.3, 0.45)
        trem = 1 - 0.3 * (0.5 + 0.5 * np.sin(2 * np.pi * 22 * np.arange(len(fr)) / SR))
        place(buf, tone(fr, env * trem, (1.0, 0.4, 0.12)), t)
        t += d + 0.12
    return lowpass(buf, 2000)


def woodpecker():
    """Distant drumming on a hollow trunk, speeding up then fading."""
    buf = np.zeros(int(1.6 * SR))
    t = 0.02
    gap = 0.07
    for i in range(rng.integers(14, 20)):
        ln = int(0.03 * SR)
        knock = rng.standard_normal(ln) * np.exp(-np.linspace(0, 10, ln))
        knock = bandpass(knock, 700, 2200) * (1 - i / 22)
        place(buf, knock, t)
        t += gap
        gap *= 0.97
    return buf


def frog():
    """A croaking ribbit: a buzzy pulse train in two parts."""
    buf = np.zeros(int(0.9 * SR))
    for part, (d, f) in enumerate([(0.12, rng.uniform(380, 520)), (0.2, rng.uniform(300, 420))]):
        n = int(d * SR)
        tt = np.arange(n) / SR
        pulses = 0.5 + 0.5 * signal.square(2 * np.pi * rng.uniform(32, 45) * tt, 0.3)
        carrier = np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(4 * np.pi * f * tt)
        place(buf, carrier * pulses * note_env(n, 0.1, 0.3), 0.05 + part * 0.2)
    return lowpass(buf, 2500)


def finish_call(x, gain=0.85, room=0.25):
    x = highpass(x, 250)
    return normalize(reverb(x, 1.2, room, 5000), gain)


# ----------------------------------------------------------------------------

def main():
    import sys
    if "--water" in sys.argv:
        save("brook", brook())
        save("waterfall", waterfall())
        save("pond", pond())
        return
    save("wind_leaves", wind_leaves(), 3)
    save("brook", brook())
    save("waterfall", waterfall())
    save("pond", pond())
    save("crickets", crickets())
    save("bees", bees())
    save("campfire", campfire())
    for i in range(3):
        save("bird_warbler_%d" % i, finish_call(bird_warbler()))
    for i in range(3):
        save("bird_robin_%d" % i, finish_call(bird_robin()))
    for i in range(2):
        save("bird_chickadee_%d" % i, finish_call(bird_chickadee()))
    for i in range(2):
        save("bird_chirps_%d" % i, finish_call(bird_chirps(), 0.7))
    save("bird_dove_0", finish_call(bird_dove(), 0.6, 0.35))
    save("woodpecker_0", finish_call(woodpecker(), 0.6, 0.4))
    for i in range(2):
        save("frog_%d" % i, finish_call(frog(), 0.7, 0.2))


if __name__ == "__main__":
    main()
