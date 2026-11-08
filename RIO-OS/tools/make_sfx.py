#!/usr/bin/env python3
"""Generate the RIO pet sound effects (small mono 16-bit WAV files) into <out>.
Replace any of them with your own .wav of the same name to customise. Needs: pip install numpy"""
import sys, os, wave
import numpy as np
SR = 44100
rng = np.random.default_rng(7)

def t(d): return np.linspace(0, d, int(SR * d), endpoint=False)
def env(n, a=0.005, r=0.05, curve=1.0):
    e = np.ones(n); na = max(1, int(a * SR)); nr = max(1, int(r * SR))
    e[:na] = np.linspace(0, 1, na); e[-nr:] *= np.linspace(1, 0, nr) ** curve
    return e
def decay(x, k): return x * np.exp(-k * np.linspace(0, 1, len(x)))
def tone(f, d, harm=(1.0,), k=4.0):
    x = t(d); y = sum(h * np.sin(2 * np.pi * f * (i + 1) * x) for i, h in enumerate(harm))
    return decay(y, k) * env(len(x), 0.004, 0.02)
def sweep(f0, f1, d, harm=(1.0,)):
    x = t(d); f = np.linspace(f0, f1, len(x)); ph = 2 * np.pi * np.cumsum(f) / SR
    return sum(h * np.sin(ph * (i + 1)) for i, h in enumerate(harm)) * env(len(x), 0.004, 0.03)
def lowpass_sweep(noise, c0, c1):
    out = np.zeros_like(noise); y = 0.0; n = len(noise)
    for i in range(n):
        c = c0 + (c1 - c0) * i / n; a = 1 - np.exp(-2 * np.pi * c / SR)
        y += a * (noise[i] - y); out[i] = y
    return out
def mix(*parts):
    n = max(len(p[1]) + int(p[0] * SR) for p in parts); out = np.zeros(n)
    for start, x in parts: s = int(start * SR); out[s:s + len(x)] += x
    return out
def save(name, x, peak=0.55):
    x = x / (np.abs(x).max() + 1e-9) * peak
    x = np.concatenate([x, np.zeros(int(0.02 * SR))])
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype('<i2').tobytes())

def thwip():   # web shot: bright airy sweep up + tiny 'tick'
    d = 0.30; n = int(SR * d); noise = rng.standard_normal(n)
    a = lowpass_sweep(noise, 700, 7000) - lowpass_sweep(noise, 200, 900)
    a *= np.sin(np.linspace(0, np.pi, n)) ** 0.6 * np.linspace(0.6, 1, n)
    tick = tone(2100, 0.05, (1, .4), 30)
    return mix((0, a), (0.24, tick * 0.5))
def zip_():    # being pulled along the web: whoosh down
    d = 0.34; n = int(SR * d); noise = rng.standard_normal(n)
    a = lowpass_sweep(noise, 5200, 500) * np.sin(np.linspace(0, np.pi, n)) ** 0.8
    return a
def land():    return mix((0, tone(95, 0.2, (1, .5), 9)), (0, decay(lowpass_sweep(rng.standard_normal(int(SR * .06)), 1500, 300), 6)))
def pop():     return sweep(700, 1250, 0.07, (1, .3)) * np.linspace(1, 0.2, int(SR * .07))
def chime():   return mix((0, tone(1318, 0.55, (1, .35, .12), 5)), (0.11, tone(1760, 0.6, (1, .35, .12), 5)))
def done():    return mix(*[(i * 0.075, tone(f, 0.28, (1, .3), 5)) for i, f in enumerate((523, 659, 784, 1046))])
def celebrate():
    notes = (523, 659, 784, 1046, 784, 1046, 1318)
    parts = [(i * 0.07, tone(f, 0.26, (1, .3, .1), 5)) for i, f in enumerate(notes)]
    spark = [(0.35 + i * 0.04, tone(2400 + 300 * (i % 3), 0.06, (1,), 12) * 0.3) for i in range(7)]
    return mix(*parts, *spark)
def jump():    return sweep(280, 760, 0.2, (1, .4)) * np.linspace(1, 0.3, int(SR * .2))
def hello():    return mix((0, tone(660, 0.14, (1, .3), 5)), (0.11, tone(880, 0.2, (1, .3), 5)))
def breakr():  return mix(*[(i * 0.18, tone(f, 0.45, (1, .25), 4)) for i, f in enumerate((784, 659, 523))])
def sleep():
    n = int(SR * 1.3); a = lowpass_sweep(rng.standard_normal(n), 380, 220); return a * np.sin(np.linspace(0, np.pi, n)) ** 2 * 0.8
def wake():    return mix((0, sweep(300, 520, 0.18, (1, .3))), (0.16, tone(784, 0.25, (1, .3), 5)))
def alert():   return mix((0, tone(740, 0.12, (1, .4), 3)), (0.15, tone(988, 0.2, (1, .4), 4)))
def distract():  # 'wah wah' - missed it
    return mix((0, sweep(520, 380, 0.22, (1, .5))), (0.25, sweep(440, 300, 0.3, (1, .5))))
def push():    return tone(440, 0.07, (1, .3), 8)
def snap():    # stretch / quick action
    return decay(lowpass_sweep(rng.standard_normal(int(SR * .08)), 6000, 1500), 7)

if __name__ == '__main__':
    OUT = sys.argv[1] if len(sys.argv) > 1 else 'sfx'
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [('thwip', thwip), ('zip', zip_), ('land', land), ('pop', pop), ('chime', chime), ('done', done),
                     ('celebrate', celebrate), ('jump', jump), ("wave", hello), ('break', breakr), ('sleep', sleep),
                     ('wake', wake), ('alert', alert), ('distract', distract), ('push', push), ('snap', snap)]:
        save(name, fn(), 0.5 if name not in ('sleep',) else 0.25)
    print('wrote', len(os.listdir(OUT)), 'sounds to', OUT)
