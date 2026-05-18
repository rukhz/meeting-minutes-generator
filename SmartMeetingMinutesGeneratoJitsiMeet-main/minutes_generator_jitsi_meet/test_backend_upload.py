"""
Test that the Flask backend accepts uploads and returns minutes JSON.
Run from repo root with backend running:
  python minutes_generator_jitsi_meet/test_backend_upload.py
"""
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def create_minimal_wav(path: str) -> bool:
    """Write a minimal valid WAV file (1 sec silence) for testing."""
    import wave
    import struct
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        for _ in range(16000):
            w.writeframes(struct.pack("<h", 0))
    return os.path.exists(path) and os.path.getsize(path) > 0


def test_health(base_url: str) -> bool:
    import urllib.request
    try:
        req = urllib.request.Request(f"{base_url}/api/health", method="GET")
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status == 200 and b"ok" in r.read()
    except Exception as e:
        print(f"Health check failed: {e}", file=sys.stderr)
        return False


def test_upload_curl(base_url: str, wav_path: str) -> bool:
    url = f"{base_url}/api/generate-minutes"
    try:
        result = subprocess.run(
            [
                "curl.exe",
                "-s",
                "-w", "%{http_code}",
                "-X", "POST",
                "-F", "meeting_id=test-meeting-1",
                "-F", f"audio=@{wav_path}",
                url,
            ],
            capture_output=True,
            text=True,
            timeout=90,
            cwd=SCRIPT_DIR,
        )
        out = (result.stdout or "") + (result.stderr or "")
        if result.returncode != 0:
            print(f"curl failed: {out}", file=sys.stderr)
            return False
        # Last 3 chars are http_code from -w
        body = result.stdout[:-3] if len(result.stdout) >= 3 else result.stdout
        code = result.stdout[-3:] if len(result.stdout) >= 3 else "000"
        if code != "200":
            print(f"Upload returned {code}: {body[:400]}", file=sys.stderr)
            return False
        if "success" not in body or "minutes" not in body:
            print(f"Response missing success/minutes: {body[:400]}", file=sys.stderr)
            return False
        print("Upload test passed. Backend returned success and minutes.")
        return True
    except FileNotFoundError:
        print("curl.exe not found. Use: pip install requests && python -c \"import requests; r=requests.get('{}'); print(r.json())\"".format(f"{base_url}/api/health"), file=sys.stderr)
        return False
    except Exception as e:
        print(f"Upload test failed: {e}", file=sys.stderr)
        return False


def main():
    base_url = os.environ.get("BACKEND_URL", "http://127.0.0.1:5000").rstrip("/")
    print(f"Testing backend at {base_url}")

    if not test_health(base_url):
        print("FAIL: Health check failed. Is the Flask app running on port 5000?", file=sys.stderr)
        return 1
    print("OK: Health check passed.")

    wav_path = os.path.join(SCRIPT_DIR, "test_audio.wav")
    if not create_minimal_wav(wav_path):
        print("FAIL: Could not create test WAV.", file=sys.stderr)
        return 1
    try:
        if not test_upload_curl(base_url, wav_path):
            return 1
    finally:
        if os.path.exists(wav_path):
            os.remove(wav_path)

    print("All backend tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
