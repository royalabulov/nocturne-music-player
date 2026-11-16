"""Song radio quality test, step 1: YAMNet embeddings for the FMA "small" set.

Measures radio on public music, not on one person's library: FMA small has 8000 clips of
30 s, 1000 in each of 8 genres (https://github.com/mdeff/fma). Each clip goes through the
same steps as the app's AudioAnalyzer.kt, so the numbers are the ones the phone would give:
the same yamnet.tflite, mono, a 7 kHz low-pass (31-tap Hann windowed sinc) and linear
interpolation to 16 kHz, one 10 s part at 10% for files under 40 s, 3 YAMNet windows spread
across each part, the embedding averaged over them.

The audio stays outside the repository and is never shipped. Output: one JSON line a clip
(trackId, genre, artist, rmsDb, the float embedding as base64); tool/radio_eval/radio_eval.dart
packs it the way the app does and measures. Clips already in the output are skipped, so a
stopped run carries on.

    python -m venv venv && venv/Scripts/pip install tensorflow numpy soundfile
    venv/Scripts/python tool/radio_eval/fma_embeddings.py <fma folder> [--limit N] [--workers N]

<fma folder> holds fma_metadata/ and fma_small/ (unzipped).
"""

import argparse
import base64
import csv
import json
import os
import sys
from multiprocessing import Pool
from pathlib import Path

import numpy as np

MODEL = Path(__file__).resolve().parents[2] / "android/app/src/main/assets/yamnet.tflite"
SAMPLE_RATE = 16000
SEGMENT_SECONDS = 10
FRAMES_PER_SEGMENT = 3


def read_tracks(meta: Path) -> list[dict]:
    """The small set's tracks with their top genre and artist (tracks.csv has 3 header rows)."""
    with open(meta / "tracks.csv", encoding="utf-8", newline="") as f:
        rows = csv.reader(f)
        top, sub, _ = next(rows), next(rows), next(rows)
        col = {f"{a}.{b}": i for i, (a, b) in enumerate(zip(top, sub))}
        out = []
        for r in rows:
            if r[col["set.subset"]] != "small" or not r[col["track.genre_top"]]:
                continue
            out.append({"trackId": int(r[0]), "genre": r[col["track.genre_top"]], "artist": r[col["artist.name"]]})
    return out


def low_pass(x: np.ndarray, cutoff: float) -> np.ndarray:
    """AudioAnalyzer.lowPass: 31 taps, Hann window, normalized, 'same' alignment."""
    taps, mid = 31, 15
    k = np.arange(taps) - mid
    sinc = np.where(k == 0, 2 * cutoff, np.sin(2 * np.pi * cutoff * k) / (np.pi * np.where(k == 0, 1, k)))
    w = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(taps) / (taps - 1))
    h = (sinc * w).astype(np.float32)
    h /= h.sum()
    return np.convolve(x, h, mode="same").astype(np.float32)


def resample(src: np.ndarray, rate: int) -> np.ndarray:
    """AudioAnalyzer.resample: low-pass above 16 kHz, then linear interpolation, clamped."""
    x = low_pass(src, 7000.0 / rate) if rate > SAMPLE_RATE else src
    n = len(x) * SAMPLE_RATE // rate
    pos = np.arange(n) * (rate / SAMPLE_RATE)
    j = pos.astype(np.int64)
    ok = j < len(x) - 1
    j, frac = j[ok], (pos[ok] - j[ok]).astype(np.float32)
    return np.clip(x[j] * (1 - frac) + x[j + 1] * frac, -1, 1).astype(np.float32)


def segments(path: Path) -> list[np.ndarray]:
    import soundfile as sf

    with sf.SoundFile(str(path)) as f:
        rate, total = f.samplerate, f.frames
        dur = total / rate
        positions = [0.1] if dur < 40 else [0.25, 0.5, 0.75]
        out = []
        for p in positions:
            f.seek(int(total * p))
            pcm = f.read(rate * SEGMENT_SECONDS, dtype="float32", always_2d=True)
            if len(pcm):
                out.append(resample(pcm.mean(axis=1), rate))
        return out


_it = None


def interpreter():
    global _it
    if _it is None:
        os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
        import tensorflow as tf

        _it = tf.lite.Interpreter(model_path=str(MODEL), num_threads=1)
        _it.allocate_tensors()
    return _it


def analyze(track: dict, audio: Path) -> dict:
    tid = track["trackId"]
    path = audio / f"{tid:06d}"[:3] / f"{tid:06d}.mp3"
    try:
        segs = segments(path)
    except Exception as e:  # FMA small has a few broken files
        return {**track, "error": str(e)}
    if not segs:
        return {**track, "error": "no audio decoded"}

    it = interpreter()
    inp = it.get_input_details()[0]
    outs = it.get_output_details()
    emb_out = outs[1]
    scale, zero = emb_out["quantization"]
    frame = inp["shape"][-1]
    emb_sum = np.zeros(1024, dtype=np.float64)
    frames, sq, n = 0, 0.0, 0
    for seg in segs:
        sq += float(np.square(seg, dtype=np.float64).sum())
        n += len(seg)
        count = max(1, min(FRAMES_PER_SEGMENT, len(seg) // frame))
        span = max(len(seg) - frame, 0)
        for f in range(count):
            start = 0 if count == 1 else span * f // (count - 1)
            x = np.zeros(frame, dtype=np.float32)
            part = seg[start : start + frame]
            x[: len(part)] = part
            it.set_tensor(inp["index"], x)
            it.invoke()
            e = it.get_tensor(emb_out["index"]).reshape(-1)
            emb_sum += (e.astype(np.float64) - zero) * scale if e.dtype == np.int8 else e
            frames += 1
    rms = np.sqrt(sq / max(n, 1))
    emb = (emb_sum / frames).astype(np.float32)
    return {
        **track,
        "rmsDb": round(float(20 * np.log10(max(rms, 1e-6))), 3),
        "embedding": base64.b64encode(emb.tobytes()).decode(),
    }


def _work(args):
    return analyze(*args)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("fma", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--limit", type=int, default=0, help="only the first N clips (a quick try)")
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    a = ap.parse_args()
    out = a.out or a.fma / "fma_small_embeddings.jsonl"

    tracks = read_tracks(a.fma / "fma_metadata")
    if a.limit:
        tracks = tracks[: a.limit]
    done = set()
    if out.exists():
        with open(out, encoding="utf-8") as f:
            done = {json.loads(line)["trackId"] for line in f if line.strip()}
    todo = [t for t in tracks if t["trackId"] not in done]
    print(f"{len(tracks)} clips, {len(done)} done, {len(todo)} to go, {a.workers} workers", flush=True)

    errors = 0
    with open(out, "a", encoding="utf-8") as f, Pool(a.workers) as pool:
        for i, r in enumerate(pool.imap_unordered(_work, [(t, a.fma / "fma_small") for t in todo], chunksize=4), 1):
            if "error" in r:
                errors += 1
                print(f"skip {r['trackId']}: {r['error']}", file=sys.stderr, flush=True)
            f.write(json.dumps(r) + "\n")
            if i % 200 == 0:
                f.flush()
                print(f"{i}/{len(todo)}", flush=True)
    print(f"done: {out} ({errors} could not be read)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
