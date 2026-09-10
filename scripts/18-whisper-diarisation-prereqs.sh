#!/bin/bash
# Prerequisites for the diarisation stack.
#
# Transcription is handled by whisper.cpp (ROCm/Vulkan) or the NPU via Lemonade.
# Diarisation needs pyannote.audio, which is PyTorch based and therefore has
# genuine ROCm support, unlike CTranslate2 (CUDA/CPU only), which is why stock
# WhisperX would transcribe on the CPU here.
set -euo pipefail

echo "==> Installing ffmpeg and Python venv tooling"
apt-get install -y ffmpeg python3-venv python3-pip

echo
echo "==> Versions"
ffmpeg -version 2>/dev/null | head -1 | sed 's/^/    /'
python3 --version | sed 's/^/    /'
echo
echo "  Next step runs as your normal user, no root needed."
