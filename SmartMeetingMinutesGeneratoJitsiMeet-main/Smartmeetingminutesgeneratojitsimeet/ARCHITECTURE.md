# Architecture Overview

## System Flow

```
┌─────────────────┐
│  Flutter App    │
│  (Phone)        │
└────────┬────────┘
         │
         │ 1. Creates Jitsi meeting room
         │ 2. Sends room name to server
         │
         ▼
┌─────────────────┐
│  Server Bot     │
│  (Node.js)      │
└────────┬────────┘
         │
         │ 3. Joins meeting via Puppeteer
         │ 4. Starts audio recording
         │
         ▼
┌─────────────────┐
│  Jitsi Meet     │
│  (Cloud/Server) │
└─────────────────┘
         │
         │ 5. Meeting audio stream
         │
         ▼
┌─────────────────┐
│  MediaRecorder  │
│  (Browser API)  │
└────────┬────────┘
         │
         │ 6. Recorded audio file
         │
         ▼
┌─────────────────┐
│  Server Storage │
│  (recordings/)  │
└────────┬────────┘
         │
         │ 7. Download URL sent to app
         │
         ▼
┌─────────────────┐
│  Flutter App    │
│  Downloads &    │
│  Saves Audio    │
└─────────────────┘
```

## Components

### Flutter App (`lib/`)

1. **main.dart** - Main UI with meeting creation and recording management
2. **models/meeting.dart** - Data model for meeting information
3. **services/jitsi_service.dart** - Handles Jitsi Meet integration
4. **services/recording_service.dart** - Communicates with server bot and manages audio files

### Server Bot (`server/`)

1. **server.js** - Express server with Puppeteer bot
2. **package.json** - Node.js dependencies
3. **recordings/** - Directory for recorded audio files (created automatically)

## API Endpoints

### POST /api/start-recording
Initiates recording for a Jitsi room.

**Request:**
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
Stops recording and returns download URL.

**Request:**
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
Returns server status and active recording count.

## Data Flow

1. User creates a meeting in the Flutter app
2. App generates/uses a room name
3. App calls `/api/start-recording` with room name
4. Server bot launches Puppeteer browser
5. Bot navigates to Jitsi room URL
6. Bot joins the meeting (auto-join or click join button)
7. Bot sets up MediaRecorder to capture audio
8. Meeting proceeds (audio is being recorded)
9. User stops recording in app
10. App calls `/api/stop-recording`
11. Bot stops MediaRecorder and saves file
12. Server returns download URL
13. App downloads audio file to device storage
14. Audio file is saved in app's recordings directory

## Storage Locations

- **Server recordings**: `server/recordings/*.webm`
- **App recordings**: App documents directory (`recordings/recording_*.webm`)

## Technology Stack

- **Flutter**: Mobile app framework
- **Jitsi Meet Flutter SDK**: Video conferencing integration
- **Node.js + Express**: Server bot framework
- **Puppeteer**: Browser automation for joining meetings
- **MediaRecorder API**: Audio recording in browser
- **HTTP**: Communication between app and server

