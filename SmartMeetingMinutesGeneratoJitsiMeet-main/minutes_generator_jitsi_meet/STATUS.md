# Functionality status

## What was verified

| Step | Status | How to verify |
|------|--------|----------------|
| **Backend receives upload** | ✅ Working | Run `python minutes_generator_jitsi_meet/verify_flow.py` (with backend running). Health + upload accepted. |
| **Sending to backend (from app)** | ✅ Working | Flutter sends multipart POST to `/api/generate-minutes`. Same as verify_flow.py. Works when backend URL is reachable (localhost + adb reverse, or PC IP on same Wi‑Fi). |
| **Recording (Flutter)** | ✅ Implemented | App uses device microphone (`record` package), saves `.m4a` in app documents. Requires mic permission. Start recording before/during Jitsi meeting. |
| **Transcription (backend)** | ⚠️ Depends on setup | Backend uses **Whisper** + **ffmpeg**. If both installed: `transcription_done = True` and minutes contain transcript/summary. If not: upload still succeeds, minutes are empty. |

## Quick verification

1. Start backend: `cd minutes_generator_jitsi_meet && python app.py`
2. In another terminal: `python minutes_generator_jitsi_meet/verify_flow.py`
3. You should see: health OK, upload OK, and either "Transcription: OK" or "Transcription: skipped (install Whisper + ffmpeg)".

## If transcription is skipped

- **Whisper**: `pip install openai-whisper` (already in requirements.txt).
- **ffmpeg**: Required by Whisper to read audio. Install and add to PATH:
  - Windows: `winget install ffmpeg` or download from https://ffmpeg.org
  - Or: `choco install ffmpeg`

After installing ffmpeg, restart the backend and run `verify_flow.py` again (or upload a recording with speech from the app).
