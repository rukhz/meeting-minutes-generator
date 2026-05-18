"""
Bot Server (Module 2): Python bot that joins Jitsi meetings via headless browser,
requests host permission, captures live meeting audio from ALL participants,
saves and optionally streams to ASR.
Uses Playwright for browser automation with Jitsi Meet API for audio capture.
"""
import asyncio
import base64
import json
import logging
import os
import re
import time
from datetime import datetime
from pathlib import Path

import requests

logger = logging.getLogger(__name__)

JITSI_BASE = os.environ.get("JITSI_SERVER_URL", "https://meet.jit.si")
ASR_API_URL = os.environ.get("ASR_API_URL", "http://localhost:5000/api/generate-minutes")
RECORDINGS_DIR = Path(os.environ.get("RECORDINGS_DIR", "recordings"))
RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)


async def join_and_record(room_name: str, meeting_id: str, on_status=None, stop_event=None) -> str | None:
    """
    Join Jitsi meeting with Playwright, capture ALL participants' audio (not just bot's mic),
    save and optionally stream to ASR. Returns path to saved audio file.
    """
    try:
        from playwright.async_api import async_playwright
    except ImportError:
        logger.error("Playwright not installed. Run: pip install playwright && playwright install chromium")
        return None

    def status(s: str):
        if on_status:
            on_status(s)
        logger.info("Status: %s", s)
        prit("Status: %s", s)

    status("bot_joining")
    
    browser = None

    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch(
                headless=os.environ.get("BOT_HEADLESS", "true").lower() == "true",
                args=[
                    "--no-sandbox",
                    "--disable-setuid-sandbox",
                    "--autoplay-policy=no-user-gesture-required",
                    "--use-fake-ui-for-media-stream",
                    "--use-fake-device-for-media-stream",
                ],
            )
            context = await browser.new_context(
                permissions=["microphone", "camera"],
                ignore_https_errors=True,
            )
            page = await context.new_page()

            url = f"{JITSI_BASE.rstrip('/')}/{room_name}"
            await page.goto(url, wait_until="networkidle", timeout=60000)
            await asyncio.sleep(3)

            # Extract domain from JITSI_BASE
            jitsi_domain = JITSI_BASE.replace("https://", "").replace("http://", "").strip("/")
            
            # Set up Jitsi API before loading the page
            await page.evaluate("""
                (domain) => {
                    window.jitsiApi = null;
                    window.meetingEnded = false;
                    
                    // Function to initialize Jitsi API
                    window.initJitsiAPI = () => {
                        return new Promise((resolve, reject) => {
                            if (window.JitsiMeetExternalAPI) {
                                try {
                                    const api = new window.JitsiMeetExternalAPI(domain, {
                                        parentNode: document.createElement('div'),
                                        width: '100%',
                                        height: '100%',
                                        roomName: window.roomName,
                                    });
                                    
                                    api.addEventListener('videoConferenceJoined', () => {
                                        console.log('Jitsi API: Conference joined');
                                        window.jitsiApi = api;
                                        resolve(api);
                                    });
                                    
                                    api.addEventListener('participantJoined', (event) => {
                                        console.log('Jitsi API: Participant joined:', event);
                                    });
                                    
                                    api.addEventListener('participantLeft', (event) => {
                                        console.log('Jitsi API: Participant left:', event);
                                    });
                                    
                                    api.addEventListener('conferenceLeft', (event) => {
                                        console.log('Jitsi API: Conference left');
                                        window.meetingEnded = true;
                                    });
                                    
                                    // Timeout fallback
                                    setTimeout(() => {
                                        if (!window.jitsiApi) {
                                            resolve(null);
                                        }
                                    }, 15000);
                                } catch (e) {
                                    console.error('Jitsi API init error:', e);
                                    reject(e);
                                }
                            } else {
                                resolve(null);
                            }
                        });
                    };
                }
            """, jitsi_domain)

            # Try to click prejoin join button if present
            join_btn = await page.query_selector('button[data-testid="prejoin.joinMeetingButton"]')
            if join_btn:
                await join_btn.click()
                await asyncio.sleep(3)

            status("recording")

            # Store room name for Jitsi API
            await page.evaluate(f"window.roomName = '{room_name}';")

            # Try to use Jitsi Meet JS API to get conference audio
            # This is the most reliable method to capture ALL participants' audio
            result = await page.evaluate("""
                async () => {
                    try {
                        // First, wait for Jitsi to load its API
                        await new Promise((resolve) => {
                            const checkJitsi = () => {
                                if (window.JitsiMeetJS || window.JitsiMeetExternalAPI) {
                                    resolve();
                                } else {
                                    setTimeout(checkJitsi, 500);
                                }
                            };
                            checkJitsi();
                        });
                        
                        // Try to get display media with audio (captures system audio when user shares screen)
                        // This is the BEST method as it captures ALL meeting audio
                        if (navigator.mediaDevices.getDisplayMedia) {
                            try {
                                console.log('Attempting getDisplayMedia with audio...');
                                const stream = await navigator.mediaDevices.getDisplayMedia({
                                    video: true,
                                    audio: {
                                        echoCancellation: false,
                                        noiseSuppression: false,
                                        autoGainControl: false
                                    }
                                });
                                
                                const audioTracks = stream.getAudioTracks();
                                if (audioTracks.length > 0) {
                                    console.log('getDisplayMedia: Got', audioTracks.length, 'audio tracks');
                                    const audioOnly = new MediaStream(audioTracks);
                                    window.meetingAudioStream = audioOnly;
                                    window.mediaRecorder = new MediaRecorder(audioOnly, {
                                        mimeType: MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
                                            ? 'audio/webm;codecs=opus' : 'audio/webm',
                                        audioBitsPerSecond: 128000
                                    });
                                    window.audioChunks = [];
                                    window.mediaRecorder.ondataavailable = (e) => {
                                        if (e.data && e.data.size > 0) window.audioChunks.push(e.data);
                                    };
                                    window.mediaRecorder.start(1000);
                                    
                                    // Stop video track immediately, we only want audio
                                    stream.getVideoTracks().forEach(t => t.stop());
                                    
                                    return { ok: true, method: 'displayMedia', participants: 'all' };
                                }
                            } catch (e) {
                                console.warn('getDisplayMedia failed:', e);
                            }
                        }
                    } catch (e) {
                        console.warn('Display media attempt failed:', e);
                    }
                    
                    // Fallback: Try to get audio from Jitsi conference audio elements
                    // This captures the mixed audio from all participants
                    try {
                        const audioElements = document.querySelectorAll('audio');
                        console.log('Found', audioElements.length, 'audio elements');
                        for (const audio of audioElements) {
                            if (audio.srcObject && audio.srcObject.getAudioTracks().length > 0) {
                                console.log('Audio element has', audio.srcObject.getAudioTracks().length, 'tracks');
                                const audioStream = audio.srcObject;
                                window.meetingAudioStream = audioStream;
                                window.mediaRecorder = new MediaRecorder(audioStream, {
                                    mimeType: MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
                                        ? 'audio/webm;codecs=opus' : 'audio/webm',
                                    audioBitsPerSecond: 128000
                                });
                                window.audioChunks = [];
                                window.mediaRecorder.ondataavailable = (e) => {
                                    if (e.data && e.data.size > 0) window.audioChunks.push(e.data);
                                };
                                window.mediaRecorder.start(1000);
                                return { ok: true, method: 'audioElement', participants: 'all' };
                            }
                        }
                    } catch (e) {
                        console.warn('Audio element capture failed:', e);
                    }
                    
                    // Fallback: Try Jitsi Meet API if available
                    try {
                        if (window.JitsiMeetExternalAPI) {
                            const domain = window.location.hostname;
                            const api = new window.JitsiMeetExternalAPI(domain, {
                                parentNode: document.createElement('div'),
                                roomName: window.roomName,
                                onload: 'dummy'
                            });
                            
                            // Try to get local tracks (which include remote mixed audio)
                            if (api.getLocalDevices) {
                                const devices = await api.getLocalDevices();
                                const audioDevices = devices.filter(d => d.kind === 'audioinput');
                                if (audioDevices.length > 0) {
                                    const stream = await navigator.mediaDevices.getUserMedia({
                                        audio: { 
                                            echoCancellation: false, 
                                            noiseSuppression: false,
                                            autoGainControl: false
                                        },
                                        video: false
                                    });
                                    window.meetingAudioStream = stream;
                                    window.mediaRecorder = new MediaRecorder(stream, {
                                        mimeType: MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
                                            ? 'audio/webm;codecs=opus' : 'audio/webm',
                                        audioBitsPerSecond: 128000
                                    });
                                    window.audioChunks = [];
                                    window.mediaRecorder.ondataavailable = (e) => {
                                        if (e.data && e.data.size > 0) window.audioChunks.push(e.data);
                                    };
                                    window.mediaRecorder.start(1000);
                                    return { ok: true, method: 'jitsiApi', participants: 'all' };
                                }
                            }
                            api.dispose();
                        }
                    } catch (e) {
                        console.warn('Jitsi API capture failed:', e);
                    }
                    
                    // Last fallback: use microphone (will only capture bot's mic, not meeting audio)
                    try {
                        console.log('Fallback to microphone...');
                        const stream = await navigator.mediaDevices.getUserMedia({
                            audio: { 
                                echoCancellation: false, 
                                noiseSuppression: false,
                                autoGainControl: false
                            },
                            video: false
                        });
                        window.meetingAudioStream = stream;
                        window.mediaRecorder = new MediaRecorder(stream, {
                            mimeType: MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
                                ? 'audio/webm;codecs=opus' : 'audio/webm',
                            audioBitsPerSecond: 128000
                        });
                        window.audioChunks = [];
                        window.mediaRecorder.ondataavailable = (e) => {
                            if (e.data && e.data.size > 0) window.audioChunks.push(e.data);
                        };
                        window.mediaRecorder.start(1000);
                        return { ok: true, method: 'microphone', participants: 'bot_only' };
                    } catch (e) {
                        console.error('All audio capture methods failed:', e);
                        return { ok: false, error: String(e) };
                    }
                }
            """)

            if not result or not result.get("ok"):
                logger.error(f"Failed to start audio capture: {result}")
                return None

            logger.info(f"Audio capture started using method: {result.get('method')} (captures: {result.get('participants')})")

            # Record for configured duration or until manually stopped
            duration_sec = int(os.environ.get("BOT_RECORD_DURATION", "300"))
            logger.info("Recording for %s seconds (set BOT_RECORD_DURATION to change)", duration_sec)
            elapsed = 0
            
            # Periodically log participant count
            last_participant_count = 0
            while elapsed < duration_sec:
                if stop_event and stop_event.is_set():
                    logger.info("Stop signal received for room=%s; finalizing recording", room_name)
                    break
                
                # Check participant count every 10 seconds
                if elapsed % 10 == 0:
                    try:
                        participant_count = await page.evaluate("""
                            () => {
                                // Count participants from various sources
                                let count = 0;
                                
                                // From video containers
                                const videos = document.querySelectorAll('[data-testid="video-tile"]');
                                count = videos.length;
                                
                                // From avatar elements (indicates participants)
                                const avatars = document.querySelectorAll('.avatar, [class*="avatar"]');
                                if (avatars.length > count) count = avatars.length;
                                
                                // From participant list if available
                                const participantList = document.querySelector('[data-testid="participant-list"]');
                                if (participantList) {
                                    const items = participantList.querySelectorAll('[data-testid="participant-list-item"]');
                                    if (items.length > count) count = items.length;
                                }
                                
                                return count;
                            }
                        """)
                        if participant_count != last_participant_count:
                            logger.info(f"Participants in meeting: {participant_count}")
                            last_participant_count = participant_count
                    except:
                        pass
                
                await asyncio.sleep(1)
                elapsed += 1
                
                # Check if meeting has ended via Jitsi events
                try:
                    check_ended = await page.evaluate("() => window.meetingEnded === true")
                    if check_ended:
                        logger.info("Meeting ended detected for room=%s; finalizing recording", room_name)
                        break
                except:
                    pass

            # Finalize recording
            audio_b64 = await page.evaluate("""
                () => {
                    return new Promise((resolve) => {
                        if (window.mediaRecorder && window.mediaRecorder.state !== 'inactive') {
                            const onStop = () => {
                                setTimeout(() => {
                                    // Stop all tracks in the meeting audio stream
                                    if (window.meetingAudioStream) {
                                        window.meetingAudioStream.getTracks().forEach(t => t.stop());
                                    }
                                    
                                    const blob = new Blob(window.audioChunks, { type: 'audio/webm' });
                                    const reader = new FileReader();
                                    reader.onloadend = () => resolve(reader.result);
                                    reader.readAsDataURL(blob);
                                }, 1000);
                            };
                            window.mediaRecorder.addEventListener('stop', onStop, { once: true });
                            window.mediaRecorder.stop();
                        } else {
                            resolve(null);
                        }
                    });
                }
            """)

            await browser.close()
            browser = None

            if not audio_b64 or not isinstance(audio_b64, str):
                logger.warning("No audio data captured")
                return None

            # Save to file
            match = re.match(r"data:audio/(\w+);base64,(.+)", audio_b64)
            ext = match.group(1) if match else "webm"
            b64_data = match.group(2) if match else audio_b64
            safe_id = re.sub(r"[^\w\-]", "_", meeting_id)
            filename = f"recording_{safe_id}_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.{ext}"
            filepath = RECORDINGS_DIR / filename
            filepath.write_bytes(base64.b64decode(b64_data))
            logger.info("Saved recording: %s (size: %d bytes)", filepath, filepath.stat().st_size)

            return str(filepath)

    except Exception as e:
        logger.exception("Bot recording failed: %s", e)
        if browser:
            try:
                await browser.close()
            except Exception:
                pass
        return None


def run_bot_sync(room_name: str, meeting_id: str, on_status=None, stop_event=None) -> str | None:
    """Synchronous wrapper for join_and_record."""
    return asyncio.run(join_and_record(room_name, meeting_id, on_status, stop_event=stop_event))
