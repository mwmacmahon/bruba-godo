#!/bin/bash
# TTS wrapper script using sherpa-onnx
# Usage: tts.sh "text to speak" output.wav

set -e

TEXT="${1:-Hello, this is a test.}"
OUTPUT="${2:-/tmp/tts-output.wav}"

RUNTIME_DIR="${SHERPA_ONNX_RUNTIME_DIR:-$HOME/.clawdbot/tools/sherpa-onnx-tts/runtime}"
MODEL_DIR="${SHERPA_ONNX_MODEL_DIR:-$HOME/.clawdbot/tools/sherpa-onnx-tts/models/vits-piper-en_US-lessac-high}"

# Expand ~ in paths
RUNTIME_DIR="${RUNTIME_DIR/#\~/$HOME}"
MODEL_DIR="${MODEL_DIR/#\~/$HOME}"

# Find model files
MODEL_ONNX=$(find "$MODEL_DIR" -name "*.onnx" -not -name "*.json" | head -1)
TOKENS="$MODEL_DIR/tokens.txt"
ESPEAK_DATA="$MODEL_DIR/espeak-ng-data"

if [ ! -f "$MODEL_ONNX" ]; then
    echo "Error: Model not found in $MODEL_DIR" >&2
    exit 1
fi

# Run TTS, suppress all verbose output
"$RUNTIME_DIR/bin/sherpa-onnx-offline-tts" \
    --vits-model="$MODEL_ONNX" \
    --vits-tokens="$TOKENS" \
    --vits-data-dir="$ESPEAK_DATA" \
    --output-filename="$OUTPUT" \
    "$TEXT" > /dev/null 2>&1

echo "$OUTPUT"
