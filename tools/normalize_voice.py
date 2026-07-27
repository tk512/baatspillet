#!/usr/bin/env python3
"""Loudness-match the voice clips so no line vanishes under the music.

Finn-Erik's lines are recorded in different sittings, at different distances
from the microphone, so they arrived spanning ~13 dB: "oppdrag" at -9 dB mean
and "finn_en_havn" at -20 dB. Playback can't fix that -- Assets.playNamedVoice
already uses volume 1.0, which is OpenAL's ceiling -- so a quiet recording is
simply quiet. The fix belongs in the files.

Normalises to EBU R128 (the loudness standard broadcast uses), so every line
lands at the same PERCEIVED volume rather than the same peak: peak-matching
would still leave a softly-spoken line sounding faint.

    python3 tools/normalize_voice.py           # normalise assets/voice/*.ogg
    python3 tools/normalize_voice.py --check   # measure only, change nothing

Originals are copied to raw/voice_original/ the first time each file is
touched, and never overwritten after -- so running this twice can't quietly
normalise an already-normalised file into mush, and the raw takes survive.

Re-run it whenever new lines are recorded; matching a new clip to the set by
ear is exactly the thing this removes.
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
VOICE = os.path.join(ROOT, "assets", "voice")
BACKUP = os.path.join(ROOT, "raw", "voice_original")

# -14 LUFS: a little hotter than the -16 broadcast/streaming norm, because this
# competes with a music bed and an ambience loop on a tablet speaker held at
# arm's length by a child. TP leaves 1.5 dB of true-peak headroom so nothing
# distorts through the Vorbis encode.
#
# NOTE measure LOUDNESS (LUFS), not RMS: "finn_en_havn" reads -20 dB mean but is
# -15 LUFS -- the low RMS is just silence around a short line. It sounded faint
# only because "oppdrag" and "skatt" were 6-7 dB HOTTER than everything else.
# Matching perceived loudness is the whole point of normalising here.
TARGET_I, TARGET_TP, TARGET_LRA = -14.0, -1.5, 11.0


def measure(path):
    out = subprocess.run(
        ["ffmpeg", "-i", path, "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True, text=True).stderr
    mean = re.search(r"mean_volume:\s*(-?[\d.]+) dB", out)
    peak = re.search(r"max_volume:\s*(-?[\d.]+) dB", out)
    return (float(mean.group(1)) if mean else None,
            float(peak.group(1)) if peak else None)


ap = argparse.ArgumentParser()
ap.add_argument("--check", action="store_true", help="measure only")
args = ap.parse_args()

files = sorted(glob.glob(os.path.join(VOICE, "*.ogg")))
if not files:
    sys.exit("no voice files found in " + VOICE)
os.makedirs(BACKUP, exist_ok=True)

print(f"{'clip':<24}{'mean':>9}{'peak':>9}   ->{'mean':>9}{'peak':>9}")
for f in files:
    name = os.path.basename(f)
    m0, p0 = measure(f)
    if args.check:
        print(f"{name:<24}{m0:>8.1f}dB{p0:>8.1f}dB")
        continue

    # keep the raw take exactly once, before it is ever rewritten
    kept = os.path.join(BACKUP, name)
    if not os.path.exists(kept):
        shutil.copy2(f, kept)

    # ffmpeg (loudnorm -> wav) | oggenc (-> vorbis), the pipeline CLAUDE.md
    # documents. Homebrew's ffmpeg ships without libvorbis, and its built-in
    # "vorbis" encoder is experimental and sounds worse than oggenc.
    wav, tmp = f + ".norm.wav", f + ".norm.ogg"
    r = subprocess.run(
        ["ffmpeg", "-y", "-i", kept,          # always normalise from the RAW take
         "-af", f"loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}",
         "-ar", "44100", wav],
        capture_output=True, text=True)
    if r.returncode == 0:
        r = subprocess.run(["oggenc", "-Q", "-q", "5", "-o", tmp, wav],
                           capture_output=True, text=True)
    if os.path.exists(wav):
        os.remove(wav)
    if r.returncode != 0 or not os.path.exists(tmp):
        tail = (r.stderr or "").strip().splitlines()
        print(f"{name:<24}  FAILED: {tail[-1] if tail else 'unknown'}")
        if os.path.exists(tmp):
            os.remove(tmp)
        continue
    os.replace(tmp, f)
    m1, p1 = measure(f)
    print(f"{name:<24}{m0:>8.1f}dB{p0:>8.1f}dB   ->{m1:>8.1f}dB{p1:>8.1f}dB")

if not args.check:
    print(f"\nraw takes kept in {os.path.relpath(BACKUP, ROOT)}")
