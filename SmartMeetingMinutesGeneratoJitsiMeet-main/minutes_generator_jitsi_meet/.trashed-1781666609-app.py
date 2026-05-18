"""
Smart Meeting Minutes Generator - Jitsi Bot Control
Flask app with Jitsi bot integration for joining meetings.
"""

import threading
from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit

from jitsi_bot import JitsiBot, BotConfig
from record import start_recording, stop_recording

app = Flask(__name__)
app.config["SECRET_KEY"] = "smart-meeting-minutes-secret"
socketio = SocketIO(app, cors_allowed_origins="*")

# Global bot instance (one bot per server)
bot: JitsiBot | None = None
bot_lock = threading.Lock()


def notify_bot_status(status: str, message: str = ""):
    """Emit bot status to all connected clients via Socket.IO."""
    socketio.emit("bot_status", {"status": status, "message": message})


@app.route("/")
def index():
    """Serve the bot control UI."""
    return render_template("index.html")


@app.route("/api/bot/join", methods=["POST"])
def bot_join():
    """Start the bot and join a Jitsi meeting."""
    global bot

    data = request.get_json() or {}
    room = data.get("room", "MeetingRoom").strip() or "MeetingRoom"
    display_name = data.get("display_name", "MeetingBot").strip() or "MeetingBot"
    audio_muted = data.get("audio_muted", False)
    video_muted = data.get("video_muted", True)
    headless = data.get("headless", False)

    with bot_lock:
        if bot and bot.is_in_meeting():
            return jsonify({"success": False, "error": "Bot is already in a meeting"}), 400

        config = BotConfig(
            room_name=room,
            display_name=display_name,
            start_with_audio_muted=audio_muted,
            start_with_video_muted=video_muted,
            headless=headless,
        )
        bot = JitsiBot(config)

        def on_joined_callback():
            print("[Bot] Successfully joined the meeting")
            start_recording()
            notify_bot_status("joined", "Bot joined the meeting")

        def on_left_callback():
            print("[Bot] Meeting ended")
            stop_recording()
            notify_bot_status("left", "Bot left the meeting")

        bot.on_joined(on_joined_callback)
        bot.on_left(on_left_callback)

    # Run join in background to avoid blocking
    def do_join():
        success = bot.join()
        if not success:
            notify_bot_status("error", "Failed to join meeting")

    thread = threading.Thread(target=do_join, daemon=True)
    thread.start()

    return jsonify({"success": True, "message": "Bot is joining the meeting"})


@app.route("/api/bot/leave", methods=["POST"])
def bot_leave():
    """Make the bot leave the current meeting."""
    global bot

    with bot_lock:
        if not bot or not bot.is_in_meeting():
            return jsonify({"success": False, "error": "Bot is not in a meeting"}), 400

        bot.leave()
        bot = None

    return jsonify({"success": True, "message": "Bot left the meeting"})


@app.route("/api/bot/status")
def bot_status():
    """Get current bot status."""
    with bot_lock:
        in_meeting = bot is not None and bot.is_in_meeting()
    return jsonify({"in_meeting": in_meeting})


@app.route("/api/meeting-minutes")
def meeting_minutes():
    """Return generated meeting minutes (from meeting_minutes.txt)."""
    try:
        with open("meeting_minutes.txt", "r", encoding="utf-8") as f:
            text = f.read()
        return jsonify({"minutes": text})
    except FileNotFoundError:
        return jsonify({"minutes": "", "error": "No minutes yet"}), 404


@socketio.on("connect")
def handle_connect():
    """Send current status when client connects."""
    with bot_lock:
        in_meeting = bot is not None and bot.is_in_meeting()
    emit("bot_status", {"status": "joined" if in_meeting else "idle", "in_meeting": in_meeting})


if __name__ == "__main__":
    socketio.run(app, debug=True, host="0.0.0.0", port=5000)
