#!/bin/bash
# Wrapper for whisper that outputs clean text only
# Usage: whisper-clean.sh <audio-file>

# Debug: log invocation
echo "$(date): $1" >> /tmp/whisper-debug.log

MODEL="${WHISPER_MODEL:-base}"
INPUT="$1"
OUTPUT_DIR=$(/usr/bin/mktemp -d)

# Run whisper
/Users/bruba/Library/Python/3.11/bin/whisper "$INPUT" \
  --model "$MODEL" \
  --language en \
  --output_format txt \
  --output_dir "$OUTPUT_DIR" \
  >/dev/null 2>&1

# Output just the text
BASENAME=$(/usr/bin/basename "$INPUT" | /usr/bin/sed "s/\.[^.]*$//")
RESULT=$(/bin/cat "${OUTPUT_DIR}/${BASENAME}.txt" 2>/dev/null)
echo "Result: $RESULT" >> /tmp/whisper-debug.log

# Output to stdout
echo "$RESULT"

# Cleanup
/bin/rm -rf "$OUTPUT_DIR"
