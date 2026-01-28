#!/bin/bash
#
# Post-process transcription using Claude Haiku via Claude Code CLI
#
# Usage: postprocess.sh "<transcription_text>" <instruction_file>
#

set -e

TEXT="$1"
INSTRUCTION_FILE="$2"

# Find claude CLI
CLAUDE_PATH="$HOME/.local/bin/claude"
if [ ! -x "$CLAUDE_PATH" ]; then
    CLAUDE_PATH=$(which claude 2>/dev/null || echo "")
fi

if [ -z "$CLAUDE_PATH" ] || [ ! -x "$CLAUDE_PATH" ]; then
    echo "Error: Claude CLI not found" >&2
    echo "$TEXT"
    exit 0
fi

# Check instruction file exists
if [ ! -f "$INSTRUCTION_FILE" ]; then
    echo "Error: Instruction file not found: $INSTRUCTION_FILE" >&2
    echo "$TEXT"
    exit 0
fi

# Read instructions
INSTRUCTIONS=$(cat "$INSTRUCTION_FILE")

# Build full prompt
FULL_PROMPT="${INSTRUCTIONS}

## Transcription to format:

${TEXT}"

# Call Claude Haiku via Claude Code CLI
# --output-format text returns raw text directly
# --model haiku is fast and follows instructions well
# --no-session-persistence avoids session overhead
RESULT=$("$CLAUDE_PATH" -p "$FULL_PROMPT" \
    --model haiku \
    --output-format text \
    --no-session-persistence \
    2>/dev/null) || {
    echo "Error: Claude CLI failed" >&2
    echo "$TEXT"
    exit 0
}

# Return result (or original text if empty)
if [ -n "$RESULT" ]; then
    # Remove markdown code block wrappers (```markdown or ``` at start/end)
    # Remove opening ``` or ```markdown line
    RESULT=$(echo "$RESULT" | sed '1{/^```/d;}')
    # Remove closing ``` line
    RESULT=$(echo "$RESULT" | sed '${/^```$/d;}')
    echo "$RESULT"
else
    echo "$TEXT"
fi
