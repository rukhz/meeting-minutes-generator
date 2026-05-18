# Testing Guide

## Debug Logging Added

All key paths now log to console. Prefixes:
- `[MeetingFlow]` – main.dart meeting create/stop/auto-stop
- `[RecordingService]` – start/stop recording, upload, download, bot API
- `[AuthProvider]` – Firebase auth (guest mode when Firebase not configured)
- `[APP]` – Flask backend (health, generate-minutes)

## 1. Test Flask Backend

```powershell
cd minutes_generator_jitsi_meet
python app.py
```

In another terminal:
```powershell
python test_all.py
```

Expected: 3/3 tests pass. Watch Flask terminal for `[APP]` logs.

## 2. Test Flutter App

```powershell
cd Smartmeetingminutesgeneratojitsimeet
flutter run -d android
```

Watch the run terminal for:
- `[MeetingFlow] main: init`
- `[MeetingFlow] main: runApp`
- `[AuthProvider] Firebase.apps.isEmpty=...`

## 3. Test Recording Flow

**Device mic:**
1. Turn OFF "Record all participants (Bot)"
2. Set Backend URL: `http://PC_IP:5000`
3. Create & join meeting
4. Speak for 10+ seconds
5. Leave meeting
6. Watch logs: `[RecordingService]` for upload, `[APP]` in Flask for transcription

**Bot (all participants):**
1. Run Bot Server: `cd server && npm start`
2. Turn ON "Record all participants (Bot)"
3. Set Bot Server URL: `http://PC_IP:3000`
4. Create & join meeting
5. When browser prompts, choose tab + Share tab audio
6. Leave meeting – bot stops, file downloaded, uploaded to Flask

## 4. Check Logs on Crash

- Flutter: Run `flutter run` and watch terminal; errors show stack trace
- Android: `adb logcat -s flutter` or filter by package name
