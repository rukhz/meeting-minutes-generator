# Jitsi Meeting Recorder

A Flask web application that allows you to join Jitsi Meet meetings and record the audio.

## Features

- 🎥 Join Jitsi Meet meetings through a web interface
- 🎙️ Record meeting audio directly in the browser
- 💾 Save recordings with timestamps
- 📁 View and download saved recordings
- 🎨 Modern, user-friendly interface

## Requirements

- Python 3.7 or higher
- Modern web browser with microphone permissions (Chrome, Edge, Firefox, Safari)
- Internet connection

## Installation

1. **Clone or download this repository**

2. **Create a virtual environment (recommended)**:
```bash
python -m venv venv
```

3. **Activate the virtual environment**:
   - On Windows:
     ```bash
     venv\Scripts\activate
     ```
   - On macOS/Linux:
     ```bash
     source venv/bin/activate
     ```

4. **Install dependencies**:
```bash
pip install -r requirements.txt
```

## Usage

1. **Start the Flask application**:
```bash
python app.py
```

2. **Open your browser** and navigate to:
```
http://localhost:5000
```

3. **Join a meeting**:
   - Enter the meeting room name (Jitsi meeting ID)
   - Optionally enter your name
   - Click "Join Meeting"

4. **Record audio**:
   - Allow microphone permissions when prompted
   - Click "Start Recording" when ready
   - Click "Stop Recording" to save the recording

5. **View recordings**:
   - Click "View Saved Recordings" from the home page
   - Download any recording by clicking the "Download" button

## How It Works

- The application uses Jitsi Meet's External API to embed meetings in the web page
- Audio recording is done client-side using the browser's MediaRecorder API
- Recordings are saved as WebM audio files on the server
- All recordings are stored in the `recordings/` directory

## Browser Compatibility

- **Chrome/Edge**: Full support (recommended)
- **Firefox**: Full support
- **Safari**: May have limited MediaRecorder support
- **Mobile browsers**: Limited support (desktop recommended)

## Notes

- Recordings are saved in WebM format (audio only)
- Make sure to allow microphone permissions in your browser
- The recording captures audio from your microphone, not the entire meeting audio stream
- For best results, use Chrome or Edge browser
- Recordings are stored locally on the server in the `recordings/` folder

## Configuration

You can modify the following settings in `app.py`:

- `UPLOAD_FOLDER`: Directory where recordings are saved (default: `recordings/`)
- `MAX_CONTENT_LENGTH`: Maximum file size for uploads (default: 500MB)
- `SECRET_KEY`: Flask secret key (change in production)

## Production Deployment

For production deployment:

1. Set a secure `SECRET_KEY` environment variable
2. Use a production WSGI server (e.g., Gunicorn, uWSGI)
3. Configure proper HTTPS/SSL
4. Set up proper file storage for recordings
5. Configure CORS if needed
6. Set up proper logging and error handling

## License

This project is provided as-is for educational and personal use.

## Troubleshooting

**Issue: Microphone not working**
- Check browser permissions for microphone access
- Ensure your microphone is connected and working
- Try a different browser (Chrome recommended)

**Issue: Recording not saving**
- Check that the `recordings/` directory exists and is writable
- Check browser console for errors
- Ensure you have sufficient disk space

**Issue: Can't join Jitsi meeting**
- Check your internet connection
- Verify the meeting ID is correct
- Some Jitsi servers may require authentication

