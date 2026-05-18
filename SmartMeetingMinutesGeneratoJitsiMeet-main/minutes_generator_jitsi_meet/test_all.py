#!/usr/bin/env python3
"""
Test script for Smart Meeting Minutes API.
Run Flask backend first: python app.py
Then: python test_all.py
"""
import os
import sys
import requests

BASE = os.environ.get("API_BASE", "http://localhost:5000")


def test_health():
    """Test GET /api/health"""
    print("\n=== TEST: GET /api/health ===")
    try:
        r = requests.get(f"{BASE}/api/health", timeout=5)
        print(f"  Status: {r.status_code}")
        print(f"  Response: {r.json()}")
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"
        assert r.json().get("ok") is True
        print("  PASS")
        return True
    except Exception as e:
        print(f"  FAIL: {e}")
        return False


def test_generate_minutes_no_file():
    """Test POST /api/generate-minutes without file"""
    print("\n=== TEST: POST /api/generate-minutes (no file) ===")
    try:
        r = requests.post(
            f"{BASE}/api/generate-minutes",
            data={"meeting_id": "test123"},
            timeout=5,
        )
        print(f"  Status: {r.status_code}")
        assert r.status_code == 400
        print("  PASS (expected 400)")
        return True
    except Exception as e:
        print(f"  FAIL: {e}")
        return False


def test_generate_minutes_with_audio():
    """Test POST /api/generate-minutes with actual audio file"""
    print("\n=== TEST: POST /api/generate-minutes (with audio) ===")
    sample = os.path.join(os.path.dirname(__file__), "demo", "sample.wav")
    if not os.path.exists(sample):
        print(f"  SKIP: No sample.wav at {sample}")
        return True
    try:
        with open(sample, "rb") as f:
            r = requests.post(
                f"{BASE}/api/generate-minutes",
                files={"audio": ("sample.wav", f, "audio/wav")},
                data={"meeting_id": "test_meeting"},
                timeout=120,
            )
        print(f"  Status: {r.status_code}")
        data = r.json()
        print(f"  success: {data.get('success')}")
        print(f"  transcription_done: {data.get('transcription_done')}")
        print(f"  filename: {data.get('filename')}")
        print(f"  file_size: {data.get('file_size')}")
        if data.get("minutes"):
            m = data["minutes"]
            print(f"  minutes.transcript len: {len(m.get('transcript', []))}")
            print(f"  minutes.summary len: {len(m.get('summary', ''))}")
        assert r.status_code == 200, f"Expected 200, got {r.status_code}"
        assert data.get("success") is True
        print("  PASS")
        return True
    except Exception as e:
        print(f"  FAIL: {e}")
        return False


def main():
    print("Smart Meeting Minutes - API Test Suite")
    print(f"Base URL: {BASE}")
    results = []
    results.append(("Health", test_health()))
    results.append(("Generate (no file)", test_generate_minutes_no_file()))
    results.append(("Generate (with audio)", test_generate_minutes_with_audio()))
    print("\n" + "=" * 50)
    passed = sum(1 for _, ok in results if ok)
    total = len(results)
    print(f"Results: {passed}/{total} passed")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
