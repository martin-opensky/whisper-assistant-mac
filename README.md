# Whisper Assistant for Mac

A powerful voice transcription tool for macOS that lets you record audio with a hotkey, transcribe it using OpenAI's Whisper, and automatically format it for use with AI coding assistants like Claude Code.

## Features

- 🎤 **Toggle recording with a hotkey** - Start/stop recording with CMD+M (customizable)
- 🔴 **Visual feedback** - Menu bar indicator while recording
- 📝 **Fast transcription** - Uses faster-whisper for local, offline transcription
- 🤖 **AI post-processing** - Optional formatting of transcripts using Claude Code CLI
- ⌨️ **Auto-paste** - Transcribed text automatically pasted at cursor position
- 💾 **Save history** - All transcripts saved to markdown files with timestamps
- ⚙️ **Configurable** - Customize model, language, hotkey, and more

## How It Works

```
┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│   Hammerspoon       │────▶│  ffmpeg          │────▶│  faster-whisper     │
│   (Hotkey/UI)       │     │  (Record audio)  │     │  (Transcribe)       │
└─────────────────────┘     └──────────────────┘     └─────────────────────┘
         │                                                     │
         │                                                     ▼
         │                                            ┌─────────────────────┐
         │                                            │  Claude Code CLI    │
         │                                            │  (Format prompt)    │
         │                                            └─────────────────────┘
         │                                                     │
         │                                                     ▼
         │                                            ┌─────────────────────┐
         └────────────────────────────────────────────▶  Paste to cursor   │
                                                      └─────────────────────┘
```

## Prerequisites

Before you begin, ensure you have:

- **macOS** (tested on macOS 10.14+)
- **Homebrew** - Package manager for macOS ([install here](https://brew.sh/))
- **Python 3.8+** - Usually pre-installed on macOS

## Installation

### Step 1: Install Hammerspoon

Hammerspoon is a powerful macOS automation tool that provides the hotkey and UI functionality.

```bash
brew install --cask hammerspoon
```

After installation:
1. Open Hammerspoon from Applications
2. Grant it **Accessibility** and **Microphone** permissions when prompted
3. Click "Enable Accessibility" in System Preferences → Security & Privacy

### Step 2: Install ffmpeg

ffmpeg is used to capture audio from your microphone.

```bash
brew install ffmpeg
```

Verify installation:
```bash
ffmpeg -version
```

### Step 3: Clone This Repository

```bash
cd ~/
git clone https://github.com/martin-opensky/whisper-assistant-mac.git
cd whisper-assistant-mac
```

### Step 4: Set Up Python Virtual Environment

Create and activate a Python virtual environment:

```bash
python3 -m venv venv
source venv/bin/activate
```

Install required Python packages:

```bash
pip install faster-whisper
```

The `faster-whisper` package will download the Whisper model on first use (~500MB for the small model).

### Step 5: Install Claude Code CLI (Optional but Recommended)

If you want AI-powered post-processing to format your transcriptions into structured prompts:

```bash
# Install Claude Code CLI
curl -fsSL https://raw.githubusercontent.com/anthropics/claude-code/main/install.sh | sh
```

Login to Claude Code:
```bash
claude login
```

This requires a Claude Code subscription (Free, Pro, or Max plan).

> **Note:** Post-processing uses your Claude Code CLI usage. If you have a Max plan ($200/month), you get unlimited CLI usage. Free and Pro plans have monthly limits.

### Step 6: Link to Hammerspoon

Create symlinks to make the scripts accessible to Hammerspoon:

```bash
# Create the necessary symlinks
ln -sf ~/whisper-assistant-mac/init.lua ~/.hammerspoon/init.lua
ln -sf ~/whisper-assistant-mac/transcribe.py ~/.hammerspoon/transcribe.py
ln -sf ~/whisper-assistant-mac/postprocess.py ~/.hammerspoon/postprocess.py
ln -sf ~/whisper-assistant-mac/settings.json ~/.hammerspoon/settings.json
ln -sf ~/whisper-assistant-mac/instructions ~/.hammerspoon/instructions
ln -sf ~/whisper-assistant-mac/transcripts ~/.hammerspoon/transcripts
ln -sf ~/whisper-assistant-mac/venv ~/.hammerspoon/venv
```

### Step 7: Reload Hammerspoon

Reload the Hammerspoon configuration:
1. Click the Hammerspoon menu bar icon
2. Select "Reload Config"
3. You should see an alert: "Voice transcription loaded: cmd+m"

## Configuration

Edit `settings.json` to customize the behavior:

```json
{
  "model": "small",
  "audioDevice": ":1",
  "hotkey": {
    "modifiers": ["cmd"],
    "key": "m"
  },
  "language": "en",
  "postProcessing": "claudecode"
}
```

### Configuration Options

| Option | Description | Values |
|--------|-------------|--------|
| `model` | Whisper model size | `tiny`, `base`, `small`, `medium`, `large` |
| `audioDevice` | Audio input device | `:0` (default mic), `:1` (external mic) |
| `hotkey.modifiers` | Keyboard modifiers | `["cmd"]`, `["cmd", "shift"]`, etc. |
| `hotkey.key` | Hotkey key | Any letter key like `"m"` |
| `language` | Transcription language | `en`, `es`, `fr`, etc. |
| `postProcessing` | Post-processing template | `claudecode` or remove this field to disable |

### Whisper Model Sizes

| Model | Speed | Accuracy | Size | Use Case |
|-------|-------|----------|------|----------|
| `tiny` | Fastest | Lowest | ~75 MB | Quick notes |
| `base` | Fast | Decent | ~150 MB | General use |
| `small` | Balanced | Good | ~500 MB | **Recommended** |
| `medium` | Slower | Better | ~1.5 GB | High accuracy needed |
| `large` | Slowest | Best | ~3 GB | Maximum accuracy |

### Finding Your Audio Device

To list available audio devices:

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

Look for your microphone in the output and use the device number in `audioDevice` (e.g., `:0` or `:1`).

## Usage

### Basic Transcription

1. **Start Recording**: Press **CMD + M** (or your configured hotkey)
   - A red dot 🔴 appears in the menu bar
   - Alert shows "🎤 Recording..."

2. **Stop Recording**: Press **CMD + M** again
   - Recording stops and processing begins
   - Alert shows "⏸️ Processing..."

3. **Done**:
   - Alert shows "✓ Transcribed & Processed"
   - Transcribed (and formatted) text is pasted at your cursor
   - Text is copied to your clipboard
   - Transcript saved to `transcripts/YYYY-MM-DD_HH-MM-SS.md`

### Post-Processing with Claude Code

When `postProcessing` is enabled in settings, your transcriptions are automatically formatted using Claude Code before being pasted. This is especially useful for:

- **Coding tasks**: Converts rambling voice notes into structured development prompts
- **Documentation**: Cleans up filler words and formats as proper markdown
- **Instructions**: Extracts action items and requirements

Example:

**Raw Transcription:**
> "Um, so I want to, like, add a login feature to the app with, you know, email validation and stuff"

**After Claude Code Processing:**
```markdown
## Objective
Add login feature with email validation

## Requirements
- Implement user authentication
- Add email validation
- Integrate with existing application

## Next Steps
- Clarify technology stack
- Determine session management approach
```

### Disabling Post-Processing

To use raw transcription without AI formatting:

1. Edit `settings.json`
2. Remove the `"postProcessing": "claudecode"` line
3. Reload Hammerspoon config

## File Structure

```
whisper-assistant-mac/
├── init.lua              # Main Hammerspoon script
├── transcribe.py         # Whisper transcription script
├── postprocess.py        # Claude Code post-processing script
├── settings.json         # Configuration file
├── instructions/         # Post-processing templates
│   └── claudecode.md     # Claude Code formatting instructions
├── transcripts/          # Saved transcripts (auto-created)
│   └── 2026-01-22_14-30-45.md
├── venv/                 # Python virtual environment
└── README.md            # This file
```

## Troubleshooting

### Microphone Not Working

**Problem:** No audio is recorded or "Audio file too small" error

**Solution:**
1. Check microphone permissions:
   - System Preferences → Security & Privacy → Privacy → Microphone
   - Ensure Hammerspoon is checked

2. Test your audio device:
   ```bash
   ffmpeg -f avfoundation -list_devices true -i ""
   ```

3. Try different audio device numbers in `settings.json` (`":0"`, `":1"`, etc.)

### Transcription Fails

**Problem:** "❌ Transcription failed" alert appears

**Solution:**
1. Verify faster-whisper is installed:
   ```bash
   source venv/bin/activate
   python -c "import faster_whisper; print('OK')"
   ```

2. Check the Hammerspoon Console for detailed errors:
   - Click Hammerspoon menu bar icon → Console

3. Ensure sufficient disk space for model downloads (~500MB)

### Post-Processing Not Working

**Problem:** Transcriptions aren't being formatted, just raw text

**Solution:**
1. Verify Claude Code CLI is installed and logged in:
   ```bash
   which claude
   claude --version
   claude auth status
   ```

2. Check if you have Claude Code usage remaining (for non-Max plans)

3. Look for errors in Hammerspoon Console

4. Test the postprocess script manually:
   ```bash
   source venv/bin/activate
   ./postprocess.py "test text" instructions/claudecode.md
   ```

### Text Not Pasting

**Problem:** Transcription completes but text doesn't appear at cursor

**Solution:**
1. Grant Accessibility permissions:
   - System Preferences → Security & Privacy → Privacy → Accessibility
   - Ensure Hammerspoon is checked

2. Try clicking in the target application first to ensure it has focus

3. Check if the app accepts keyboard input (some apps block programmatic typing)

### Model Download Fails

**Problem:** First run takes forever or fails when downloading model

**Solution:**
- Ensure stable internet connection
- Check disk space (~500MB for small model)
- Models are cached in `~/.cache/huggingface/`
- Manually pre-download:
  ```bash
  source venv/bin/activate
  python -c "from faster_whisper import WhisperModel; WhisperModel('small')"
  ```

## Advanced Usage

### Custom Post-Processing Instructions

Create your own formatting templates:

1. Create a new file in `instructions/` (e.g., `custom.md`)
2. Write instructions for how to format the transcription
3. Update `settings.json`:
   ```json
   "postProcessing": "custom"
   ```

Example `instructions/custom.md`:
```markdown
# Custom Formatter

Format the transcription as bullet points.
Remove filler words.
Make it concise.
```

### Testing Transcription Manually

```bash
source venv/bin/activate

# Record 5 seconds of audio
ffmpeg -f avfoundation -i ":1" -ar 16000 -ac 1 -t 5 test.wav

# Transcribe it
./transcribe.py test.wav small en

# Post-process it
./postprocess.py "your transcription text" instructions/claudecode.md
```

### Multiple Hotkeys

You can set up multiple configurations with different hotkeys by:
1. Creating separate settings files
2. Modifying `init.lua` to load different settings for different hotkeys

### Debugging

Enable detailed logging:

1. Open Hammerspoon Console (Hammerspoon menu → Console)
2. All events are logged here with timestamps
3. Look for error messages in red

For Python script debugging:
```bash
source venv/bin/activate
python transcribe.py <audio_file> small en
```

## Cost & Usage

### Whisper Transcription
- **100% FREE** - Runs locally on your Mac
- No API calls, no usage limits
- No internet required after initial model download

### Claude Code Post-Processing
- **Requires Claude Code subscription**
- Free plan: Limited CLI usage per month
- Pro plan ($20/month): Higher CLI usage limits
- Max plan ($200/month): **Unlimited CLI usage**
- Only used when `postProcessing` is enabled

> This tool uses the Claude Code **CLI** (included in your subscription), NOT the Anthropic API (which has separate billing).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - See LICENSE file for details

## Credits

Built with:
- [Hammerspoon](https://www.hammerspoon.org/) - macOS automation framework
- [faster-whisper](https://github.com/guillaumekln/faster-whisper) - Fast Whisper implementation
- [ffmpeg](https://ffmpeg.org/) - Audio recording and processing
- [Claude Code](https://claude.com/claude-code) - AI-powered text formatting

## Support

- **Issues**: [GitHub Issues](https://github.com/martin-opensky/whisper-assistant-mac/issues)
- **Discussions**: [GitHub Discussions](https://github.com/martin-opensky/whisper-assistant-mac/discussions)

---

Made with ❤️ for developers who think faster than they type
