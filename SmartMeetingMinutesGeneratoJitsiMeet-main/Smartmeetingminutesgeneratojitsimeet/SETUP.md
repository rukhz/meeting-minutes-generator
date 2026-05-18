# Setup Instructions

## Quick Start

### 1. Flutter App Setup

```bash
# Install Flutter dependencies
flutter pub get

# Run the app
flutter run
```

### 2. Server Bot Setup

```bash
# Navigate to server directory
cd server

# Install Node.js dependencies
npm install

# Start the server
npm start
```

## Important Notes

### Server URL Configuration

When running the Flutter app, configure the server URL based on your setup:

- **Android Emulator**: Use `http://10.0.2.2:3000` (maps to localhost on your machine)
- **iOS Simulator**: Use `http://localhost:3000`
- **Physical Device**: Use `http://YOUR_COMPUTER_IP:3000` (e.g., `http://192.168.1.100:3000`)

To find your computer's IP address:
- Windows: `ipconfig` in Command Prompt
- Mac/Linux: `ifconfig` or `ip addr`

### Permissions

The Flutter app requires:
- Internet permission (for API calls)
- Storage permission (for saving recordings)
- Microphone permission (for Jitsi Meet)

These are already configured in `AndroidManifest.xml` for Android.

### Dependencies

**Flutter packages** (automatically installed with `flutter pub get`):
- `jitsi_meet_flutter_sdk` - Jitsi Meet integration
- `http` - HTTP requests
- `path_provider` - File system access
- `permission_handler` - Permission management
- `uuid` - UUID generation
- `share_plus` - File sharing

**Node.js packages** (automatically installed with `npm install`):
- `express` - Web server
- `puppeteer` - Browser automation
- `cors` - CORS support
- `fs-extra` - File system utilities

### Troubleshooting

1. **Server won't start**: Make sure Node.js is installed (v14 or higher)
2. **Puppeteer errors**: Make sure Chrome/Chromium is installed
3. **Can't connect to server from app**: Check the server URL and firewall settings
4. **Recording not working**: Check browser console for errors in the server logs

