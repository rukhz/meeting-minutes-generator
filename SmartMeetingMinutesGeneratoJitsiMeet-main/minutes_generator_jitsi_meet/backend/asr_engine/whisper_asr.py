"""
ASR Engine (Module 3): Speech-to-text using Whisper.
Accepts live or recorded audio streams, converts to time-stamped transcript.
Supports multi-speaker when combined with diarization.
"""
import os
import logging
import shutil
import importlib
from typing import Any

logger = logging.getLogger(__name__)

try:
    import whisper
except ImportError:
    whisper = None

_whisper_model = None


def _ensure_ffmpeg_available() -> None:
    """Ensure ffmpeg executable is available for Whisper on all platforms."""
    if shutil.which("ffmpeg"):
        return
    try:
        import imageio_ffmpeg

        ffmpeg_bin = imageio_ffmpeg.get_ffmpeg_exe()
        ffmpeg_dir = os.path.dirname(ffmpeg_bin)
        current_path = os.environ.get("PATH", "")
        if ffmpeg_dir and ffmpeg_dir not in current_path:
            os.environ["PATH"] = f"{ffmpeg_dir}{os.pathsep}{current_path}"
    except Exception as e:
        logger.warning("ffmpeg auto-detection failed: %s", e)


def get_model():
    """Lazily load Whisper model."""
    global whisper
    global _whisper_model
    if whisper is None:
        try:
            whisper = importlib.import_module("whisper")
        except Exception:
            whisper = None
    if whisper is None:
        raise RuntimeError(
            "Whisper not installed. pip install openai-whisper"
        )
    if _whisper_model is None:
        model_name = os.environ.get("WHISPER_MODEL", "base")
        _whisper_model = whisper.load_model(model_name)
    return _whisper_model


def transcribe(audio_path: str, language: str | None = None) -> dict[str, Any]:
    """
    Transcribe audio file to text with time-stamped segments.
    Returns structured transcript JSON suitable for NLP pipeline.
    """
    _ensure_ffmpeg_available()
    model = get_model()
    lang = os.environ.get("WHISPER_LANGUAGE", "en")
    if lang.lower() == "auto":
        lang = None
    initial_prompt = (
        "Meeting minutes, agenda, action items, decision, agreed, follow up, "
        "deadline, assign, participant, summary, topic, conclusion."
    )
    try:
        import torch
        fp16 = torch.cuda.is_available()
    except Exception:
        fp16 = False

    result = model.transcribe(
        audio_path,
        language=lang,
        task="transcribe",
        fp16=fp16,
        initial_prompt=initial_prompt if lang == "en" else None,
        verbose=False,
        condition_on_previous_text=False,
        compression_ratio_threshold=2.2,
        no_speech_threshold=0.5,
        temperature=[0.0, 0.2, 0.4],
    )
    return result


def transcribe_to_json(audio_path: str) -> dict[str, Any]:
    """
    Transcribe and return structured JSON:
    {
        "text": "full transcript",
        "segments": [{"start": float, "end": float, "text": str}, ...]
    }
    """
    raw = transcribe(audio_path)
    text = (raw.get("text") or "").strip()
    segments = raw.get("segments") or []
    return {
        "text": text,
        "segments": [
            {"start": s.get("start"), "end": s.get("end"), "text": s.get("text", "").strip()}
            for s in segments
        ],
    }
