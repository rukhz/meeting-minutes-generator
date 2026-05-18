# Jitsi Recording Bot Server

This server bot joins Jitsi Meet rooms via Puppeteer and records audio from the meetings.

## Setup

1. Install dependencies:
```bash
npm install
```

2. Start the server:
```bash
npm start
```

The server will run on `http://localhost:3000` by default.

## API Endpoints

### POST /api/start-recording
Starts recording audio from a Jitsi Meet room.

**Request Body:**
```json
{
  "roomName": "my-meeting-room"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Recording started",
  "roomName": "my-meeting-room"
}
```

### POST /api/stop-recording
Stops recording and returns the recording URL.

**Request Body:**
```json
{
  "roomName": "my-meeting-room"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Recording stopped",
  "recordingUrl": "http://localhost:3000/recordings/recording_my-meeting-room_1234567890.webm"
}
```

### GET /api/health
Check server health and active recordings count.

## Notes

- The bot uses Puppeteer to control a headless Chrome browser
- Audio is recorded using the MediaRecorder API
- Recordings are saved in the `recordings/` directory as WebM, then converted to MP3 for playback (better Android support)
- Make sure to have **Chrome/Chromium** installed for Puppeteer to work
- **ffmpeg** must be installed and in PATH for MP3 conversion (recordings will fall back to WebM if ffmpeg is missing)

## "Cannot reach bot server" on phone

1. **Start the server on your PC**  
   - Double‑click `START_BOT_SERVER.ps1` or in PowerShell run:  
     `.\START_BOT_SERVER.ps1`  
   - It will print the URL to use (e.g. `http://192.168.1.5:3000`). Enter that in the app.

2. **Same Wi‑Fi**  
   - Phone and PC must be on the same Wi‑Fi network (not mobile data).

3. **Allow port 3000 in Windows Firewall** (if the phone still cannot connect):  
   - Open PowerShell **as Administrator**, then run:  
     `New-NetFirewallRule -DisplayName "Jitsi Bot Server Port 3000" -Direction Inbound -LocalPort 3000 -Protocol TCP -Action Allow`

4. **Check on PC**  
   - In a browser on the PC open: `http://localhost:3000/api/health`  
   - You should see `{"status":"ok",...}`. If not, the server is not running.
