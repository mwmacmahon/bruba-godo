#!/bin/bash
# Show voice configuration status
# Usage: voice-status.sh

set -e

CONFIG_FILE="$HOME/.clawdbot/clawdbot.json"
MODELS_DIR="$HOME/.clawdbot/tools/sherpa-onnx-tts/models"

echo "=== Voice Configuration Status ==="
echo ""

# Whisper model
echo "Speech-to-Text (Whisper):"
whisper_model=$(python3 -c "
import json
with open(\"$CONFIG_FILE\") as f:
    config = json.load(f)
args = config.get(\"tools\", {}).get(\"media\", {}).get(\"audio\", {}).get(\"models\", [{}])[0].get(\"args\", [])
for i, arg in enumerate(args):
    if arg == \"--model\" and i+1 < len(args):
        print(args[i+1])
        break
else:
    print(\"not configured\")
")
echo "  Model: $whisper_model (only model installed)"
echo ""

# TTS voice
echo "Text-to-Speech (sherpa-onnx):"
tts_voice=$(python3 -c "
import json
import os
with open(\"$CONFIG_FILE\") as f:
    config = json.load(f)
model_dir = config.get(\"skills\", {}).get(\"entries\", {}).get(\"sherpa-onnx-tts\", {}).get(\"env\", {}).get(\"SHERPA_ONNX_MODEL_DIR\", \"\")
model_dir = os.path.expanduser(model_dir)
print(os.path.basename(model_dir) if model_dir else \"not configured\")
")
echo "  Voice: $tts_voice"
echo ""

# Runtime check
echo "Runtime Status:"
if [ -f "$HOME/.clawdbot/tools/sherpa-onnx-tts/runtime/bin/sherpa-onnx-offline-tts" ]; then
    echo "  sherpa-onnx: installed"
else
    echo "  sherpa-onnx: NOT FOUND"
fi

if command -v whisper &>/dev/null; then
    echo "  whisper: installed"
else
    echo "  whisper: NOT FOUND"
fi
echo ""

echo "Usage:"
echo "  ~/clawd/tools/tts.sh \"text\" /tmp/output.wav"
echo "  /usr/bin/afplay /tmp/output.wav"
