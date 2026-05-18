# Smart Meeting Minutes – Functionality (Client / Student Guide)

This document explains what the system does and how to use it.

---

## 1. What the System Does

- **Creates Jitsi Meet meetings** from the mobile app (room name or auto-generated).
- **Joins a bot** to the meeting (run on your PC). The bot is a silent participant that records the meeting audio.
- **Records** the full meeting audio on the PC while participants speak.
- **When the meeting ends** (you tap **Stop Meeting** or leave the Jitsi meeting), the PC:
  - Stops the bot and recording
  - Transcribes the audio with **Whisper**
  - Summarizes with **BART** and writes **meeting minutes** (summary, transcript, key points).
- **Shows the minutes** in the app (full text with date, summary, transcript).

---

## 2. Architecture (Current Setup)

```
┌─────────────────────────────────────────────────────────────────┐
│              Flutter App (Android / iOS)                         │
│  • Start / Stop Meeting    • Join via Jitsi    • View minutes    │
└────────────────────────────────┬────────────────────────────────┘
                                   │  HTTP (same Wi‑Fi)
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│              Flask Backend (Python) – Port 5000                 │
│  • Jitsi bot (joins meeting, runs on PC)                        │
│  • Recording (system audio while bot is in meeting)              │
│  • Whisper transcription + BART summary → meeting_minutes.txt     │
│  • API: /api/bot/join, /api/bot/leave, /api/meeting-minutes       │
└─────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│              Jitsi Meet (meet.jit.si)                            │
│  • Meeting room (you + bot join same room)                      │
└─────────────────────────────────────────────────────────────────┘
```

- **One backend only:** the **Flask app** (`minutes_generator_jitsi_meet/app.py`) on port **5000**. There is no separate “bot server” on port 3000.
- **PC:** runs Flask; the Jitsi bot and recording run on the same machine.
- **Phone:** runs the Flutter app; it only talks to Flask (e.g. `http://YOUR_PC_IP:5000`).

---

## 3. User Flow (Step by Step)

| Step | Where | Action |
|------|--------|--------|
| 1 | PC | Start Flask: `cd minutes_generator_jitsi_meet` then `python app.py` (must use `host="0.0.0.0"` so phone can reach it). |
| 2 | App | Open **Smart Meeting Minutes** → go to meeting screen (e.g. **New Meeting**). |
| 3 | App | Set **Flask Server URL** (e.g. `http://192.168.1.5:5000`). Use **Auto** to detect PC on the network, or **Test** to check the URL. |
| 4 | App | (Optional) Enter **Room Name** or leave empty to auto-generate. Tap **Start Meeting**. |
| 5 | Backend | App calls `POST /api/bot/join` → bot joins the Jitsi room and recording starts on the PC. |
| 6 | App | Jitsi opens (in-app or in Jitsi app). You join the same room and speak. |
| 7 | App | When done: tap **Stop Meeting** (or leave Jitsi and return to the app; it may auto-stop). |
| 8 | Backend | App calls `POST /api/bot/leave` → bot leaves, recording stops, Whisper + BART run and write `meeting_minutes.txt`. |
| 9 | App | App polls `GET /api/meeting-minutes` until minutes are ready, then shows the **Minutes** screen. |

---

## 4. Main App Screens and Buttons

- **Landing:** Quick actions – **New Meeting**, **Past Meetings**, Settings, Help.
- **Meeting screen:**
  - **Flask Server URL** – PC address (e.g. `http://192.168.1.5:5000`).
  - **Auto** – find Flask on the network (port 5000).
  - **Test** – check if Flask is reachable.
  - **Room Name** – optional; leave empty to generate.
  - **Start Meeting** – bot joins + Jitsi opens.
  - **Stop Meeting** – bot leaves, minutes generated and shown.
- **Minutes screen** – plain text: date, summary, key points, full transcript.

---

## 5. Backend APIs (Flask, Port 5000)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/bot/status` | Check if backend is up and if bot is in a meeting. Used by **Test** and **Auto**. |
| POST | `/api/bot/join` | Start bot and join Jitsi room; start recording. Body: `room`, `display_name`, etc. |
| POST | `/api/bot/leave` | Make bot leave; stop recording and run transcription + minutes. |
| GET | `/api/meeting-minutes` | Return contents of `meeting_minutes.txt` as JSON: `{ "minutes": "..." }`. |

---

## 6. Important Files (No Need to Change for Normal Use)

| Role | Path |
|------|------|
| Flask app (bot + API) | `minutes_generator_jitsi_meet/app.py` |
| Jitsi bot logic | `minutes_generator_jitsi_meet/jitsi_bot.py` |
| Recording (start/stop) | `minutes_generator_jitsi_meet/record.py` |
| Transcription + minutes | `minutes_generator_jitsi_meet/speech_to_text.py` |
| Output files (on PC) | `minutes_generator_jitsi_meet/transcript.txt`, `meeting_minutes.txt`, `desktop_audio.wav` |
| Flutter meeting UI | `Smartmeetingminutesgeneratojitsimeet/lib/screens/meeting_home_page.dart` |
| Flask API client | `Smartmeetingminutesgeneratojitsimeet/lib/services/flask_bot_service.dart` |

---

## 7. Prerequisites

- **PC:** Python 3.10+, same Wi‑Fi as phone, firewall allows port 5000.
- **Phone:** Flutter app installed (debug or release APK).
- **First run on PC:** Install Python dependencies in `minutes_generator_jitsi_meet` (e.g. `flask`, `flask-socketio`, `whisper`, `transformers`, etc.; see project requirements).

---

## 8. Troubleshooting

- **“Not found” / Test fails:** Run Flask with `host="0.0.0.0"`, use the PC’s LAN IP (e.g. `http://192.168.1.5:5000`), same Wi‑Fi.
- **“Bot not in a meeting” when stopping:** Bot already left (e.g. auto-stop). App still fetches minutes; wait for “Generating minutes…” to finish.
- **Minutes not updating:** Transcription takes 1–2 minutes. App polls for up to 2 minutes; ensure `meeting_minutes.txt` is written by `speech_to_text.py` in the same folder as `app.py`.
