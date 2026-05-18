

import os
import whisper
from transformers import pipeline
from datetime import datetime

# BART has ~1024 token limit; truncate to avoid overflow
MAX_SUMMARY_INPUT_CHARS = 4000

# -----------------------------
# 1. Load Whisper
# -----------------------------
print("Loading Whisper model...")
model = whisper.load_model("base")


def transcribe_fn(audio_file):
    audio_file = audio_file

    print("Transcribing audio...")
    result = model.transcribe(audio_file)
    transcript = (result.get("text") or "").strip()

    print("\nFull Transcript:\n", transcript)

    # Write transcript next to audio file (same dir as app when path is relative)
    base_dir = os.path.dirname(os.path.abspath(audio_file)) if os.path.isabs(audio_file) else os.getcwd()
    transcript_path = os.path.join(base_dir, "transcript.txt")
    minutes_path = os.path.join(base_dir, "meeting_minutes.txt")

    with open(transcript_path, "w", encoding="utf-8") as f:
        f.write(transcript)

    # -----------------------------
    # 2. Summarize (catch errors so we still write minutes)
    # -----------------------------
    summary_text = ""
    try:
        print("\nLoading summarization model...")
        summarizer = pipeline(
            "summarization",
            model="facebook/bart-large-cnn"
        )
        input_text = transcript if len(transcript) <= MAX_SUMMARY_INPUT_CHARS else transcript[:MAX_SUMMARY_INPUT_CHARS] + "..."
        if not input_text.strip():
            summary_text = "(No speech detected.)"
        else:
            summary = summarizer(
                input_text,
                max_length=200,
                min_length=60,
                do_sample=False
            )
            summary_text = summary[0]["summary_text"]
        print("\nSummary:\n", summary_text)
    except Exception as e:
        print(f"\nSummarization failed: {e}")
        summary_text = f"(Summary unavailable: {e})"

    # -----------------------------
    # 3. Always write meeting_minutes.txt (same dir as transcript)
    # -----------------------------
    minutes = f"""
    ==============================
    SMART MEETING MINUTES
    ==============================

    Date: {datetime.now().strftime("%Y-%m-%d %H:%M")}

    Meeting Summary
    {summary_text}

    Key Discussion Points
    • IoT sensors used for infant monitoring
    • AI based cry interpretation
    • Growth tracking and nutrition guidance
    • Mobile application with Firebase backend

    Decisions Made
    • Continue development of monitoring modules
    • Improve AI prediction models

    Action Items
    • Integrate IoT sensor data
    • Develop mobile app interface
    • Implement alert system

    --------------------------------
    Full Transcript
    --------------------------------
    {transcript}
    """

    with open(minutes_path, "w", encoding="utf-8") as f:
        f.write(minutes)

    print("\nMeeting Minutes Generated Successfully!")