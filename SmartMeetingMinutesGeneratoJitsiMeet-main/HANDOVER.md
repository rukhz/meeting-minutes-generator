# Smart Meeting Minutes – Short Handover (Client PC)

## What you have

- **Android app:** `app-release.apk` (in `Smartmeetingminutesgeneratojitsimeet\build\app\outputs\flutter-apk\` after build), or run via `flutter run`
- **Backend:** Python Flask in `minutes_generator_jitsi_meet/` (one service, port 5000)

## One-time setup (PC)

1. Install **Python 3.10+**
2. Install dependencies in `minutes_generator_jitsi_meet` (see project requirements / README)
3. Phone and PC on **same Wi‑Fi**
4. Allow **port 5000** in Windows Firewall if prompted

## Install app on phone (one time)

1. Copy `app-release.apk` to phone (or install via `flutter run`)
2. Install and allow “Install unknown apps” if asked

## Daily use (before each meeting)

1. On PC, open a terminal in the project folder
2. Run:
   ```bash
   cd minutes_generator_jitsi_meet
   python app.py
   ```
   Or use **Start_Flask.bat** if available (see below).
3. Note the PC’s IP (e.g. `192.168.1.5`) shown or find it in Windows network settings.

## In the app

1. Open **Smart Meeting Minutes**
2. Go to the meeting screen (e.g. **New Meeting**)
3. Set **Flask Server URL** to `http://YOUR_PC_IP:5000` (e.g. `http://192.168.1.5:5000`)
4. Use **Auto** to find the PC, or **Test** to check the URL
5. Tap **Start Meeting** → Jitsi opens; join and speak
6. When done, tap **Stop Meeting** (or leave Jitsi and return; app may auto-stop)
7. Wait for “Generating minutes…” then view the minutes on screen

## If something fails

- Phone and PC must be on the **same Wi‑Fi**
- Flask must be running; try in browser: `http://localhost:5000/api/bot/status`
- Use the PC’s **LAN IP** in the app (not localhost)
- See [FUNCTIONALITY.md](FUNCTIONALITY.md) for full flow and troubleshooting.
