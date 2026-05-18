# Smart Meeting Minutes Generator

A Flutter app that creates Jitsi Meet meetings, records them via a **Python bot** running on a PC (Flask backend), and generates meeting minutes using Whisper transcription and BART summarization.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter App (Android/iOS)                    │
│  • Create/stop meetings  • Join Jitsi  • View minutes            │
└───────────────────────────────┬─────────────────────────────────┘
                                │  HTTP (same Wi‑Fi)
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              Flask Backend (Python) – Port 5000                  │
│  • Jitsi bot joins meeting  • Records audio  • Whisper + BART    │
│  • /api/bot/join, /api/bot/leave, /api/meeting-minutes            │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Jitsi Meet (meet.jit.si)                     │
└─────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Path | Port | Role |
|-----------|------|------|------|
| Flutter App | `Smartmeetingminutesgeneratojitsimeet/` | - | Mobile UI, Jitsi SDK, Firebase auth |
| Flask Backend | `minutes_generator_jitsi_meet/` | 5000 | Bot control, recording, Whisper, minutes |

## Quick Start

### Prerequisites

- **Python 3.10+** – for Flask backend
- **Flutter** – for app development
- PC and phone on **same Wi‑Fi**

### Run backend (PC)

```bash
cd minutes_generator_jitsi_meet
python app.py
```

Flask runs at `http://0.0.0.0:5000`. Note your PC’s LAN IP (e.g. `192.168.1.5`).

### Run app (phone / emulator)

```bash
cd Smartmeetingminutesgeneratojitsimeet
flutter run -d <device>
```

In the app: set **Flask Server URL** to `http://YOUR_PC_IP:5000`, or use **Auto** to detect it. Tap **Start Meeting** to create a room and open Jitsi; tap **Stop Meeting** to generate and view minutes.

## Flow

1. **Start Meeting** – App calls `POST /api/bot/join`; bot joins Jitsi and recording starts.
2. **Meeting** – You join the same Jitsi room; audio is recorded on the PC.
3. **Stop Meeting** – App calls `POST /api/bot/leave`; bot leaves, recording stops, Whisper + BART run.
4. **Minutes** – App polls `GET /api/meeting-minutes` and displays the result.

## Key Files

- `minutes_generator_jitsi_meet/app.py` – Flask app (bot join/leave, minutes API)
- `minutes_generator_jitsi_meet/jitsi_bot.py` – Jitsi bot
- `minutes_generator_jitsi_meet/record.py` – Recording start/stop
- `minutes_generator_jitsi_meet/speech_to_text.py` – Whisper + BART → meeting_minutes.txt
- `Smartmeetingminutesgeneratojitsimeet/lib/screens/meeting_home_page.dart` – Meeting UI
- `Smartmeetingminutesgeneratojitsimeet/lib/services/flask_bot_service.dart` – Flask API client

## Documentation

- **[FUNCTIONALITY.md](FUNCTIONALITY.md)** – Full functionality guide for client/students (recommended)
- [REQUIREMENTS.md](REQUIREMENTS.md) – Functional requirements
- [HANDOVER.md](HANDOVER.md) – Short client handover
- [API_DOCUMENTATION.md](API_DOCUMENTATION.md) – API reference (Flask endpoints)

## Troubleshooting

- **Can't connect from phone** – Same Wi‑Fi; run Flask with `host="0.0.0.0"`; firewall allows port 5000.
- **No minutes** – Wait 1–2 min after stop (transcription); check Flask terminal and `meeting_minutes.txt`.
- **“Bot not in a meeting”** – Bot already left; app still fetches minutes when ready.
