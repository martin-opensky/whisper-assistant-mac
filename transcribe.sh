#!/bin/bash
#
# Transcribe audio using whisper.cpp with Metal GPU acceleration
#
# Usage:
#   transcribe.sh                        # Interactive mode - select from today's recordings
#   transcribe.sh --list                 # List today's recordings
#   transcribe.sh <audio_file> [model] [language]  # Direct transcription
#
# Model sizes: tiny, base, small, medium, large (default: base)
# For English-only, use: tiny.en, base.en, small.en, medium.en
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRANSCRIPTS_DIR="$SCRIPT_DIR/transcripts"
TODAY=$(date +%Y-%m-%d)

# Function to list today's recordings (display only, most recent first)
list_recordings() {
    local today_dir="$TRANSCRIPTS_DIR/$TODAY"
    if [ ! -d "$today_dir" ]; then
        echo "No recordings found for today ($TODAY)"
        return 1
    fi

    local count=0
    local i=1

    echo ""
    echo "Today's recordings ($TODAY) - most recent first:"
    echo "-------------------------------------------------"

    # Get directories sorted by name in reverse order (most recent first)
    for time_dir in $(ls -1dr "$today_dir"/*/  2>/dev/null); do
        [ -d "$time_dir" ] || continue
        local wav_file="$time_dir/recording.wav"
        if [ -f "$wav_file" ]; then
            local time_name=$(basename "$time_dir")
            local size=$(stat -f%z "$wav_file" 2>/dev/null || stat -c%s "$wav_file" 2>/dev/null)
            local size_kb=$((size / 1024))
            local has_transcript=""
            [ -f "$time_dir/transcript.md" ] && has_transcript=" [transcribed]"
            echo "  $i) $time_name - ${size_kb}KB${has_transcript}"
            ((i++))
            ((count++))
        fi
    done

    if [ $count -eq 0 ]; then
        echo "  No recordings found"
        return 1
    fi

    echo ""
}

# Function for interactive selection (most recent first)
interactive_select() {
    local today_dir="$TRANSCRIPTS_DIR/$TODAY"
    if [ ! -d "$today_dir" ]; then
        echo "No recordings found for today ($TODAY)"
        exit 1
    fi

    local recordings=()
    local i=1

    echo ""
    echo "Today's recordings ($TODAY) - most recent first:"
    echo "-------------------------------------------------"

    # Get directories sorted by name in reverse order (most recent first)
    for time_dir in $(ls -1dr "$today_dir"/*/  2>/dev/null); do
        [ -d "$time_dir" ] || continue
        local wav_file="$time_dir/recording.wav"
        if [ -f "$wav_file" ]; then
            local time_name=$(basename "$time_dir")
            local size=$(stat -f%z "$wav_file" 2>/dev/null || stat -c%s "$wav_file" 2>/dev/null)
            local size_kb=$((size / 1024))
            local has_transcript=""
            [ -f "$time_dir/transcript.md" ] && has_transcript=" [transcribed]"
            echo "  $i) $time_name - ${size_kb}KB${has_transcript}"
            recordings+=("$wav_file")
            ((i++))
        fi
    done

    if [ ${#recordings[@]} -eq 0 ]; then
        echo "No recordings found for today"
        exit 1
    fi

    echo ""
    read -p "Select recording (1-${#recordings[@]}): " selection

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#recordings[@]} ]; then
        echo "Invalid selection"
        exit 1
    fi

    AUDIO_FILE="${recordings[$((selection-1))]}"
    echo ""
    echo "Selected: $AUDIO_FILE"
    echo ""
}

# Handle --list flag
if [ "$1" = "--list" ]; then
    list_recordings
    exit 0
fi

# Track if we're in interactive mode (to save transcript and copy to clipboard)
INTERACTIVE_MODE=false

# Interactive mode if no arguments
if [ -z "$1" ]; then
    interactive_select
    INTERACTIVE_MODE=true
    MODEL_SIZE="base.en"
    LANGUAGE="en"
else
    AUDIO_FILE="$1"
    MODEL_SIZE="${2:-base.en}"
    LANGUAGE="${3:-en}"
fi
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

# In interactive mode: save transcript and copy to clipboard
if [ "$INTERACTIVE_MODE" = true ]; then
    # Get the directory containing the recording
    RECORDING_DIR=$(dirname "$AUDIO_FILE")
    TRANSCRIPT_FILE="$RECORDING_DIR/transcript.md"

    # Save transcript
    echo "$RESULT" > "$TRANSCRIPT_FILE"
    log "Transcript saved to: $TRANSCRIPT_FILE"
    echo ""
    echo "[Saved to: $TRANSCRIPT_FILE]"

    # Copy to clipboard (macOS)
    echo "$RESULT" | pbcopy
    echo "[Copied to clipboard]"
fi
