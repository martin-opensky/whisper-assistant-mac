#!/usr/bin/env python3
"""
Post-process transcription using Claude Haiku
"""
import sys
import os
import subprocess
import json

def postprocess(text, instruction_file):
    """
    Post-process transcription text using Claude Code CLI

    Args:
        text: The transcribed text to process
        instruction_file: Path to the instruction file

    Returns:
        Processed text from Claude
    """
    # Read instructions
    try:
        with open(instruction_file, 'r') as f:
            instructions = f.read()
    except FileNotFoundError:
        print(f"Error: Instruction file not found: {instruction_file}", file=sys.stderr)
        return text
    except Exception as e:
        print(f"Error reading instruction file: {e}", file=sys.stderr)
        return text

    # Build the full prompt
    full_prompt = f"{instructions}\n\n## Transcription to format:\n\n{text}"

    # Call Claude Code CLI
    # Use full path since Hammerspoon may not have claude in PATH
    claude_path = os.path.expanduser("~/.local/bin/claude")
    if not os.path.exists(claude_path):
        claude_path = "claude"  # Fall back to PATH if not in standard location

    try:
        result = subprocess.run(
            [
                claude_path,
                "-p",
                full_prompt,
                "--model", "haiku",
                "--output-format", "json",
                "--no-session-persistence"
            ],
            capture_output=True,
            text=True,
            timeout=30  # 30 second timeout
        )

        # Check for errors
        if result.returncode != 0:
            print(f"Error calling Claude CLI: {result.stderr}", file=sys.stderr)
            return text

        # Debug: print raw output
        print(f"DEBUG: Claude CLI stdout length: {len(result.stdout)}", file=sys.stderr)

        # Parse JSON response
        try:
            response_json = json.loads(result.stdout)
            if 'result' not in response_json:
                print(f"ERROR: 'result' key not found in JSON response. Keys: {list(response_json.keys())}", file=sys.stderr)
                return text

            processed_text = response_json['result']
            print(f"DEBUG: Processed text length: {len(processed_text)}", file=sys.stderr)
            return processed_text
        except json.JSONDecodeError as e:
            print(f"ERROR: Failed to parse JSON: {e}", file=sys.stderr)
            print(f"Raw output: {result.stdout[:500]}", file=sys.stderr)
            return text

    except subprocess.TimeoutExpired:
        print("ERROR: Claude CLI call timed out", file=sys.stderr)
        return text
    except Exception as e:
        print(f"ERROR: Unexpected error calling Claude CLI: {e}", file=sys.stderr)
        return text

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: postprocess.py <transcription_text> <instruction_file>", file=sys.stderr)
        sys.exit(1)

    text = sys.argv[1]
    instruction_file = sys.argv[2]

    result = postprocess(text, instruction_file)
    print(result)
