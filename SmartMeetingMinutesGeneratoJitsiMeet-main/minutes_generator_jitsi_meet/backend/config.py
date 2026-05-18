"""
Backend configuration. Use environment variables for secrets.
DO NOT hardcode credentials.
"""
import os

# Flask
SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-key-change-in-production")
DEBUG = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
HOST = os.environ.get("FLASK_HOST", "0.0.0.0")
PORT = int(os.environ.get("FLASK_PORT", "5000"))

# Upload
UPLOAD_FOLDER = os.environ.get("UPLOAD_FOLDER", "recordings")
MAX_CONTENT_LENGTH = 500 * 1024 * 1024  # 500MB

# Firebase - required for production; set via env
FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "")
FIREBASE_CREDENTIALS_PATH = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "")

# ASR (Whisper)
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "base")
WHISPER_LANGUAGE = os.environ.get("WHISPER_LANGUAGE", "en")

# Optional diarization (pyannote)
PYANNOTE_AUTH_TOKEN = os.environ.get("PYANNOTE_AUTH_TOKEN", "")

# LLM for minutes generation (OpenAI API)
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")

# Supported audio extensions
ALLOWED_AUDIO_EXTENSIONS = {".webm", ".wav", ".mp3", ".m4a", ".ogg", ".mp4"}
