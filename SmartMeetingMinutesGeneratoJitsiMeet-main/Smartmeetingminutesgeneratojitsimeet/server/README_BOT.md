# Bot Server - Record All Participants

The bot joins the Jitsi meeting on your **PC** and captures the mixed conference audio (all participants).

## Setup

1. Install Node.js (v16+)
2. From this folder: `npm install`
3. Run: `npm start`

The bot runs on port 3000.

## Usage

1. Start the Bot Server on your PC
2. In the Flutter app, set **Bot Server URL** to `http://YOUR_PC_IP:3000` (same Wi‑Fi as phone)
3. Enable **Record all participants (Bot)**
4. Create & join a meeting

When the bot starts, a browser window opens on the PC. **Important**: When prompted to share:
1. Choose **This tab** (the Jitsi meeting tab)
2. **Check "Share tab audio"** – required for voice capture
3. Click **Share**

Without "Share tab audio", recording will fall back to less reliable capture and may produce poor or no audio.

The bot will capture all participants' voices. When you leave the meeting, the recording is downloaded and sent to the Flask backend for transcription.
