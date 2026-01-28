#!/bin/bash
#
# Transcribe audio using whisper.cpp with Metal GPU acceleration
#
# Usage: transcribe.sh <audio_file> [model_size] [language]
#
# Model sizes: tiny, base, small, medium, large (default: base)
# For English-only, use: tiny.en, base.en, small.en, medium.en
#

set -e

AUDIO_FILE="$1"
MODEL_SIZE="${2:-base.en}"
LANGUAGE="${3:-en}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/models"
WHISPER_CLI="/opt/homebrew/bin/whisper-cli"

# Map model names to filenames
case "$MODEL_SIZE" in
    tiny|tiny.en)
        MODEL_FILE="ggml-tiny.en.bin"
        ;;
    base|base.en)
        MODEL_FILE="ggml-base.en.bin"
        ;;
    small|small.en)
        MODEL_FILE="ggml-small.en.bin"
        ;;
    medium|medium.en)
        MODEL_FILE="ggml-medium.en.bin"
        ;;
    large|large-v3)
        MODEL_FILE="ggml-large-v3.bin"
        ;;
    *)
        # Allow direct model filename
        MODEL_FILE="$MODEL_SIZE"
        ;;
esac

MODEL_PATH="$MODELS_DIR/$MODEL_FILE"

# Check if audio file exists
if [ ! -f "$AUDIO_FILE" ]; then
    echo "Error: Audio file not found: $AUDIO_FILE" >&2
    exit 1
fi

# Check if model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "Error: Model not found: $MODEL_PATH" >&2
    echo "Download models from: https://huggingface.co/ggerganov/whisper.cpp" >&2
    exit 1
fi

# Check if whisper-cli exists
if [ ! -x "$WHISPER_CLI" ]; then
    echo "Error: whisper-cli not found. Install with: brew install whisper-cpp" >&2
    exit 1
fi

# Run transcription with Metal GPU acceleration
# --no-prints: suppress loading messages
# --no-timestamps: output clean text only
# -t 4: use 4 threads (good for M1)
exec "$WHISPER_CLI" \
    -m "$MODEL_PATH" \
    -f "$AUDIO_FILE" \
    -l "$LANGUAGE" \
    -t 4 \
    --no-prints \
    --no-timestamps \
    2>/dev/null
