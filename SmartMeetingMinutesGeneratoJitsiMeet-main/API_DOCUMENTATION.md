# API Documentation – Smart Meeting Minutes (Flask Backend)

Base URL: `http://YOUR_PC_IP:5000` (or `http://localhost:5000` on PC).

---

## Endpoints

### Bot status (health check)

```
GET /api/bot/status
```

Response:
```json
{ "in_meeting": false }
```
Use this for **Test** and **Auto** in the app.

---

### Join meeting (start bot and recording)

```
POST /api/bot/join
Content-Type: application/json
```

Body:
```json
{
  "room": "jitsi-room-name",
  "display_name": "MeetingBot",
  "audio_muted": true,
  "video_muted": true
}
```

Response (success):
```json
{ "success": true, "message": "Bot is joining the meeting" }
```

Response (error, e.g. bot already in meeting):
```json
{ "success": false, "error": "Bot is already in a meeting" }
```
Status: 400.

---

### Leave meeting (stop bot and generate minutes)

```
POST /api/bot/leave
Content-Type: application/json
```

Body: `{}` (empty object).

Response (success):
```json
{ "success": true, "message": "Bot left the meeting" }
```

Response (error, e.g. bot not in meeting):
```json
{ "success": false, "error": "Bot is not in a meeting" }
```
Status: 400. The app still uses this to trigger fetching minutes if the bot already left.

---

### Get meeting minutes

```
GET /api/meeting-minutes
```

Response (success):
```json
{ "minutes": "Full text of meeting_minutes.txt ..." }
```

Response (no minutes yet):
```json
{ "minutes": "", "error": "No minutes yet" }
```
Status: 404.

---

## Flow

1. App calls `POST /api/bot/join` with room name → bot joins Jitsi, recording starts.
2. User joins same room and speaks.
3. App calls `POST /api/bot/leave` → bot leaves, recording stops, Whisper + BART run and write `meeting_minutes.txt`.
4. App polls `GET /api/meeting-minutes` until minutes are ready, then displays them.
