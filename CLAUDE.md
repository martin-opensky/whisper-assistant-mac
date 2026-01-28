# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Whisper Assistant is a macOS voice transcription tool that records audio via hotkey (CMD+M), transcribes using whisper.cpp with Metal GPU acceleration, optionally formats via Ollama, and pastes the result at the cursor.

## Architecture

```
Hammerspoon (init.lua)     →  ffmpeg (record)  →  whisper.cpp (transcribe)
     ↓                                                    ↓
Settings/State management                          transcribe.sh
     ↓                                                    ↓
Post-processing chooser    →  Ollama (format)   →  postprocess.sh
     ↓                                                    ↓
Paste to cursor + save transcript
```

**Key files:**
- `init.lua` - Main Hammerspoon orchestrator (~650 lines). Manages hotkey, recording state, async tasks, UI alerts, and coordinates the pipeline.
- `transcribe.sh` - Calls whisper-cli with Metal GPU. Logs to `/tmp/whisper-transcribe.log`.
- `postprocess.sh` - Calls Ollama API (llama3.2:3b) with instructions from `instructions/claudecode.md`.
- `settings.json` - User configuration (model, hotkey, audio device, language).

**Symlink setup:** Files are symlinked to `~/.hammerspoon/` so Hammerspoon can access them. The `scriptDir` variable in init.lua resolves to the symlink directory.

## Commands

```bash
# Reload Hammerspoon config after changes
# Click Hammerspoon menu → Reload Config

# Download whisper model
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" -o models/ggml-base.en.bin

# Test transcription manually
./transcribe.sh /path/to/audio.wav base.en en

# Test post-processing manually
./postprocess.sh "test input text" instructions/claudecode.md

# Check transcription logs
tail -f /tmp/whisper-transcribe.log

# Ensure Ollama is running for post-processing
ollama serve
ollama pull llama3.2:3b
```

## Key Implementation Details

**Transcription flow in init.lua:**
1. `startRecording()` - Spawns ffmpeg via `hs.task`, shows menu bar indicator
2. `stopRecording()` - Terminates ffmpeg, validates audio file size, spawns transcribe.sh
3. Transcription callback - Parses result, optionally spawns postprocess.sh
4. Final callback - Saves transcript, copies to clipboard, pastes via `hs.eventtap.keyStrokes()`

**Timeout handling:** 90-second timeout kills hung transcriptions. Progress timer updates alert with elapsed time.

**Audio fade:** Volume fades out when recording starts, fades back when recording stops (prevents hearing yourself).

**Post-processing rejection:** postprocess.sh rejects conversational responses (grep for "How can I", "It seems", etc.) and returns original text.

## Creating New Post-Processing Templates

1. Create `instructions/yourtemplate.md` with formatting rules
2. Set `"postProcessing": "yourtemplate"` in settings.json
3. The instruction file content is passed as the system prompt to Ollama

## Dependencies

- Hammerspoon (macOS automation)
- ffmpeg (audio recording)
- whisper-cpp (brew install whisper-cpp)
- Ollama with llama3.2:3b model (for post-processing)
- jq (JSON parsing in shell scripts)
