#!/usr/bin/env python3
"""
Transcribe audio file using faster-whisper
"""
import sys
import os
from faster_whisper import WhisperModel

def transcribe_audio(audio_path, model_size="small", language="en"):
    """
    Transcribe audio file using faster-whisper

    Args:
        audio_path: Path to the audio file
        model_size: Model size (tiny, base, small, medium, large)
        language: Language code (e.g., 'en')

    Returns:
        Transcribed text as string
    """
    try:
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"Audio file not found: {audio_path}")

        # Initialize model
        model = WhisperModel(model_size, device="cpu", compute_type="int8")

        # Transcribe
        segments, info = model.transcribe(audio_path, language=language, beam_size=5)

        # Collect all segments
        text = " ".join([segment.text.strip() for segment in segments])

        return text.strip()

    except Exception as e:
        print(f"Error during transcription: {e}", file=sys.stderr)
        return ""

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: transcribe.py <audio_file> [model_size] [language]", file=sys.stderr)
        sys.exit(1)

    audio_file = sys.argv[1]
    model = sys.argv[2] if len(sys.argv) > 2 else "small"
    language = sys.argv[3] if len(sys.argv) > 3 else "en"

    result = transcribe_audio(audio_file, model, language)

    if result:
        print(result)
    else:
        sys.exit(1)
