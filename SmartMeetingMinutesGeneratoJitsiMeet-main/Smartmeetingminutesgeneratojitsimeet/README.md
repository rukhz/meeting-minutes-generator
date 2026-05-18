# Smart Meeting Minutes Generator with Jitsi Meet

A Flutter application that creates Jitsi Meet rooms and records meeting audio using a server-side bot.

## Architecture

```
Phone (Flutter App)
   |
   |  creates meeting link
   |
Server Bot (Node.js)
   |
   | joins Jitsi via browser (Puppeteer)
   |
captures audio (allowed)
```

## Features

- Create Jitsi Meet rooms from the Flutter app
- Join meetings directly from the app
- Server bot automatically joins meetings and records audio
- Download and save recordings to the device
- View and manage recorded meetings

## Setup

### Flutter App

1. Install Flutter dependencies:
```bash
flutter pub get
```

2. For Android, ensure you have the required permissions (already configured in AndroidManifest.xml)

3. Run the app:
```bash
flutter run
```

### Server Bot

1. Navigate to the server directory:
```bash
cd server
```

2. Install Node.js dependencies:
```bash
npm install
```

3. Make sure you have Chrome/Chromium installed (required for Puppeteer)

4. Start the server:
```bash
npm start
```

The server will run on `http://localhost:3000` by default.

## Usage

1. **Start the server bot first** (on your development machine or server)

2. **Launch the Flutter app** on your device/emulator

3. **Configure the server URL** in the app (default: `http://localhost:3000`)
   - For Android emulator, use `http://10.0.2.2:3000` instead of `localhost`
   - For physical device, use your computer's IP address: `http://YOUR_IP:3000`

4. **Enter your name** (optional)

5. **Enter a room name** or leave empty to auto-generate one

6. **Tap "Create & Join Meeting"** - This will:
   - Create a Jitsi Meet room
   - Start recording on the server bot
   - Join the meeting from the app

7. **Conduct your meeting**

8. **Tap "Stop Recording"** when done - This will:
   - Stop the server bot recording
   - Download the audio file to your device
   - Save it in the app's recordings directory

## API Endpoints (Server)

- `POST /api/start-recording` - Start recording a Jitsi room
- `POST /api/stop-recording` - Stop recording and get download URL
- `GET /api/health` - Check server status

## Project Structure

```
lib/
  models/
    meeting.dart          # Meeting data model
  services/
    jitsi_service.dart    # Jitsi Meet integration
    recording_service.dart # Recording API and file management
  main.dart               # Main app UI

server/
  server.js              # Node.js bot server
  package.json           # Server dependencies
  recordings/            # Recorded audio files (created automatically)
```

## Notes

- The server bot uses Puppeteer to control a headless Chrome browser
- Audio is recorded using the MediaRecorder API in the browser
- Recordings are saved as WebM files by default
- Make sure the server is accessible from your Flutter app (network configuration)

## Troubleshooting

- **Can't connect to server**: Check the server URL and ensure the server is running
- **Recording not starting**: Make sure Chrome/Chromium is installed for Puppeteer
- **Permission errors**: Grant storage and microphone permissions in app settings
