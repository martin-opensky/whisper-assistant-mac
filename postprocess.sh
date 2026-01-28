#!/bin/bash
#
# Post-process transcription using Ollama (local, fast)
# Uses the instruction file for formatting rules
#
# Usage: postprocess.sh "<transcription_text>" <instruction_file>
#

set -e

TEXT="$1"
INSTRUCTION_FILE="$2"

# Configuration
OLLAMA_MODEL="llama3.2:3b"
OLLAMA_URL="http://localhost:11434/api/chat"
TIMEOUT=30

# Check if Ollama is running
if curl -s --connect-timeout 2 http://localhost:11434/api/tags >/dev/null 2>&1; then

    # Read instructions from file if provided
    if [ -f "$INSTRUCTION_FILE" ]; then
        SYSTEM_PROMPT=$(cat "$INSTRUCTION_FILE")
    else
        # Fallback to basic prompt
        SYSTEM_PROMPT="Clean up this voice transcription. Do not add anything. Do not respond conversationally. Just output the cleaned text."
    fi

    # Call Ollama API with low temperature to reduce creativity/hallucination
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
            stream: false,
            options: {
                temperature: 0.1
            }
        }')" 2>/dev/null | jq -r '.message.content // empty')

    # Check if result looks like a conversation (reject it, use original)
    if echo "$RESULT" | grep -qiE "(It seems|How can I|I'd be happy|Hello|Hi there|I haven't|I don't have|This conversation|What would you|Can you provide|Could you|start of our|I cannot|I'm unable)"; then
        echo "$TEXT"
        exit 0
    fi

    if [ -n "$RESULT" ]; then
        echo "$RESULT"
        exit 0
    fi
fi

# Fallback: return original text
echo "$TEXT"
