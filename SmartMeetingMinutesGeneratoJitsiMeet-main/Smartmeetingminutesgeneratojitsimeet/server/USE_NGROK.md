# Reach bot server from phone using ngrok (alternative to same Wi‑Fi)

If the phone cannot reach your PC (different network, firewall, etc.), use **ngrok** to expose the bot server with a public HTTPS URL. The phone can then use that URL from anywhere.

## Steps

### 1. Install ngrok
- Download from https://ngrok.com/download (or `choco install ngrok` on Windows).
- Sign up at ngrok.com and get your auth token; run `ngrok config add-authtoken YOUR_TOKEN`.

### 2. Start the bot server (Terminal 1)
```bash
cd server
npm start
```
Leave it running.

### 3. Start ngrok (Terminal 2)
```bash
ngrok http 3000
```
You will see something like:
```
Forwarding   https://abc123.ngrok-free.app -> http://localhost:3000
```

### 4. In the app
- Set **Server URL** to the **https** URL from ngrok, e.g. `https://abc123.ngrok-free.app`
- Turn **Bot recording** ON.
- Tap Test or Create meeting.

The phone will connect via the internet to ngrok, which forwards to your PC. No need for same Wi‑Fi.
