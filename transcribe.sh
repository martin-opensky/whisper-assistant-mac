#!/bin/bash
#
# Transcribe audio using whisper.cpp with Metal GPU acceleration
#
# Usage: transcribe.sh <audio_file> [model_size] [language]
#
# Model sizes: tiny, base, small, medium, large (default: base)
# For English-only, use: tiny.en, base.en, small.en, medium.en
#

AUDIO_FILE="$1"
MODEL_SIZE="${2:-base.en}"
LANGUAGE="${3:-en}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/models"
WHISPER_CLI="/opt/homebrew/bin/whisper-cli"
LOG_FILE="/tmp/whisper-transcribe.log"

# Log function - writes to stderr (captured by Hammerspoon) and log file
log() {
    echo "[$(date '+%H:%M:%S')] $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

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
        MODEL_FILE="$MODEL_SIZE"
        ;;
esac

MODEL_PATH="$MODELS_DIR/$MODEL_FILE"

log "Starting transcription: model=$MODEL_SIZE, audio=$AUDIO_FILE"

# Check if audio file exists and has content
if [ ! -f "$AUDIO_FILE" ]; then
    log "ERROR: Audio file not found: $AUDIO_FILE"
    exit 1
fi

AUDIO_SIZE=$(stat -f%z "$AUDIO_FILE" 2>/dev/null || stat -c%s "$AUDIO_FILE" 2>/dev/null)
log "Audio file size: $AUDIO_SIZE bytes"

if [ "$AUDIO_SIZE" -lt 1000 ]; then
    log "ERROR: Audio file too small ($AUDIO_SIZE bytes), likely no speech recorded"
    exit 1
fi

# Check if model exists
if [ ! -f "$MODEL_PATH" ]; then
    log "ERROR: Model not found: $MODEL_PATH"
    log "Download with: curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_FILE -o $MODEL_PATH"
    exit 1
fi

# Check if whisper-cli exists
if [ ! -x "$WHISPER_CLI" ]; then
    log "ERROR: whisper-cli not found at $WHISPER_CLI"
    log "Install with: brew install whisper-cpp"
    exit 1
fi

# Run transcription with Metal GPU acceleration
# Capture both stdout and stderr
log "Running whisper-cli..."
START_TIME=$(date +%s)

TEMP_ERR=$(mktemp)
RESULT=$("$WHISPER_CLI" \
    -m "$MODEL_PATH" \
    -f "$AUDIO_FILE" \
    -l "$LANGUAGE" \
    -t 4 \
    --no-prints \
    --no-timestamps \
    2>"$TEMP_ERR")

EXIT_CODE=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Check for errors
if [ $EXIT_CODE -ne 0 ]; then
    log "ERROR: whisper-cli failed with exit code $EXIT_CODE"
    log "stderr: $(cat "$TEMP_ERR")"
    rm -f "$TEMP_ERR"
    exit $EXIT_CODE
fi

# Check if result is empty
if [ -z "$RESULT" ] || [ "$RESULT" = " " ]; then
    log "WARNING: Transcription returned empty result"
    # Check stderr for clues
    STDERR_CONTENT=$(cat "$TEMP_ERR")
    if [ -n "$STDERR_CONTENT" ]; then
        log "stderr output: $STDERR_CONTENT"
    fi
    rm -f "$TEMP_ERR"
    exit 1
fi

rm -f "$TEMP_ERR"

# Output result
CHAR_COUNT=${#RESULT}
log "Transcription complete: ${DURATION}s, ${CHAR_COUNT} chars"
echo "$RESULT"
