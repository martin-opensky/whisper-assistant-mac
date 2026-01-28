#!/bin/bash
#
# Post-process transcription using Ollama (local, fast)
# Falls back to Claude CLI if Ollama is unavailable
#
# Usage: postprocess.sh "<transcription_text>" <instruction_file>
#

set -e

TEXT="$1"
INSTRUCTION_FILE="$2"

# Configuration
OLLAMA_MODEL="qwen2.5:1.5b"
OLLAMA_URL="http://localhost:11434/api/chat"
TIMEOUT=30

# Check if Ollama is running
if curl -s --connect-timeout 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
    # Use Ollama (fast, local)

    # Read instructions and extract just the core formatting rules
    # Use a simplified system prompt for speed
    SYSTEM_PROMPT="You are a text formatter for voice transcriptions. Convert the input into a structured task format.

Rules:
- Output ONLY the formatted result, no explanations
- Never ask questions or request clarification
- Extract the actionable task from the voice input

Output format:
## Task
[Clear, concise task description]

## Requirements
- [Key requirement 1]
- [Key requirement 2]

If the input is casual/non-technical, just clean it up and return it directly."

    # Call Ollama API
    RESULT=$(curl -s --max-time "$TIMEOUT" "$OLLAMA_URL" -d "$(jq -n \
        --arg model "$OLLAMA_MODEL" \
        --arg system "$SYSTEM_PROMPT" \
        --arg text "$TEXT" \
        '{
            model: $model,
            messages: [
                {role: "system", content: $system},
                {role: "user", content: $text}
            ],
            stream: false
        }')" 2>/dev/null | jq -r '.message.content // empty')

    if [ -n "$RESULT" ]; then
        echo "$RESULT"
        exit 0
    fi

    echo "Warning: Ollama returned empty, falling back to original" >&2
fi

# Fallback: return original text if Ollama unavailable or failed
echo "$TEXT"
