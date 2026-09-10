# 08. Speech: transcription with speaker diarisation, on AMD

## What this produces

```bash
~/whisper-diarise/bin/python scripts/diarise.py recording.m4a --speakers 2
```

```
[00:00:00] SPEAKER_01:
  Good morning. I wanted to walk through the benchmark
  results from the Strix Halo machine before we decide on the
  default model.

[00:00:07] SPEAKER_00:
  Yes, go ahead. I am particularly interested in whether the
  mixture of experts models really are that much faster than
  the dense ones.
```

Who said what, with timestamps, both stages GPU accelerated. `--speakers N` is optional and improves accuracy when the count is known. `--json out.json` writes raw segments and turns. Any format ffmpeg reads works as input.

## Why not WhisperX

WhisperX is the tool everyone recommends for this. **On AMD hardware it transcribes on the CPU**, and this is the single most useful thing in this document if you are on Strix Halo.

WhisperX is built on faster-whisper, which is built on CTranslate2. **CTranslate2 has no ROCm backend.** It supports CUDA and CPU only. So stock WhisperX runs its transcription stage on the CPU on any AMD GPU, no matter what else is configured, and only the pyannote diarisation stage sees the GPU.

The community workaround is a patched `ctranslate2-rocm` fork, compiled for a specific GPU architecture, which means an unofficial build of a core dependency that has to be rebuilt for `gfx1151`. It works for people who have done it. It is fragile, and it puts a fork at the bottom of the stack.

The alternative used here gets full GPU acceleration from entirely official components:

| Stage | Component | Runs on |
|---|---|---|
| Transcription | whisper.cpp via Lemonade, `Whisper-Large-v3-Turbo` | GPU, the `gfx1151` ROCm build |
| Diarisation | pyannote.audio 4.0.7 on PyTorch 2.14.0+rocm7.2 | GPU, verified as Radeon 8060S |
| Merge | maximal time overlap per segment | CPU, trivial |

whisper.cpp has real ROCm and Vulkan builds. pyannote is PyTorch, and PyTorch has genuine ROCm support with `cp314` wheels on the `rocm7.2` index, so Python 3.14 is fine. The only thing given up is WhisperX's merge step, which `diarise.py` reimplements in about fifteen lines.

## Setup

**Prerequisites**, script `18-whisper-diarisation-prereqs.sh`:

```bash
sudo apt install -y ffmpeg python3-venv python3-pip
```

**The venv:**

```bash
python3 -m venv ~/whisper-diarise
~/whisper-diarise/bin/pip install --index-url https://download.pytorch.org/whl/rocm7.2 torch torchaudio
~/whisper-diarise/bin/pip install pyannote.audio
```

The torch wheel is 6.2 GB and the venv ends up around 16 GB, almost entirely PyTorch. On a machine with 30 GiB of system RAM that is worth knowing exists.

**HuggingFace token.** pyannote's models are gated. You need to:

1. Accept the terms, logged in, on [pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1) and [pyannote/segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0)
2. Create a token and put it in `~/.config/hf/token` (mode 600) or `HF_TOKEN`

A valid token still gets 403s until the terms are accepted. Check with:

```bash
curl -s -H "Authorization: Bearer $(cat ~/.config/hf/token)" \
  https://huggingface.co/api/models/pyannote/speaker-diarization-3.1 -o /dev/null -w '%{http_code}\n'
```

200 means both token and terms are good.

**Transcription** comes from Lemonade's `whispercpp:rocm` backend and the `Whisper-Large-v3-Turbo` model. See [Lemonade](07-lemonade.md). Pin it so it stays warm; `whisper-server` is 95 MB resident.

## Three things that broke and how they were handled

**pyannote.audio 4.x renamed `use_auth_token` to `token`** in `Pipeline.from_pretrained`. Every tutorial uses the old name.

**pyannote 4.x returns a `DiarizeOutput` dataclass**, not an `Annotation`. The annotation is at `.speaker_diarization`, with `.exclusive_speaker_diarization` alongside. `diarise.py` unwraps whichever it gets.

**torchcodec's shared library fails to load** in this venv, so pyannote's built-in audio decoding is broken. pyannote's own documented workaround is to pass audio in memory as `{"waveform": tensor, "sample_rate": int}`. `diarise.py` reads the 16 kHz mono wav with the standard library and does exactly that. It removes a dependency rather than adding one.

## The NPU cannot diarise

`whisper-v3-turbo-FLM` transcribes correctly on the NPU and leaves the GPU entirely free, which sounds ideal for running pyannote alongside. But its backend returns only `{model, text}`. No segments, no words, no timestamps, whatever `response_format` or `timestamp_granularities` is requested. Diarisation needs timestamps to align speaker turns against, so there is nothing to merge.

`diarise.py` checks for this and fails with an explicit message rather than silently labelling everything `UNKNOWN`. The NPU path remains fine for plain transcription.

## Verification

Tested against a synthetic conversation built with Lemonade's kokoro TTS: four turns in two distinct voices, with turns two and three deliberately the same voice. pyannote correctly found two speakers and correctly **merged the two consecutive same-voice turns into one speaker** rather than splitting on the pause between them. That is a stronger test than alternating voices, because it shows clustering by voice identity rather than by silence. Turn boundaries landed within 0.5 s of the true cut points.

## Related capabilities

Moonshine, also through Lemonade, does **streaming** ASR, which Whisper cannot: real-time transcription rather than batch. `Moonshine-Small-Streaming` is 430 MB and produced a correct transcript of the same test audio.
