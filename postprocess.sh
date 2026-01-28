#!/bin/bash
#
# Post-process transcription using Ollama (local, fast)
# Uses llama3.2:3b for good quality/speed balance
#
# Usage: postprocess.sh "<transcription_text>" <instruction_file>
#

set -e

TEXT="$1"
INSTRUCTION_FILE="$2"

# Configuration - llama3.2:3b offers best quality/speed balance
OLLAMA_MODEL="llama3.2:3b"
OLLAMA_URL="http://localhost:11434/api/chat"
TIMEOUT=30

# Check if Ollama is running
if curl -s --connect-timeout 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
    # Use Ollama (fast, local)

    SYSTEM_PROMPT="Convert voice transcriptions into this EXACT format:

## Task
[One clear sentence describing what needs to be done]

## Problem
[What is currently broken or wrong]

## Goal
[What should happen when this is fixed]

## Requirements
- [Specific step or requirement 1]
- [Specific step or requirement 2]
- [Specific step or requirement 3]

Rules:
- Output ONLY the formatted text above, nothing else
- No explanations, no questions, no preamble
- Keep each section concise (1-2 sentences max)
- If input is casual/non-technical, just clean it up and return it directly without the format"

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
