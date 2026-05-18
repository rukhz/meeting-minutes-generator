# Smart Meeting Minutes – Requirements

## Overview

The system records Jitsi Meet meetings via a server-side bot, transcribes audio with Whisper, and generates structured meeting minutes (topics, decisions, action items, summary).

---

## Functional Requirements

### 1. Meeting Creation & Recording

| ID | Requirement | Status |
|----|-------------|--------|
| M1 | User creates a Jitsi meeting from the app | Done |
| M2 | App generates or accepts a room ID | Done |
| M3 | Bot joins the meeting as a participant (no user action) | Done |
| M4 | Bot captures meeting audio (all participants) | Done |
| M5 | Recording starts automatically when bot joins | Done |
| M6 | Recording stops when user taps Stop or when meeting ends | Done |
| M7 | One meeting produces one recording file | Done |

### 2. Audio Capture

| ID | Requirement | Status |
|----|-------------|--------|
| A1 | Primary: capture from Jitsi DOM/audio elements | Done |
| A2 | Fallback: microphone if DOM capture unavailable | Done |
| A3 | Partial flush during recording (crash recovery) | Done |
| A4 | Output: WebM audio, converted to MP4 for compatibility | Done |

### 3. Upload & Minutes

| ID | Requirement | Status |
|----|-------------|--------|
| U1 | Bot uploads recorded audio to backend when stop is called | Done |
| U2 | Backend transcribes audio (Whisper) | Done |
| U3 | Backend generates structured minutes (topics, decisions, action items, summary) | Done |
| U4 | Minutes returned to app (via stop response or status API) | Done |
| U5 | App displays minutes in a readable format | Done |

### 4. User Experience

| ID | Requirement | Status |
|----|-------------|--------|
| UX1 | User can create meeting and join in one action | Done |
| UX2 | User can stop recording from the app | Done |
| UX3 | User can view and download recordings | Done |
| UX4 | User can view minutes after meeting ends | Done |
| UX5 | App works with PC and phone on same Wi‑Fi | Done |
| UX6 | Optional Firebase auth for cloud sync | Done |

### 5. Robustness

| ID | Requirement | Status |
|----|-------------|--------|
| R1 | Meeting-end detection (page navigate, URL change, participants left) | Done |
| R2 | Single stop handler (no duplicate files) | Done |
| R3 | Graceful handling of page context loss | Done |
| R4 | Protocol timeout for long meetings (Puppeteer) | Done |
| R5 | Health endpoints for bot and backend | Done |

---

## Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NF1 | Bot server: Node.js, runs on port 3000 |
| NF2 | Backend: Flask/Python, runs on port 5000 |
| NF3 | App: Flutter, Android (iOS optional) |
| NF4 | Jitsi: meet.jit.si (or configurable) |
| NF5 | Chrome/Chromium required for Puppeteer |
| NF6 | FFmpeg required for WebM→MP4 conversion |

---

## APIs Used

### Bot Server (Node.js)

- `POST /api/start-recording` – Start recording for a room
- `POST /api/stop-recording` – Stop recording, upload, return minutes
- `GET /api/health` – Health check
- `GET /api/recordings` – List recordings (deduplicated by room)
- `GET /recordings/:file` – Serve recording file

### Flask Backend (Python)

- `POST /api/generate-minutes` – Upload audio, transcribe, return minutes
- `GET /api/health` – Health check
- `PATCH /api/meetings/:id/status` – Update meeting status (optional)

---

## Out of Scope (Current)

- Recording without bot (in-browser only)
- Multi-room concurrent recording
- Cloud storage (beyond Firebase)
- Real-time transcription during meeting
- Video recording
