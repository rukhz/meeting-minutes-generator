"""
Bot Server HTTP API: Start/stop recording, integrate with Flask ASR.
"""
import json
import logging
import os
import re
import socket
import threading
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS

from jitsi_bot import run_bot_sync

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

_active_recordings = {}  # room_name -> {"thread", "stop_event", "status", "filepath"}


def get_recordings_dir():
    """Get the recordings directory path."""
    return os.environ.get("RECORDINGS_DIR", "recordings")


def get_local_ip():
    """Get the local IP address of this machine for network access."""
    try:
        # Create a socket to determine the local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "localhost"


def get_base_url():
    """Get the base URL for this server that phones can access."""
    port = int(os.environ.get("BOT_PORT", "3000"))
    # Try to get the local IP address for network access
    host = os.environ.get("BOT_HOST", get_local_ip())
    return f"http://{host}:{port}"


def get_backend_url():
    """Get the Flask backend URL for uploading recordings."""
    return os.environ.get("ASR_API_URL", "http://localhost:5000/api/generate-minutes")


def upload_to_backend(
    filepath: str,
    meeting_id: str,
    room_name: str,
    participants: list[dict] | None = None,
    auth_token: str | None = None,
) -> dict:
    """
    Upload recording to Flask backend for transcription and minutes generation.
    Returns the backend response with minutes on success.
    """
    import requests
    
    backend_url = get_backend_url()
    
    try:
        with open(filepath, 'rb') as f:
            files = {'audio': f}
            safe_participants = []
            if isinstance(participants, list):
                for p in participants:
                    if not isinstance(p, dict):
                        continue
                    safe_participants.append({
                        'id': str(p.get('id', '')).strip(),
                        'name': str(p.get('name', '')).strip() or 'Participant',
                    })
            data = {
                'meeting_id': meeting_id,
                'metadata': json.dumps({'participants': safe_participants}),
            }
            headers = {}
            if auth_token:
                headers['Authorization'] = f'Bearer {auth_token}'
            response = requests.post(backend_url, files=files, data=data, headers=headers, timeout=120)
            
        if response.status_code == 200:
            result = response.json()
            logger.info(f"Successfully uploaded recording to backend for meeting {meeting_id}")
            return {
                'success': True,
                'minutes': result.get('minutes'),
                'message': result.get('message', 'Minutes generated')
            }
        else:
            logger.error(f"Backend upload failed: {response.status_code} - {response.text}")
            return {
                'success': False,
                'error': f"Backend returned {response.status_code}",
                'message': response.text
            }
    except Exception as e:
        logger.error(f"Error uploading to backend: {e}")
        return {
            'success': False,
            'error': str(e),
            'message': 'Failed to upload to backend'
        }


@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({
        "ok": True, 
        "service": "bot-server", 
        "active": len(_active_recordings),
        "base_url": get_base_url()
    })


@app.route("/api/start-recording", methods=["POST"])
def start_recording():
    """
    Start bot recording. JSON: { room_name, meeting_id }.
    Bot joins Jitsi, captures audio, saves file. Optionally call ASR when done.
    """
    data = request.get_json(silent=True) or {}
    # Accept both room_name and roomName for compatibility
    room_name = (data.get("room_name") or data.get("roomName") or "").strip()
    # Accept both meeting_id and meetingId
    meeting_id = (data.get("meeting_id") or data.get("meetingId") or room_name or "").strip()

    if not room_name:
        return jsonify({"error": "room_name is required"}), 400

    if room_name in _active_recordings:
        return jsonify({"error": "Recording already in progress for this room"}), 400

    stop_event = threading.Event()
    participants = data.get("participants") if isinstance(data.get("participants"), list) else []
    auth_token = data.get("authToken") or data.get("auth_token") or None

    state = {
        "status": "bot_joining",
        "filepath": None,
        "stop_event": stop_event,
        "meeting_id": meeting_id,
        "participants": participants,
        "auth_token": auth_token,
    }
    _active_recordings[room_name] = state

    def run():
        def on_status(s):
            state["status"] = s

        fp = run_bot_sync(room_name, meeting_id, on_status=on_status, stop_event=stop_event)
        state["filepath"] = fp
        state["status"] = "completed"
        stop_event.set()

    t = threading.Thread(target=run, daemon=True)
    t.start()
    state["thread"] = t

    return jsonify({"success": True, "room_name": room_name, "meeting_id": meeting_id})


@app.route("/api/stop-recording", methods=["POST"])
def stop_recording():
    """Signal bot to stop (if supported). Returns recording URL for download."""
    data = request.get_json(silent=True) or {}
    # Accept both room_name and roomName for compatibility
    room_name = (data.get("room_name") or data.get("roomName") or "").strip()
    # Get auto_upload flag (default True)
    auto_upload = data.get("auto_upload", True)
    
    if not room_name:
        return jsonify({"error": "room_name is required"}), 400

    rec = _active_recordings.get(room_name)
    if not rec:
        return jsonify({"error": "No active recording for this room"}), 404

    rec.get("stop_event", threading.Event()).set()
    # Wait briefly for completion
    t = rec.get("thread")
    if t and t.is_alive():
        t.join(timeout=30)

    # If worker is still finalizing, keep it active and ask client to retry.
    if t and t.is_alive():
        return jsonify({
            "error": "Bot is still finalizing recording. Try again in a few seconds.",
            "status": rec.get("status", "recording"),
        }), 409

    filepath = rec.get("filepath")
    meeting_id = rec.get("meeting_id", room_name)
    participants = rec.get("participants", [])
    auth_token = rec.get("auth_token")

    response_data = {
        "success": True, 
        "recordingUrl": None,
        "recording_path": None,
        "uploaded_to_backend": False,
        "minutes": None
    }

    if filepath and os.path.exists(filepath):
        # Return a FULL URL that the app can use to download the recording
        filename = os.path.basename(filepath)
        base_url = get_base_url()
        recording_url = f"{base_url}/api/download/{filename}"
        
        response_data["recordingUrl"] = recording_url
        response_data["recording_path"] = filepath
        
        # Auto-upload to backend if enabled
        if auto_upload:
            logger.info(f"Auto-uploading recording to backend for meeting {meeting_id}")
            upload_result = upload_to_backend(
                filepath,
                meeting_id,
                room_name,
                participants=participants,
                auth_token=auth_token,
            )
            response_data["uploaded_to_backend"] = upload_result.get("success", False)
            response_data["minutes"] = upload_result.get("minutes")
            response_data["backend_message"] = upload_result.get("message")
            
            if upload_result.get("success"):
                logger.info(f"Successfully generated minutes for meeting {meeting_id}")
            else:
                logger.warning(f"Failed to generate minutes: {upload_result.get('error')}")

        _active_recordings.pop(room_name, None)
        
        return jsonify(response_data)

    # Fallback: discover latest completed recording by naming convention.
    recordings_dir = get_recordings_dir()
    safe_id = re.sub(r"[^\w\-]", "_", meeting_id)
    expected_prefix = f"recording_{safe_id}_"
    latest_file = None
    latest_mtime = 0.0
    try:
        for name in os.listdir(recordings_dir):
            if not name.startswith(expected_prefix):
                continue
            full = os.path.join(recordings_dir, name)
            if not os.path.isfile(full):
                continue
            size = os.path.getsize(full)
            if size <= 1024:
                continue
            mtime = os.path.getmtime(full)
            if mtime > latest_mtime:
                latest_mtime = mtime
                latest_file = full
    except Exception as e:
        logger.warning("Failed to scan fallback recordings for room=%s: %s", room_name, e)

    if latest_file and os.path.exists(latest_file):
        filename = os.path.basename(latest_file)
        base_url = get_base_url()
        response_data["recordingUrl"] = f"{base_url}/api/download/{filename}"
        response_data["recording_path"] = latest_file
        _active_recordings.pop(room_name, None)
        return jsonify(response_data)
    
    # Finalized but no usable file: clear active state and report explicit failure.
    _active_recordings.pop(room_name, None)
    response_data["success"] = False
    response_data["message"] = "Recording stopped but no audio file was produced"
    return jsonify(response_data)


@app.route("/api/upload-recording", methods=["POST"])
def upload_recording():
    """
    Manually upload an existing recording to the backend.
    JSON: { recording_path, meeting_id }
    """
    data = request.get_json(silent=True) or {}
    filepath = (data.get("recording_path") or "").strip()
    meeting_id = (data.get("meeting_id") or data.get("meetingId") or "unknown").strip()
    room_name = (data.get("room_name") or "").strip()
    
    if not filepath:
        return jsonify({"error": "recording_path is required"}), 400
    
    if not os.path.exists(filepath):
        return jsonify({"error": "Recording file not found"}), 404
    
    result = upload_to_backend(filepath, meeting_id, room_name)
    
    if result.get("success"):
        return jsonify({
            "success": True,
            "minutes": result.get("minutes"),
            "message": result.get("message")
        })
    else:
        return jsonify({
            "success": False,
            "error": result.get("error"),
            "message": result.get("message")
        }), 500


@app.route("/api/download/<filename>", methods=["GET"])
def download_recording(filename):
    """Download a recording file."""
    # Security: only allow safe filenames
    safe_filename = re.sub(r'[^\w\-.]', '', filename)
    recordings_dir = get_recordings_dir()
    filepath = os.path.join(recordings_dir, safe_filename)
    
    if not os.path.exists(filepath):
        return jsonify({"error": "File not found"}), 404
    
    return send_file(filepath, as_attachment=True, download_name=safe_filename)


if __name__ == "__main__":
    port = int(os.environ.get("BOT_PORT", "3000"))
    # Print the base URL so user knows what to enter in the app
    print(f"Bot Server starting on port {port}")
    print(f"Base URL for app: {get_base_url()}")
    print(f"Backend URL for auto-upload: {get_backend_url()}")
    app.run(host="0.0.0.0", port=port, debug=True)
