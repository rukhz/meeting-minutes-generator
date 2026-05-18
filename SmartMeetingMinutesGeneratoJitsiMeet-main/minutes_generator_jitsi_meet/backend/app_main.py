"""
Smart Meeting Minutes Generator - Flask Backend (Main Application)
Modular: ASR -> NLP -> Minutes Generator, with Firebase Auth and Firestore.
Accepts optional participant list from Jitsi for real-name mapping in minutes.
"""
import json
import logging
import os
import re
import subprocess
import tempfile
from datetime import datetime

from flask import Flask, request, jsonify, send_file
from flask_cors import CORS

from backend.config import UPLOAD_FOLDER, MAX_CONTENT_LENGTH, ALLOWED_AUDIO_EXTENSIONS
from backend.auth.firebase_auth import require_auth, optional_auth
from backend.asr_engine.whisper_asr import transcribe_to_json
from backend.nlp_processor.processor import process_transcript
from backend.minutes_generator.generator import generate_minutes
from backend.firestore_service.firestore_db import (
    save_meeting,
    update_meeting_status,
    save_full_minutes,
    get_meeting,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)
app.config["SECRET_KEY"] = os.environ.get("SECRET_KEY", "dev-secret-change-in-production")
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER
app.config["MAX_CONTENT_LENGTH"] = MAX_CONTENT_LENGTH

os.makedirs(UPLOAD_FOLDER, exist_ok=True)


def allowed_file(filename: str) -> bool:
    ext = os.path.splitext(filename.lower())[1]
    return ext in ALLOWED_AUDIO_EXTENSIONS


def validate_and_prepare_audio(filepath: str) -> str | None:
    """
    Validate audio file and return a path Whisper can process.
    For corrupt/incomplete webm, converts to wav first (captures ffmpeg stderr to avoid spam).
    Returns filepath if valid, or path to converted wav. Returns None if file is corrupt.
    """
    if not os.path.isfile(filepath) or os.path.getsize(filepath) < 100:
        return None
    ext = os.path.splitext(filepath)[1].lower()
    try:
        # Quick probe - fails on corrupt webm (EBML header, etc.) without spamming stderr
        result = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", filepath, "-t", "0.001", "-f", "null", "-"],
            capture_output=True,
            timeout=30,
        )
        if result.returncode != 0:
            logger.warning("Audio file invalid or corrupt (ffmpeg probe failed): %s", filepath)
            return None
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as e:
        logger.warning("ffmpeg probe failed: %s", e)
        return None

    # For webm, convert to wav for more reliable Whisper processing
    if ext in (".webm", ".ogg"):
        try:
            fd, wav_path = tempfile.mkstemp(suffix=".wav")
            os.close(fd)
            result = subprocess.run(
                ["ffmpeg", "-y", "-v", "error", "-i", filepath, "-acodec", "pcm_s16le", "-ar", "16000", wav_path],
                capture_output=True,
                timeout=120,
            )
            if result.returncode != 0:
                try:
                    os.remove(wav_path)
                except OSError:
                    pass
                logger.warning("Could not convert webm to wav for transcription")
                return filepath
            return wav_path
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as e:
            logger.warning("ffmpeg convert failed: %s", e)
            return filepath

    return filepath


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({"ok": True, "service": "minutes-generator"})


# ---------------------------------------------------------------------------
# Generate minutes (with optional Firebase auth)
# ---------------------------------------------------------------------------

@app.route("/api/generate-minutes", methods=["POST"])
@optional_auth
def api_generate_minutes(uid=None, claims=None):
    """
    Accept uploaded audio, transcribe, run NLP, generate minutes.
    Optional: If Authorization Bearer token present, saves to Firestore for uid.
    """
    try:
        if "audio" not in request.files:
            return jsonify({"error": "No audio file provided"}), 400

        audio_file = request.files["audio"]
        meeting_id = request.form.get("meeting_id", "unknown")
        participants_from_client = []
        metadata_str = request.form.get("metadata")
        if metadata_str:
            try:
                meta = json.loads(metadata_str)
                participants_from_client = meta.get("participants") or []
                if not isinstance(participants_from_client, list):
                    participants_from_client = []
                else:
                    participants_from_client = [
                        {"id": str(p.get("id", "")), "name": str(p.get("name", "")).strip() or "Participant"}
                        for p in participants_from_client
                        if isinstance(p, dict)
                    ]
            except (json.JSONDecodeError, TypeError):
                pass

        if audio_file.filename == "":
            return jsonify({"error": "No file selected"}), 400

        if not allowed_file(audio_file.filename):
            return jsonify({
                "error": "Unsupported audio format",
                "supported_extensions": sorted(ALLOWED_AUDIO_EXTENSIONS),
            }), 415

        safe_id = re.sub(r"[^\w\-_]", "_", meeting_id)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        _, ext = os.path.splitext(audio_file.filename.lower())
        ext = ext if ext in ALLOWED_AUDIO_EXTENSIONS else ".m4a"
        filename = f"{safe_id}_{timestamp}{ext}"
        filepath = os.path.join(app.config["UPLOAD_FOLDER"], filename)

        audio_file.save(filepath)
        file_size = os.path.getsize(filepath)
        logger.info("Recording received: %s (%s bytes)", filename, file_size)

        if uid:
            update_meeting_status(uid, meeting_id, "processing")

        minutes = {
            "meeting_date": datetime.utcnow().strftime("%Y-%m-%d"),
            "participants": [],
            "topics": [],
            "decisions": [],
            "action_items": [],
            "summary": "",
            "transcript": [],
        }

        audio_path = validate_and_prepare_audio(filepath)
        if audio_path is None:
            logger.warning("Recording file invalid or corrupt, skipping transcription: %s", filename)
        else:
            try:
                asr_result = transcribe_to_json(audio_path)
                if not (asr_result.get("text") or "").strip() and not (asr_result.get("segments") or []):
                    logger.warning("Whisper returned empty transcript for %s (file size: %s)", filename, file_size)
                clean = process_transcript(asr_result)
                minutes = generate_minutes(
                    clean,
                    audio_path=filepath,
                    participant_list=participants_from_client,
                )

                if uid:
                    save_full_minutes(uid, meeting_id, minutes)
                    update_meeting_status(uid, meeting_id, "completed")
            except (RuntimeError, MemoryError) as e:
                logger.warning("Transcription skipped (memory/model): %s", e)
            except OSError as e:
                logger.exception("OS/ffmpeg error during transcription: %s", e)
                if uid:
                    update_meeting_status(uid, meeting_id, "failed", extra={"error": str(e)})
            except Exception as e:
                logger.exception("Processing failed: %s", e)
                if uid:
                    update_meeting_status(uid, meeting_id, "failed" if not minutes.get("transcript") else "completed", extra={"error": str(e)})
            finally:
                if audio_path and audio_path != filepath:
                    try:
                        os.remove(audio_path)
                    except OSError:
                        pass

        transcription_done = bool(minutes.get("transcript") or minutes.get("summary"))

        return jsonify({
            "success": True,
            "meeting_id": meeting_id,
            "filename": filename,
            "file_size": file_size,
            "transcription_done": transcription_done,
            "minutes": minutes,
            "message": "Recording saved." + (" Minutes generated." if transcription_done else " Transcription skipped."),
        })
    except Exception as e:
        logger.exception("Generate minutes failed")
        return jsonify({"error": "internal_error", "message": str(e)}), 500


# ---------------------------------------------------------------------------
# Meeting lifecycle (Firebase auth required)
# ---------------------------------------------------------------------------

@app.route("/api/meetings", methods=["POST"])
@require_auth
def api_create_meeting(uid, claims):
    """
    Create meeting record. Expects JSON: { room_name, title? }.
    Returns meeting_id for Flutter to track.
    """
    data = request.get_json(silent=True) or {}
    room_name = (data.get("room_name") or "").strip()
    title = (data.get("title") or room_name or "Meeting").strip()

    if not room_name:
        return jsonify({"error": "room_name is required"}), 400

    meeting_id = re.sub(r"[^\w\-]", "_", room_name) + "_" + datetime.utcnow().strftime("%Y%m%d_%H%M")

    save_meeting(uid, meeting_id, {
        "room_name": room_name,
        "title": title,
        "status": "created",
        "created_at": datetime.utcnow().isoformat() + "Z",
        "user_id": uid,
    })

    return jsonify({
        "success": True,
        "meeting_id": meeting_id,
        "room_name": room_name,
    })


@app.route("/api/meetings/<meeting_id>/status", methods=["PATCH"])
@optional_auth
def api_update_meeting_status(uid=None, claims=None, meeting_id=None):
    """Update meeting status: bot_joining | recording | processing | completed. Auth optional (bot may call without token)."""
    data = request.get_json(silent=True) or {}
    status = (data.get("status") or "").strip()
    if status not in ("bot_joining", "recording", "processing", "completed", "failed"):
        return jsonify({"error": "Invalid status"}), 400
    if uid:
        if update_meeting_status(uid, meeting_id, status, extra=data.get("extra")):
            return jsonify({"success": True, "status": status})
        return jsonify({"error": "Update failed"}), 500
    return jsonify({"success": True, "status": status})


@app.route("/api/meetings/<meeting_id>", methods=["GET"])
@require_auth
def api_get_meeting(uid, claims, meeting_id):
    """Get meeting details including minutes if completed."""
    m = get_meeting(uid, meeting_id)
    if m is None:
        return jsonify({"error": "Meeting not found"}), 404
    return jsonify(m)


# ---------------------------------------------------------------------------
# File operations (recordings)
# ---------------------------------------------------------------------------

@app.route("/api/save-recording", methods=["POST"])
def save_recording():
    """Save recorded audio (legacy / upload-only)."""
    try:
        if "audio" not in request.files:
            return jsonify({"error": "No audio file provided"}), 400
        audio_file = request.files["audio"]
        meeting_id = request.form.get("meeting_id", "unknown")
        if audio_file.filename == "":
            return jsonify({"error": "No file selected"}), 400
        safe_id = re.sub(r"[^\w\-_]", "_", meeting_id)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        _, ext = os.path.splitext(audio_file.filename.lower())
        ext = ext if ext in ALLOWED_AUDIO_EXTENSIONS else ".m4a"
        filename = f"{safe_id}_{timestamp}{ext}"
        filepath = os.path.join(app.config["UPLOAD_FOLDER"], filename)
        audio_file.save(filepath)
        return jsonify({"success": True, "filename": filename})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


def main():
    from backend.config import HOST, PORT, DEBUG
    if DEBUG:
        app.run(debug=True, host=HOST, port=PORT, use_reloader=False)
    else:
        import waitress
        logger.info("Starting Waitress WSGI server on %s:%s", HOST, PORT)
        waitress.serve(app, host=HOST, port=PORT, threads=2, channel_timeout=600)


if __name__ == "__main__":
    main()
