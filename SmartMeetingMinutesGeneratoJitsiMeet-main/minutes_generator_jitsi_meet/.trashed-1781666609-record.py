"""
Voice recording - starts when bot joins, stops and saves when meeting ends.
Records for the full meeting duration (no fixed limit).
"""

import threading
import wave
import soundcard as sc
import numpy as np

from speech_to_text import transcribe_fn

SAMPLERATE = 44100
CHUNK_FRAMES = 4096
OUTPUT_FILE = "desktop_audio.wav"

_recording_thread: threading.Thread | None = None
_stop_event = threading.Event()
_recorder_instance = None


def start_recording():
    """Start recording system audio in a background thread. Call when bot joins."""
    global _recording_thread, _stop_event, _recorder_instance

    if _recording_thread and _recording_thread.is_alive():
        print("[Recording] Already recording")
        return

    _stop_event.clear()
    _recording_thread = threading.Thread(target=_record_loop, daemon=True)
    _recording_thread.start()
    print("[Recording] Started")


def stop_recording():
    """Stop recording and save to file. Call when meeting ends."""
    global _recording_thread, _stop_event

    if not _recording_thread or not _recording_thread.is_alive():
        print("[Recording] Not recording")
        return

    _stop_event.set()
    _recording_thread.join(timeout=5)
    _recording_thread = None
    print(f"[Recording] Saved as {OUTPUT_FILE}")
    transcribe_fn(OUTPUT_FILE)


def _record_loop():
    """Background thread: record in chunks until stop_event is set."""
    global _recorder_instance

    try:
        speaker = sc.default_speaker()
        with sc.get_microphone(
            id=str(speaker.name), include_loopback=True
        ).recorder(samplerate=SAMPLERATE) as mic:
            _recorder_instance = mic
            with wave.open(OUTPUT_FILE, "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)  # 16-bit
                wav_file.setframerate(SAMPLERATE)

                while not _stop_event.is_set():
                    try:
                        data = mic.record(numframes=CHUNK_FRAMES)
                        audio = np.array(data)
                        if len(audio.shape) > 1:
                            audio = audio.mean(axis=1)
                        audio_int16 = (np.clip(audio, -1, 1) * 32767).astype(np.int16)
                        wav_file.writeframes(audio_int16.tobytes())
                    except Exception as e:
                        if not _stop_event.is_set():
                            print(f"[Recording] Error: {e}")
                        break
    except Exception as e:
        print(f"[Recording] Failed to start: {e}")
    finally:
        _recorder_instance = None
