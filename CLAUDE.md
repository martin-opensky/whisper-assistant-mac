# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current Status (2026-01-29)

**What was done:**
- Fixed critical bug where recordings were lost when transcription failed silently
- Root cause: `hs.timer.doAfter` is unreliable when Hammerspoon's chooser UI is active
- Solution: Replaced timers with `hs.task` running shell commands (`sleep 0.5 && mkdir && cp`)
- Task callbacks are reliable regardless of UI state
- Recordings now saved BEFORE transcription starts (prevents data loss)
- Added persistent logging to `whisper-assistant.log`
- Enhanced `transcribe.sh` with interactive mode (most recent recordings shown first)
- Transcripts saved alongside recordings, copied to clipboard

**The fix that worked:** In `stopRecording()`, instead of using `hs.timer.doAfter(0.5, ...)` which silently fails when the chooser is open, we now use:
```lua
hs.task.new("/bin/bash", callback, {"-c", "sleep 0.5 && mkdir -p DIR && cp FILE DIR"})
```

**Testing status:** User reported no errors since the fix was applied. Needs continued monitoring over several days to confirm stability.

## Next Steps

1. **Monitor for stability** - Use the tool normally and watch for any recurrence of the silent failure issue
2. **Performance optimization** - Consider if the 0.5s sleep delay can be reduced
3. **Potential improvements:**
   - Add notification sound on transcription complete
   - Support for multiple whisper models via settings
   - Batch re-transcription of failed recordings

## Key Files to Reference

When continuing work on this project, read these files:
- `init.lua` - Main orchestrator (~677 lines) - the `stopRecording()` function (around line 403) contains the critical fix
- `transcribe.sh` - CLI tool for manual/recovery transcription
- `settings.json` - User configuration
- `whisper-assistant.log` - Check this for debugging issues

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

# Re-transcribe a recording (interactive - lists today's recordings)
./transcribe.sh

# List today's recordings
./transcribe.sh --list

# Direct transcription of specific file
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
1. `startRecording()` - Spawns ffmpeg via `hs.task`, shows menu bar indicator, fades volume out
2. `stopRecording()` - Terminates ffmpeg, shows chooser UI, starts `saveAndTranscribeTask`
3. `saveAndTranscribeTask` (hs.task) - Shell command: `sleep 0.5 && mkdir -p && cp` saves recording
4. Task callback - Verifies audio file, spawns whisper transcription via `transcribe.sh`
5. Transcription callback - Parses result, optionally spawns `postprocess.sh` for Ollama formatting
6. Final callback - Saves transcript, copies to clipboard, pastes via `hs.eventtap.keyStrokes()`

**CRITICAL: Why hs.task instead of hs.timer:**
- `hs.timer.doAfter()` silently fails when Hammerspoon's chooser UI is active
- `hs.task` callbacks are reliable regardless of UI state
- All critical operations (save, transcribe) now use `hs.task`

**Timeout handling:** 90-second timeout kills hung transcriptions. Progress timer updates alert with elapsed time.

**Audio fade:** Volume fades out when recording starts, fades back when recording stops (prevents hearing yourself).

**Post-processing rejection:** postprocess.sh rejects conversational responses (grep for "How can I", "It seems", etc.) and returns original text.

## Creating New Post-Processing Templates

1. Create `instructions/yourtemplate.md` with formatting rules
2. Set `"postProcessing": "yourtemplate"` in settings.json
3. The instruction file content is passed as the system prompt to Ollama

## Troubleshooting & Recovery

**Log files:**
- `whisper-assistant.log` - Main application log (in script directory / ~/.hammerspoon/)
- `/tmp/whisper-transcribe.log` - Whisper transcription details

**Check logs:**
```bash
# Watch main log in real-time
tail -f ~/.hammerspoon/whisper-assistant.log

# Check whisper-specific logs
tail -f /tmp/whisper-transcribe.log
```

**Recordings are automatically saved** to `transcripts/YYYY-MM-DD/HH-MM-SS/recording.wav` immediately when recording stops. Even if transcription fails or times out, the recording is preserved.

**Re-transcribe a failed recording:**
```bash
# Interactive mode - select from today's recordings
./transcribe.sh

# List today's recordings without transcribing
./transcribe.sh --list

# Direct transcription of specific file
./transcribe.sh /path/to/recording.wav base.en en
```

**Recording cleanup:** Recordings older than 1 day are automatically deleted. Transcripts are kept for 7 days.

## Dependencies

- Hammerspoon (macOS automation)
- ffmpeg (audio recording)
- whisper-cpp (brew install whisper-cpp)
- Ollama with llama3.2:3b model (for post-processing)
- jq (JSON parsing in shell scripts)

## Git Commits and Pull Requests

**NEVER add any Claude attribution to commits or PRs.** This includes:
- No "Co-Authored-By: Claude" lines
- No "Created with Claude" or "Generated by Claude"
- No mention of AI assistance in commit messages or PR descriptions

Keep commit messages focused on what changed, not how it was created.
