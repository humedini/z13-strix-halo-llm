#!/usr/bin/env python3
"""
Transcribe and diarise an audio file: who said what, with timestamps.

Architecture, and why it is not WhisperX:
  CTranslate2 (which faster-whisper and therefore WhisperX are built on) has no
  ROCm backend, so stock WhisperX transcribes on the CPU on AMD hardware. Here
  transcription goes to whisper.cpp via Lemonade, which has real ROCm and Vulkan
  builds (and can run on the NPU instead), while diarisation uses pyannote.audio
  on PyTorch ROCm, which supports AMD natively. Both parts are GPU accelerated
  with no patched forks.

Usage:
  diarise.py AUDIO [--model Whisper-Large-v3-Turbo] [--speakers N] [--json OUT]
"""
import argparse, json, os, subprocess, sys, tempfile, urllib.request

VENV = os.path.expanduser("~/whisper-diarise")
TOKEN_FILE = os.path.expanduser("~/.config/hf/token")
LEMONADE = os.environ.get("LEMONADE_URL", "http://127.0.0.1:13305")


def hf_token():
    if os.environ.get("HF_TOKEN"):
        return os.environ["HF_TOKEN"]
    if os.path.exists(TOKEN_FILE):
        return open(TOKEN_FILE).read().strip()
    sys.exit(f"No HF token. Put one in {TOKEN_FILE} or set HF_TOKEN.")


def to_wav(path):
    """pyannote and whisper.cpp both want 16 kHz mono PCM."""
    out = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
    subprocess.run(["ffmpeg", "-y", "-i", path, "-ar", "16000", "-ac", "1",
                    "-c:a", "pcm_s16le", out],
                   check=True, capture_output=True)
    return out


def transcribe(wav, model):
    """whisper.cpp via Lemonade's OpenAI-compatible endpoint (GPU or NPU)."""
    import uuid
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in (("model", model), ("response_format", "verbose_json")):
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode())
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
                 f"filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".encode())
    parts.append(open(wav, "rb").read())
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    body = b"".join(parts)
    req = urllib.request.Request(f"{LEMONADE}/api/v1/audio/transcriptions", body,
        {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    d = json.load(urllib.request.urlopen(req, timeout=3600))
    segs = d.get("segments")
    if segs:
        return [{"start": s["start"], "end": s["end"], "text": s["text"].strip()} for s in segs]
    # The FLM/NPU whisper backend returns only {model, text}: no segments, no
    # words, no timestamps, whatever response_format is asked for. Diarisation
    # needs timestamps to align speaker turns against, so fail loudly here
    # rather than silently labelling everything UNKNOWN.
    raise SystemExit(
        f"\nERROR: model '{model}' returned no timestamped segments.\n"
        "The NPU (FLM) whisper backend does not emit timestamps, so it cannot be\n"
        "used for diarisation. Use a whispercpp model instead, e.g.\n"
        "  --model Whisper-Large-v3-Turbo\n"
        "The NPU model is still fine for plain transcription without speakers.")


def load_waveform(wav):
    """Read a 16 kHz mono PCM wav into a tensor.

    pyannote would normally decode this itself via torchcodec, but torchcodec's
    shared library fails to load in this environment. Passing the audio in memory
    is the documented workaround and avoids the dependency entirely.
    """
    import wave, numpy as np, torch
    with wave.open(wav, "rb") as w:
        assert w.getsampwidth() == 2, "expected 16-bit PCM"
        sr = w.getframerate()
        raw = w.readframes(w.getnframes())
        ch = w.getnchannels()
    a = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    return {"waveform": torch.from_numpy(a).unsqueeze(0), "sample_rate": sr}


def diarise(wav, speakers=None):
    """pyannote.audio on PyTorch ROCm."""
    import torch
    from pyannote.audio import Pipeline
    # pyannote.audio 4.x renamed use_auth_token to token.
    pipe = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1",
                                    token=hf_token())
    if torch.cuda.is_available():          # ROCm presents as .cuda in PyTorch
        pipe.to(torch.device("cuda"))
        print(f"  diarisation on GPU: {torch.cuda.get_device_name(0)}", file=sys.stderr)
    else:
        print("  diarisation on CPU (no GPU visible to torch)", file=sys.stderr)
    kw = {}
    if speakers:
        kw["num_speakers"] = speakers
    out = pipe(load_waveform(wav), **kw)
    # pyannote.audio 4.x returns a DiarizeOutput dataclass wrapping the
    # Annotation; 3.x returned the Annotation directly.
    ann = getattr(out, "speaker_diarization", out)
    return [{"start": t.start, "end": t.end, "speaker": s}
            for t, _, s in ann.itertracks(yield_label=True)]


def merge(segments, turns):
    """Label each transcript segment with the speaker it overlaps most."""
    for seg in segments:
        best, best_overlap = None, 0.0
        for t in turns:
            ov = min(seg["end"], t["end"]) - max(seg["start"], t["start"])
            if ov > best_overlap:
                best, best_overlap = t["speaker"], ov
        seg["speaker"] = best or "UNKNOWN"
    return segments


def ts(x):
    h, rem = divmod(int(x), 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("--model", default="Whisper-Large-v3-Turbo")
    ap.add_argument("--speakers", type=int, default=None,
                    help="exact speaker count, if known; improves accuracy")
    ap.add_argument("--json", help="also write raw JSON here")
    a = ap.parse_args()

    print("==> converting to 16 kHz mono", file=sys.stderr)
    wav = to_wav(a.audio)
    try:
        print(f"==> transcribing via Lemonade ({a.model})", file=sys.stderr)
        segments = transcribe(wav, a.model)
        print(f"    {len(segments)} segments", file=sys.stderr)

        print("==> diarising with pyannote", file=sys.stderr)
        turns = diarise(wav, a.speakers)
        speakers = sorted({t["speaker"] for t in turns})
        print(f"    {len(turns)} turns, {len(speakers)} speakers: {', '.join(speakers)}",
              file=sys.stderr)

        merged = merge(segments, turns)
        print(file=sys.stderr)
        last = None
        for s in merged:
            if s["speaker"] != last:
                print(f"\n[{ts(s['start'])}] {s['speaker']}:")
                last = s["speaker"]
            print(f"  {s['text']}")
        if a.json:
            json.dump({"segments": merged, "turns": turns}, open(a.json, "w"), indent=2)
            print(f"\nJSON written to {a.json}", file=sys.stderr)
    finally:
        os.unlink(wav)


if __name__ == "__main__":
    main()
