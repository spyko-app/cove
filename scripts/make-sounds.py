#!/usr/bin/env python3
"""Sons próprios do Cove (sintetizados, sem asset de terceiro).
Gera WAV 44.1k mono em Resources/Sounds — durações espelham o Alcove."""
import math, os, struct, wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Sounds")
os.makedirs(OUT, exist_ok=True)

def tone(freq, dur, amp=0.35, attack=0.005, decay=None, harm=0.0):
    n = int(SR * dur)
    decay = decay or dur
    out = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / attack) * math.exp(-3.0 * t / decay)
        v = math.sin(2 * math.pi * freq * t) + harm * math.sin(2 * math.pi * freq * 2 * t)
        out.append(amp * env * v)
    return out

def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] if i < len(p) else 0.0 for p in parts) for i in range(n)]

def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out += p + [0.0] * int(SR * gap)
    return out

def write(name, samples):
    with wave.open(os.path.join(OUT, name + ".wav"), "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))

write("volume", tone(1100, 0.12, amp=0.18, decay=0.06))                       # tick por passo
write("lock", seq(tone(660, 0.14, decay=0.1), tone(440, 0.16, decay=0.12)))   # desce
write("unlock", seq(tone(440, 0.14, decay=0.1), tone(660, 0.16, decay=0.12)))  # sobe
write("low-battery", seq(tone(392, 0.3, decay=0.25), tone(330, 0.3, decay=0.25), tone(262, 0.5, decay=0.4)))
write("low-power", seq(tone(523, 0.2, decay=0.15), tone(392, 0.45, decay=0.35)))
write("event", seq(tone(784, 0.25, harm=0.3), tone(988, 0.25, harm=0.3), tone(1175, 0.9, decay=0.7, harm=0.3), gap=0.05))
write("directions", seq(tone(659, 0.3, harm=0.2), tone(880, 0.3, harm=0.2), tone(659, 0.8, decay=0.6, harm=0.2)))
write("chime", mix(tone(523, 4.0, amp=0.25, decay=2.5, harm=0.2), tone(784, 4.0, amp=0.18, decay=2.0)))
write("sleep", seq(tone(392, 1.0, amp=0.2, decay=0.9), tone(330, 1.0, amp=0.2, decay=0.9), tone(262, 1.0, amp=0.2, decay=1.0)))
write("device", seq(tone(880, 0.12, decay=0.1), tone(1319, 0.3, decay=0.25)))  # AirPods conectou
write("haptic", tone(180, 0.012, amp=0.5, attack=0.001, decay=0.01))
print("sons em", os.path.abspath(OUT))
