"""
Verify end-to-end flow: upload -> backend receives -> transcription (if Whisper/ffmpeg available).
Run with backend running: python minutes_generator_jitsi_meet/verify_flow.py

Checks:
  1. Backend health
  2. Upload to /api/generate-minutes
  3. Response has success=True, file saved
  4. transcription_done and minutes content (if Whisper works)
"""

import os
import struct
import sys
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_URL = os.environ.get("BACKEND_URL", "http://127.0.0.1:5000").rstrip("/")


def create_minimal_wav(path: str, duration_sec: float = 1.0) -> bool:
    """Create a valid WAV file (silence). Whisper may return empty text but backend should still respond."""
    import wave
    rate = 16000
    n = int(rate * duration_sec)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        for _ in range(n):
            w.writeframes(struct.pack("<h", 0))
    return os.path.exists(path) and os.path.getsize(path) > 0


def main():
    print("=== Flow verification ===\n")
    print(f"Backend URL: {BASE_URL}\n")

    # 1. Health
    print("1. Backend health...")
    try:
        req = urllib.request.Request(f"{BASE_URL}/api/health", method="GET")
        with urllib.request.urlopen(req, timeout=10) as r:
            data = r.read().decode()
            if r.status != 200 or "ok" not in data:
                print(f"   FAIL: status={r.status} body={data[:200]}")
                return 1
    except Exception as e:
        print(f"   FAIL: {e}")
        print("   Make sure the backend is running: cd minutes_generator_jitsi_meet && python app.py")
        return 1
    print("   OK\n")

    # 2. Upload (multipart)
    print("2. Upload to /api/generate-minutes...")
    wav_path = os.path.join(SCRIPT_DIR, "verify_test.wav")
    if not create_minimal_wav(wav_path):
        print("   FAIL: could not create test WAV")
        return 1
    try:
        boundary = "----VerifyBoundary"
        with open(wav_path, "rb") as f:
            audio_bytes = f.read()
        body = (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="meeting_id"\r\n\r\n'
            "verify-meeting\r\n"
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="audio"; filename="test.wav"\r\n'
            "Content-Type: audio/wav\r\n\r\n"
        ).encode() + audio_bytes + f"\r\n--{boundary}--\r\n".encode()
        req = urllib.request.Request(
            f"{BASE_URL}/api/generate-minutes",
            data=body,
            method="POST",
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
                "Content-Length": str(len(body)),
            },
        )
        with urllib.request.urlopen(req, timeout=120) as r:
            resp_body = r.read().decode()
            if r.status != 200:
                print(f"   FAIL: status={r.status}\n{resp_body[:500]}")
                return 1
    except Exception as e:
        print(f"   FAIL: {e}")
        return 1
    finally:
        if os.path.exists(wav_path):
            os.remove(wav_path)
    print("   OK (upload accepted)\n")

    # 3. Parse response
    print("3. Response content...")
    try:
        import json
        data = json.loads(resp_body)
    except Exception as e:
        print(f"   FAIL: invalid JSON - {e}")
        return 1
    if not data.get("success"):
        print(f"   FAIL: success=False, response={data}")
        return 1
    print("   success = True")
    print(f"   file_size = {data.get('file_size', '?')}")
    transcription_done = data.get("transcription_done", False)
    minutes = data.get("minutes") or {}
    transcript = minutes.get("transcript") or []
    summary = (minutes.get("summary") or "").strip()
    print(f"   transcription_done = {transcription_done}")
    print(f"   minutes.transcript length = {len(transcript)}")
    print(f"   minutes.summary (len) = {len(summary)}")
    if transcription_done and (transcript or summary):
        print("   Transcription: OK (Whisper/ffmpeg working)")
    elif not transcription_done:
        print("   Transcription: skipped (install Whisper + ffmpeg for speech-to-text)")
    print()
    print("=== Summary ===")
    print("  Recording (Flutter): App records device mic -> m4a file. Works when mic permission granted.")
    print("  Sending to backend:  POST /api/generate-minutes. Works when backend is reachable.")
    print("  Transcription:      Backend uses Whisper + ffmpeg. Works when both installed on PC.")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
