const express = require('express');
const puppeteer = require('puppeteer');
const cors = require('cors');
const fs = require('fs-extra');
const path = require('path');
const http = require('http');
const https = require('https');
const { execFile, spawn } = require('child_process');
const { promisify } = require('util');
const execFileP = promisify(execFile);

const app = express();
const PORT = process.env.PORT || 3000;
const BOT_HEADLESS = (process.env.BOT_HEADLESS || 'false').toLowerCase() === 'true';
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:5000/api/generate-minutes';

app.use(cors());
app.use(express.json({ limit: '100mb' }));
app.use('/recordings', express.static(path.join(__dirname, 'recordings')));

const activeRecordings = new Map();
const recordingsDir = path.join(__dirname, 'recordings');
fs.ensureDirSync(recordingsDir);

// Prevent process crash on "Execution context was destroyed" (page navigates during evaluate)
process.on('unhandledRejection', (reason, promise) => {
  const msg = String(reason?.message || reason);
  if (msg.includes('Execution context was destroyed') || msg.includes('Target closed') || msg.includes('Session closed')) {
    console.warn('[Recovery] Page context lost (expected when user leaves meeting)');
    return;
  }
  console.error('Unhandled rejection:', reason);
});

function getRequestBaseUrl(req) {
  const host = req.headers.host || `localhost:${PORT}`;
  const proto = (req.headers['x-forwarded-proto'] || '').toString().trim() || 'http';
  return `${proto}://${host}`;
}

function isFfmpegAvailable() {
  try {
    const { execFileSync } = require('child_process');
    execFileSync('ffmpeg', ['-version'], { stdio: 'ignore', timeout: 5000 });
    return true;
  } catch (_) {
    return false;
  }
}

async function convertWebmToMp4(webmPath) {
  if (!webmPath || !webmPath.toLowerCase().endsWith('.webm')) return null;
  if (!isFfmpegAvailable()) {
    console.warn('[Convert] ffmpeg not found - install from https://ffmpeg.org and add to PATH');
    return null;
  }
  const mp4Path = webmPath.replace(/\.webm$/i, '.mp4');
  try {
    await new Promise((resolve, reject) => {
      const proc = spawn('ffmpeg', ['-y', '-i', webmPath, '-c:a', 'aac', '-b:a', '128k', mp4Path], {
        stdio: ['ignore', 'pipe', 'pipe']
      });
      const timer = setTimeout(() => {
        proc.kill('SIGTERM');
        reject(new Error('ffmpeg timeout'));
      }, 60000);
      proc.on('error', (e) => { clearTimeout(timer); reject(e); });
      proc.on('close', (code) => {
        clearTimeout(timer);
        code === 0 ? resolve() : reject(new Error(`ffmpeg exited ${code}`));
      });
      proc.stdout?.on('data', () => {});
      proc.stderr?.on('data', () => {});
    });
    if (await fs.pathExists(mp4Path)) {
      const stats = await fs.stat(mp4Path);
      if (stats.size > 0) {
        console.log(`[Convert] webm→mp4 ok: ${path.basename(mp4Path)}`);
        return mp4Path;
      }
    }
  } catch (e) {
    console.warn('[Convert] ffmpeg webm→mp4 failed:', e.message || e);
  }
  return null;
}

/** Ensure recording is MP4: convert webm to mp4 when call ends. Returns path to serve (mp4 or original). */
async function ensureMp4AfterCallEnd(filePath) {
  if (!filePath || !(await fs.pathExists(filePath))) return filePath;
  const mp4Path = await convertWebmToMp4(filePath);
  return mp4Path || filePath;
}

function getMinutesPathForRoom(roomName) {
  return path.join(recordingsDir, `recording_${roomName}_minutes.json`);
}

function saveMinutesForRoom(roomName, minutes) {
  try {
    if (minutes && typeof minutes === 'object') {
      const p = getMinutesPathForRoom(roomName);
      fs.writeFileSync(p, JSON.stringify(minutes), 'utf8');
    }
  } catch (e) {
    console.warn(`[${roomName}] Failed to save minutes:`, e?.message);
  }
}

function loadMinutesForRoom(roomName) {
  try {
    const p = getMinutesPathForRoom(roomName);
    if (fs.existsSync(p)) {
      const raw = fs.readFileSync(p, 'utf8');
      return JSON.parse(raw);
    }
  } catch (_) {}
  return null;
}

function findLatestRecordingForRoom(roomName) {
  try {
    const prefix = `recording_${roomName}_`;
    const files = fs.readdirSync(recordingsDir)
      .filter((file) => file.startsWith(prefix) && !file.endsWith('_minutes.json') && !file.endsWith('_partial.webm'))
      .map((file) => {
        const filePath = path.join(recordingsDir, file);
        const stats = fs.statSync(filePath);
        return { file, filePath, stats };
      })
      .filter((entry) => entry.stats.isFile() && entry.stats.size > 0)
      .sort((a, b) => b.stats.mtimeMs - a.stats.mtimeMs);
    return files.length ? files[0] : null;
  } catch (_) {
    return null;
  }
}

async function updateMeetingStatus(backendBaseUrl, meetingId, status, authToken, extra = null) {
  if (!meetingId || !backendBaseUrl) return;
  try {
    const url = `${backendBaseUrl.replace(/\/$/, '')}/api/meetings/${encodeURIComponent(meetingId)}/status`;
    const headers = { 'Content-Type': 'application/json' };
    if (authToken) headers.Authorization = `Bearer ${authToken}`;
    await fetch(url, { method: 'PATCH', headers, body: JSON.stringify({ status, ...(extra ? { extra } : {}) }) });
  } catch (e) {
    console.warn(`[status-update] Failed for meeting ${meetingId}:`, e?.message || e);
  }
}

async function uploadToBackend(filePath, meetingId, roomName, participants = [], authToken = null, backendBaseUrl = null) {
  let uploadUrl = (backendBaseUrl && backendBaseUrl.trim())
    ? `${backendBaseUrl.replace(/\/$/, '')}/api/generate-minutes`
    : BACKEND_URL;
  try {
    const u = new URL(uploadUrl);
    const host = u.hostname;
    if (host && host !== 'localhost' && host !== '127.0.0.1' && (host.startsWith('10.') || host.startsWith('192.168.') || /^172\.(1[6-9]|2[0-9]|3[01])\./.test(host))) {
      u.hostname = 'localhost';
      uploadUrl = u.toString();
      console.log(`[Upload] Using localhost for same-machine backend: ${uploadUrl}`);
    }
  } catch (_) {}
  return new Promise((resolve, reject) => {
    const boundary = '----FormBoundary' + Date.now();
    const fileName = path.basename(filePath);
    const fileData = fs.readFileSync(filePath);
    const ext = path.extname(filePath).toLowerCase();
    const mimeType = ext === '.mp4' ? 'video/mp4' : ext === '.mp3' ? 'audio/mpeg' : 'audio/webm';
    const safeParticipants = Array.isArray(participants) ? participants.filter(p => p && typeof p === 'object').map(p => ({ id: (p.id || '').toString(), name: (p.name || '').toString().trim() || 'Participant' })) : [];
    const header = `--${boundary}\r\nContent-Disposition: form-data; name="audio"; filename="${fileName}"\r\nContent-Type: ${mimeType}\r\n\r\n`;
    const footer = `\r\n--${boundary}--\r\n`;
    const meetingIdPart = `--${boundary}\r\nContent-Disposition: form-data; name="meeting_id"\r\n\r\n${meetingId || roomName}\r\n`;
    const metadataPart = `--${boundary}\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n${JSON.stringify({ participants: safeParticipants })}\r\n`;
    const body = Buffer.concat([Buffer.from(header), fileData, Buffer.from(meetingIdPart), Buffer.from(metadataPart), Buffer.from(footer)]);
    const urlParts = new URL(uploadUrl);
    const isHttps = urlParts.protocol === 'https:';
    const transport = isHttps ? https : http;
    const options = {
      hostname: urlParts.hostname,
      port: urlParts.port || (isHttps ? 443 : 80),
      path: `${urlParts.pathname || ''}${urlParts.search || ''}`,
      method: 'POST',
      headers: { 'Content-Type': `multipart/form-data; boundary=${boundary}`, 'Content-Length': body.length }
    };
    if (authToken) options.headers.Authorization = `Bearer ${authToken}`;
    const request = transport.request(options, (response) => {
      let data = '';
      response.on('data', chunk => data += chunk);
      response.on('end', () => {
        try { resolve(JSON.parse(data)); } catch (e) { resolve({ success: false, error: data }); }
      });
    });
    request.on('error', reject);
    request.write(body);
    request.end();
  });
}

async function checkMeetingEnded(page) {
  try {
    return await page.evaluate(() => {
      // CRITICAL: Check these FIRST - while still on Jitsi page.
      if (window.hasJoinedMeeting) {
        try {
          const APP = window.APP;
          if (APP && APP.conference) {
            const participants = APP.conference.getParticipants ? APP.conference.getParticipants() : null;
            const count = participants && typeof participants.size === 'number' ? participants.size : (participants ? Object.keys(participants).length : -1);
            if (typeof count === 'number' && count >= 0) {
              window.maxParticipantsSeen = Math.max(window.maxParticipantsSeen || 0, count);
              // Treat 0 or 1 as "ended" when we've seen 2+ before (bot alone; getParticipants may include/exclude self)
              if (count <= 1 && (window.maxParticipantsSeen || 0) >= 2) {
                return { ended: true, reason: 'No other participants (bot alone)', canStop: true };
              }
              if (count === 0 && (window.maxParticipantsSeen || 0) >= 1) {
                return { ended: true, reason: 'No participants left', canStop: true };
              }
            }
            const numParticipants = APP.conference.getParticipantCount ? APP.conference.getParticipantCount() : null;
            if (typeof numParticipants === 'number' && numParticipants <= 1 && (window.maxParticipantsSeen || 0) >= 2) {
              return { ended: true, reason: 'Participant count dropped to 1', canStop: true };
            }
          }
        } catch (_) {}
        const bodyText = document.body.innerText.toLowerCase();
        const endPhrases = [
          'meeting ended', 'call ended', 'conference ended', 'you\'re the only one', 'you are the only participant',
          'only one in this meeting', 'no one else is in this meeting', 'everyone has left'
        ];
        if (endPhrases.some(p => bodyText.includes(p))) return { ended: true, reason: 'End message visible', canStop: true };
        const leaveBtn = document.querySelector('[data-testid="toolbar-button-leave"]');
        if (!leaveBtn || !leaveBtn.offsetParent) return { ended: true, reason: 'Leave button not visible', canStop: true };
      }
      const href = window.location.href.toLowerCase();
      if (href.includes('ended') || href.includes('close3') || href.includes('/static/close') || href.includes('close.html')) {
        return { ended: true, reason: 'URL changed to end page', canStop: false };
      }
      return { ended: false };
    });
  } catch (e) {
    if (e.message && (e.message.includes('Execution context was destroyed') || e.message.includes('context was destroyed') || e.message.includes('navigation') || e.message.includes('Target closed'))) {
      return { ended: true, reason: 'Page navigated away', canStop: false };
    }
    return { ended: false, error: e.message };
  }
}

function isContextDestroyedError(e) {
  return e && e.message && (e.message.includes('Execution context was destroyed') || e.message.includes('context was destroyed') || e.message.includes('Target closed'));
}

async function flushPartialRecording(page, roomName) {
  if (!page || (typeof page.isClosed === 'function' && page.isClosed())) return null;
  try {
    const result = await page.evaluate(() => {
      if (!window.mediaRecorder || window.mediaRecorder.state !== 'recording') return null;
      const chunks = [...(Array.isArray(window.audioChunks) ? window.audioChunks : [])];
      if (chunks.length === 0) return null;
      const mimeType = window.mediaRecorder?.mimeType || 'audio/webm';
      const blob = new Blob(chunks, { type: mimeType });
      return new Promise((resolve) => {
        const reader = new FileReader();
        reader.onloadend = () => resolve({ audioData: reader.result, blobSize: blob.size });
        reader.onerror = () => resolve(null);
        reader.readAsDataURL(blob);
      });
    });
    if (!result || !result.audioData) return null;
    const comma = result.audioData.indexOf(',');
    if (comma === -1) return null;
    const base64Data = result.audioData.substring(comma + 1);
    if (!base64Data) return null;
    const partialPath = path.join(recordingsDir, `recording_${roomName}_partial.webm`);
    await fs.writeFile(partialPath, Buffer.from(base64Data, 'base64'));
    return partialPath;
  } catch (e) {
    if (isContextDestroyedError(e)) {
      // Page navigated - expected, no need to log
    }
    return null;
  }
}

async function autoStopRecording(roomName, recording = null) {
  console.log(`Auto-stopping recording for ${roomName}...`);
  const body = { roomName, autoUpload: true };
  if (recording) {
    if (recording.backendBaseUrl) body.backendBaseUrl = recording.backendBaseUrl;
    if (recording.meetingId) body.meetingId = recording.meetingId;
    if (Array.isArray(recording.participants) && recording.participants.length) body.participants = recording.participants;
  }
  for (let attempt = 0; attempt < 6; attempt++) {
    try {
      const response = await fetch(`http://localhost:${PORT}/api/stop-recording`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      const result = await response.json().catch(() => ({}));
      if (response.ok) return;
      if (response.status === 409) { await new Promise(resolve => setTimeout(resolve, 2500)); continue; }
      return;
    } catch (e) { await new Promise(resolve => setTimeout(resolve, 2500)); }
  }
}

async function joinMeeting(page) {
  const joinSelectors = [
    'button[data-testid="prejoin.joinMeetingButton"]',
    'button[data-testid="join-button"]',
    'button[class*="prejoin-button"]',
    'button[class*="join-button"]',
    'button:has-text("Join meeting")',
    'button:has-text("Join")',
    '#join-button',
    '.join-button'
  ];
  for (const selector of joinSelectors) {
    try {
      const button = await page.waitForSelector(selector, { timeout: 3000 });
      if (button) { await button.click(); console.log(`Clicked: ${selector}`); return true; }
    } catch (e) { continue; }
  }
  return await page.evaluate(() => {
    return !!document.querySelector('[data-testid="video-tile"]') ||
           !!document.querySelector('[data-testid="toolbar"]') ||
           !!document.querySelector('.meeting') ||
           !!document.querySelector('.conference');
  });
}

async function captureJitsiAudio(page) {
  console.log('[Audio] Trying Jitsi API...');
  return await page.evaluate(() => {
    return new Promise((resolve) => {
      try {
        const APP = window.APP;
        if (!APP || !APP.conference) return resolve({ ok: false, error: 'Jitsi APP not available' });
        const conference = APP.conference;
        if (!conference || !conference.getLocalTracks) return resolve({ ok: false, error: 'Conference API not available' });
        const participants = conference.getParticipants ? conference.getParticipants() : [];
        console.log(`[Audio] Jitsi API: ${participants.length} participants`);
        return resolve({ ok: true, method: 'jitsi-api', message: 'Jitsi API accessible' });
      } catch (e) { resolve({ ok: false, error: e.message }); }
    });
  });
}

async function setupMediaElementsAudio(page) {
  console.log('[Audio] Trying Web Audio / captureStream from media elements...');
  return await page.evaluate(() => {
    return new Promise((resolve) => {
      try {
        const videoElements = document.querySelectorAll('video');
        const audioElements = document.querySelectorAll('audio');
        const elements = [...videoElements, ...audioElements];
        console.log(`[Audio] Found ${videoElements.length} video, ${audioElements.length} audio elements`);
        for (const el of elements) {
          let stream = null;
          if (el.srcObject && el.srcObject.getAudioTracks) {
            const tracks = el.srcObject.getAudioTracks();
            if (tracks && tracks.length > 0) {
              stream = new MediaStream(Array.from(tracks));
            }
          }
          if (!stream && (el.captureStream || el.mozCaptureStream || el.webkitCaptureStream)) {
            try {
              const cap = el.captureStream || el.mozCaptureStream || el.webkitCaptureStream;
              stream = typeof cap === 'function' ? cap.call(el) : cap();
            } catch (e) { continue; }
          }
          if (stream && stream.getAudioTracks().length > 0) {
            const audioOnly = new MediaStream(stream.getAudioTracks());
            window.audioChunks = [];
            window.mediaRecorder = null;
            window.audioStream = audioOnly;
            const mimeTypes = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'];
            const mimeType = mimeTypes.find(m => MediaRecorder.isTypeSupported(m)) || 'audio/webm';
            const recorder = new MediaRecorder(audioOnly, { mimeType, audioBitsPerSecond: 128000, videoBitsPerSecond: 0 });
            recorder.ondataavailable = (e) => { if (e.data && e.data.size > 0) window.audioChunks.push(e.data); };
            recorder.onstart = () => { window.audioChunks = []; };
            recorder.onstop = () => { console.log(`[Audio] Stopped with ${window.audioChunks.length} chunks`); };
            recorder.start(500);
            window.mediaRecorder = recorder;
            console.log('[Audio] MediaRecorder started from media element');
            return resolve({ ok: true, method: 'web-audio', mimeType });
          }
        }
        return resolve({ ok: false, error: 'No capturable audio in media elements' });
      } catch (e) { resolve({ ok: false, error: e.message }); }
    });
  });
}

async function setupDisplayMediaAudio(page, timeoutMs = 30000) {
  console.log('[Audio] Trying getDisplayMedia... (Share this tab, check "Share tab audio", pick Jitsi tab)');
  return await page.evaluate((timeout) => {
    return new Promise(async (resolve) => {
      try {
        window.audioChunks = [];
        window.mediaRecorder = null;
        window.audioStream = null;
        let stream = null;
        const timeoutPromise = new Promise((_, rej) => setTimeout(() => rej(new Error('Share timed out - click Share, pick Jitsi tab, check Share tab audio within 30s')), timeout));
        try {
          stream = await Promise.race([
            navigator.mediaDevices.getDisplayMedia({
              video: { cursor: 'never', displaySurface: 'browser' },
              audio: true
            }),
            timeoutPromise
          ]);
        } catch (err) {
          try {
            stream = await Promise.race([
              navigator.mediaDevices.getDisplayMedia({ video: { cursor: 'never' }, audio: false }),
              timeoutPromise
            ]);
          } catch (err2) {
            return resolve({ ok: false, error: `getDisplayMedia failed: ${err.message}` });
          }
        }
        if (!stream) return resolve({ ok: false, error: 'Null stream' });
        const audioTracks = stream.getAudioTracks();
        const videoTracks = stream.getVideoTracks();
        console.log(`[Audio] Stream: ${audioTracks.length} audio, ${videoTracks.length} video`);
        videoTracks.forEach(t => t.stop());
        if (audioTracks.length === 0) {
          stream.getTracks().forEach(t => t.stop());
          return resolve({ ok: false, error: 'No audio tracks', requiresUserInteraction: true });
        }
        window.audioStream = stream;
        const mimeTypes = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'];
        let selectedMimeType = mimeTypes.find(m => MediaRecorder.isTypeSupported(m)) || 'audio/webm';
        console.log('[Audio] MIME type:', selectedMimeType);
        const mediaRecorder = new MediaRecorder(stream, { mimeType: selectedMimeType, audioBitsPerSecond: 128000, videoBitsPerSecond: 0 });
        mediaRecorder.ondataavailable = (event) => {
          if (event.data && event.data.size > 0) { window.audioChunks.push(event.data); }
        };
        mediaRecorder.onstart = () => { window.audioChunks = []; };
        mediaRecorder.onstop = () => { console.log(`[Audio] Stopped with ${window.audioChunks.length} chunks`); };
        mediaRecorder.start(500);
        window.mediaRecorder = mediaRecorder;
        console.log('[Audio] MediaRecorder started');
        return resolve({ ok: true, method: 'display-media', mimeType: selectedMimeType });
      } catch (err) { return resolve({ ok: false, error: String(err?.message || err) }); }
    });
  }, timeoutMs);
}

async function setupAudioRecording(page) {
  console.log('[Audio] Starting audio capture...');
  // When browser is visible: try getDisplayMedia first - user can share Jitsi tab (most reliable)
  if (!BOT_HEADLESS) {
    const dmResult = await setupDisplayMediaAudio(page);
    if (dmResult.ok) return { ...dmResult, method: 'display-media' };
    console.log('[Audio] getDisplayMedia failed:', dmResult.error);
  }
  // Try capturing from Jitsi's video/audio elements
  let result = await setupMediaElementsAudio(page);
  if (result.ok) return { ...result, method: 'web-audio' };
  console.log('[Audio] Web Audio / captureStream failed:', result.error);
  // Fallback: getDisplayMedia (when headless) or retry
  result = await setupDisplayMediaAudio(page);
  if (result.ok) return { ...result, method: 'display-media' };
  console.log('[Audio] getDisplayMedia failed:', result.error);
  return { ok: false, error: 'All audio capture methods failed', details: result.error };
}

app.post('/api/start-recording', async (req, res) => {
  const { roomName, meetingId, participants, authToken, backendBaseUrl } = req.body;
  if (!roomName) return res.status(400).json({ error: 'Room name is required' });
  if (activeRecordings.has(roomName)) return res.status(400).json({ error: 'Recording already in progress' });

  try {
    activeRecordings.set(roomName, {
      status: 'joining',
      browser: null,
      page: null,
      startTime: new Date(),
      meetingId,
      participants: Array.isArray(participants) ? participants : [],
      authToken: authToken || null,
      backendBaseUrl: backendBaseUrl || null
    });
    await updateMeetingStatus(backendBaseUrl, meetingId || roomName, 'bot_joining', authToken || null);

    const browser = await puppeteer.launch({
      headless: BOT_HEADLESS ? 'new' : false,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--window-size=1280,720',
        '--autoplay-policy=no-user-gesture-required',
        '--disable-features=AudioServiceOutOfProcess',
        '--allow-http-screen-capture',
        '--enable-usermedia-screen-capturing',
        '--disable-web-security',
        '--allow-file-access-from-files'
      ]
    });
    const rec = activeRecordings.get(roomName);
    if (rec) rec.browser = browser;

    const page = await browser.newPage();

    await page.evaluateOnNewDocument(() => {
      window.audioChunks = [];
      window.mediaRecorder = null;
      window.audioStream = null;
      window.meetingEnded = false;
      window.hasJoinedMeeting = false;
      window.maxParticipantsSeen = 0;
    });

    // Join muted + no video to avoid beep and spinning green circle; disable join/leave sounds
    const jitsiConfig = [
      'config.startWithAudioMuted=true',
      'config.startWithVideoMuted=true',
      'config.disableJoinLeaveSounds=true'
    ].join('&');
    const jitsiUrl = `https://meet.jit.si/${roomName}#${jitsiConfig}`;
    console.log(`Navigating to Jitsi room: ${roomName}`);
    await page.goto(jitsiUrl, { waitUntil: 'networkidle2', timeout: 30000 });
    await page.waitForTimeout(1500);

    await page.evaluate(() => {
      document.querySelectorAll('audio, video').forEach(el => { el.volume = 0; el.muted = true; });
      console.log('[Audio] Muted all elements');
    });

    const joinedMeeting = await joinMeeting(page);
    if (joinedMeeting) {
      console.log('Joined meeting');
      await page.evaluate(() => { window.hasJoinedMeeting = true; });
    }
    // Wait for user to join and streams to appear
    await page.waitForTimeout(5000);

    // Continuous audio muting to prevent feedback/beeping
    const muteInterval = setInterval(() => {
      try {
        page.evaluate(() => {
          document.querySelectorAll('audio, video').forEach(el => {
            if (el.volume !== 0) { el.volume = 0; el.muted = true; }
          });
        });
      } catch (e) { }
    }, 1000);
    page._muteInterval = muteInterval;

    console.log('Setting up audio capture...');
    if (!BOT_HEADLESS) console.log('[Bot] If prompted: Share this tab and enable "Share tab audio"');
    let setupResult = await setupAudioRecording(page);
    if (!setupResult.ok) {
      console.log('[Audio] First attempt failed, waiting for media elements (may need other participants)...');
      for (let retry = 0; retry < 3 && !setupResult.ok; retry++) {
        await page.waitForTimeout(3000);
        setupResult = await setupAudioRecording(page);
      }
    }
    if (!setupResult.ok) {
      console.error('Audio setup failed:', setupResult.error);
      const fallbackResult = await setupDisplayMediaAudio(page, 30000);
      if (fallbackResult.ok) {
        setupResult = { ok: true, method: fallbackResult.method };
        console.log('[Audio] Using getDisplayMedia');
      }
    }

    if (!setupResult.ok) {
      console.error('[CRITICAL] No audio capture method succeeded - recording will not work');
      try { await browser.close(); } catch (_) {}
      activeRecordings.delete(roomName);
      return res.status(500).json({
        success: false,
        error: 'Could not capture meeting audio. When the browser opens, click Share and select the Jitsi tab with "Share tab audio" enabled.',
        details: setupResult.error
      });
    }

    const partialPath = path.join(recordingsDir, `recording_${roomName}_partial.webm`);
    activeRecordings.set(roomName, {
      status: 'recording',
      browser,
      page,
      startTime: new Date(),
      meetingId,
      participants: Array.isArray(participants) ? participants : [],
      authToken: authToken || null,
      backendBaseUrl: backendBaseUrl || null,
      partialPath,
      flushInterval: null
    });
    await updateMeetingStatus(backendBaseUrl, meetingId || roomName, 'recording', authToken || null);
    console.log(`Recording started for ${roomName} via ${setupResult?.method || 'unknown'}`);

    // Flush partial every 1s so short meetings still get saved; also run first flush quickly
    const recForFlush = activeRecordings.get(roomName);
    if (recForFlush) {
      const doFlush = () => {
        const r = activeRecordings.get(roomName);
        if (!r || r.status !== 'recording' || !r.page) return;
        flushPartialRecording(r.page, roomName)
          .then((saved) => { if (saved && r) r.partialPath = saved; })
          .catch((e) => {
            if (isContextDestroyedError(e) && r?.flushInterval) {
              clearInterval(r.flushInterval);
              r.flushInterval = null;
            }
          });
      };
      recForFlush.flushInterval = setInterval(doFlush, 1000);
      setTimeout(doFlush, 800);
    }

    // Monitor for meeting end (every 500ms - catch quickly before page navigates)
    const monitorInterval = setInterval(async () => {
      const rec = activeRecordings.get(roomName);
      if (!rec || rec.status !== 'recording') { clearInterval(monitorInterval); return; }
      try {
        const page = rec.page;
        if (!page || (typeof page.isClosed === 'function' && page.isClosed())) {
          clearInterval(monitorInterval);
          console.log(`[${roomName}] Page closed, auto-stopping`);
          try { await flushPartialRecording(page, roomName); } catch (_) { }
          await autoStopRecording(roomName, rec);
          return;
        }
        const ended = await checkMeetingEnded(page);
        if (ended && ended.ended) {
          clearInterval(monitorInterval);
          const rec2 = activeRecordings.get(roomName);
          if (rec2 && rec2.flushInterval) {
            clearInterval(rec2.flushInterval);
            rec2.flushInterval = null;
          }
          console.log(`[${roomName}] Meeting ended: ${ended.reason}, auto-stopping`);
          if (ended.canStop) {
            try { await flushPartialRecording(page, roomName); } catch (_) { }
          }
          await autoStopRecording(roomName, rec2 || rec);
        }
      } catch (e) {
        if (isContextDestroyedError(e)) {
          clearInterval(monitorInterval);
          const rec2 = activeRecordings.get(roomName);
          if (rec2 && rec2.flushInterval) {
            clearInterval(rec2.flushInterval);
            rec2.flushInterval = null;
          }
          console.log(`[${roomName}] Page navigated (context destroyed), auto-stopping`);
          await autoStopRecording(roomName, rec2 || rec);
        } else {
          console.error('Monitor error:', e);
        }
      }
    }, 500);

    return res.json({
      success: true,
      message: 'Recording started',
      roomName,
      method: setupResult?.method || 'unknown',
      audioCapture: setupResult?.ok ? 'success' : 'failed'
    });
  } catch (error) {
    console.error('Error starting recording:', error);
    try {
      const rec = activeRecordings.get(roomName);
      if (rec && rec.browser) await rec.browser.close();
    } catch (_) { }
    activeRecordings.delete(roomName);
    await updateMeetingStatus(backendBaseUrl, meetingId || roomName, 'failed', authToken || null, { error: error?.message || String(error) });
    return res.status(500).json({ success: false, error: 'Failed to start recording', details: error?.message || String(error) });
  }
});

app.post('/api/stop-recording', async (req, res) => {
  const roomName = (req.body.roomName || req.body.room_name || '').toString().trim();
  const autoUpload = req.body.autoUpload !== undefined ? Boolean(req.body.autoUpload) : (req.body.auto_upload !== undefined ? Boolean(req.body.auto_upload) : true);
  const participants = Array.isArray(req.body.participants) ? req.body.participants : null;
  const authToken = req.body.authToken || null;
  const backendBaseUrl = req.body.backendBaseUrl || null;
  const meetingIdFromReq = req.body.meetingId || null;

  if (!roomName) return res.status(400).json({ error: 'Room name is required' });
  const recording = activeRecordings.get(roomName);
  if (!recording) {
    const latest = findLatestRecordingForRoom(roomName);
    if (latest) {
      const baseUrl = getRequestBaseUrl(req);
      const payload = { success: true, message: 'Recording already finalized', recordingUrl: `${baseUrl}/recordings/${latest.file}` };
      const minutes = loadMinutesForRoom(roomName);
      if (minutes) payload.minutes = minutes;
      return res.json(payload);
    }
    return res.status(404).json({ error: 'No active recording found' });
  }
  if (recording.status === 'joining') {
    if (recording.browser) {
      console.log(`[${roomName}] Force-stop while joining - closing browser`);
      try {
        await recording.browser.close();
      } catch (_) {}
      activeRecordings.delete(roomName);
      return res.json({ success: true, message: 'Recording cancelled (was still joining)', recordingUrl: null });
    }
    return res.status(409).json({ error: 'Bot is still joining. Please wait a few seconds and try again.' });
  }

  if (participants && participants.length) recording.participants = participants;
  if (authToken) recording.authToken = authToken;
  if (backendBaseUrl) recording.backendBaseUrl = backendBaseUrl;
  if (meetingIdFromReq) recording.meetingId = meetingIdFromReq;

  try {
    recording.status = 'stopping';
    const { browser, page, meetingId, participants, authToken, backendBaseUrl } = recording;
    let filePath = null;
    let recordingUrl = null;

    // Clear mute and flush intervals
    if (page && page._muteInterval) {
      clearInterval(page._muteInterval);
      page._muteInterval = null;
    }
    if (recording.flushInterval) {
      clearInterval(recording.flushInterval);
      recording.flushInterval = null;
    }

    if (!page || (typeof page.isClosed === 'function' && page.isClosed())) {
      try { if (browser) await browser.close(); } catch (_) { }
      activeRecordings.delete(roomName);
      await updateMeetingStatus(backendBaseUrl, meetingId || roomName, 'failed', authToken || null, { error: 'Page not active' });
      return res.status(422).json({ success: false, error: 'Recording page is no longer active.' });
    }

    let stopResult = null;
    try {
      stopResult = await page.evaluate(() => {
      return new Promise((resolve) => {
        if (!window.mediaRecorder) return resolve({ audioData: null, chunkCount: 0, error: 'MediaRecorder not initialized' });
        const chunks = Array.isArray(window.audioChunks) ? window.audioChunks : [];
        if (window.mediaRecorder.state === 'inactive') {
          const finalChunks = Array.isArray(window.audioChunks) ? window.audioChunks : [];
          if (finalChunks.length === 0) {
            if (window.audioStream) window.audioStream.getTracks().forEach(t => t.stop());
            return resolve({ audioData: null, chunkCount: 0, error: 'No audio chunks' });
          }
          const mimeType = window.mediaRecorder?.mimeType || 'audio/webm';
          const audioBlob = new Blob(finalChunks, { type: mimeType });
          const reader = new FileReader();
          reader.onloadend = () => {
            if (window.audioStream) window.audioStream.getTracks().forEach(t => t.stop());
            resolve({ audioData: reader.result, chunkCount: finalChunks.length, blobSize: audioBlob.size, mimeType });
          };
          reader.onerror = () => {
            if (window.audioStream) window.audioStream.getTracks().forEach(t => t.stop());
            resolve({ audioData: null, chunkCount: finalChunks.length, error: 'FileReader failed' });
          };
          reader.readAsDataURL(audioBlob);
          return;
        }
        let resolved = false;
        const onStop = () => {
          window.mediaRecorder.removeEventListener('stop', onStop);
          if (!resolved) {
            resolved = true;
            const finalChunks = Array.isArray(window.audioChunks) ? window.audioChunks : [];
            if (finalChunks.length === 0) {
              if (window.audioStream) window.audioStream.getTracks().forEach(t => t.stop());
              return resolve({ audioData: null, chunkCount: 0, error: 'No audio chunks' });
            }
            const mimeType = window.mediaRecorder?.mimeType || 'audio/webm';
            const audioBlob = new Blob(finalChunks, { type: mimeType });
            const reader = new FileReader();
            reader.onloadend = () => {
              if (window.audioStream) window.audioStream.getTracks().forEach(t => t.stop());
              resolve({ audioData: reader.result, chunkCount: finalChunks.length, blobSize: audioBlob.size, mimeType });
            };
            reader.onerror = () => {
              if (window.audioStream) window.audioStream.getTracks().forEach(t => t.stop());
              resolve({ audioData: null, chunkCount: finalChunks.length, error: 'FileReader failed' });
            };
            reader.readAsDataURL(audioBlob);
          }
        };
        window.mediaRecorder.addEventListener('stop', onStop);
        try { window.mediaRecorder.requestData(); window.mediaRecorder.stop(); } catch (err) {
          if (!resolved) {
            resolved = true;
            if (window.audioStream) window.audioStream.getTracks().forEach(t => t.stop());
            resolve({ audioData: null, chunkCount: 0, error: err.message });
          }
        }
        setTimeout(() => {
          if (!resolved) {
            resolved = true;
            if (window.audioStream) window.audioStream.getTracks().forEach(t => t.stop());
            resolve({ audioData: null, chunkCount: 0, error: 'Stop timeout' });
          }
        }, 3000);
      });
    });
    } catch (evalErr) {
      if (isContextDestroyedError(evalErr)) {
        console.log(`[${roomName}] Page context lost during stop - using partial backup if available`);
      } else {
        console.warn('[Stop] page.evaluate failed:', evalErr?.message);
      }
    }

    console.log('Stop result:', stopResult);
    let audioData = stopResult?.audioData;
    let usedPartialFallback = false;
    if (!audioData) {
      // MediaRecorder lost (page navigated)? Use last partial backup if available.
      const partialPath = recording.partialPath || path.join(recordingsDir, `recording_${roomName}_partial.webm`);
      if (await fs.pathExists(partialPath)) {
        const stats = await fs.stat(partialPath);
        if (stats.size > 0) {
          const fileName = `recording_${roomName}_${Date.now()}.webm`;
          filePath = path.join(recordingsDir, fileName);
          await fs.copy(partialPath, filePath);
          await fs.remove(partialPath).catch(() => {});
          usedPartialFallback = true;
          const baseUrl = getRequestBaseUrl(req);
          console.log(`[${roomName}] Call ended - saved .webm from partial (${stats.size} bytes)`);
          console.log(`[${roomName}] Converting .webm to .mp4...`);
          filePath = await ensureMp4AfterCallEnd(filePath);
          const serveFile = path.basename(filePath);
          recordingUrl = `${baseUrl}/recordings/${serveFile}`;
          console.log(`[${roomName}] Used partial backup (${stats.size} bytes) - MediaRecorder was lost`);
        }
      }
      if (!usedPartialFallback) {
        try { if (browser) await browser.close(); } catch (_) { }
        activeRecordings.delete(roomName);
        await updateMeetingStatus(backendBaseUrl, meetingId || roomName, 'failed', authToken || null, { error: stopResult?.error || 'No audio captured' });
        return res.status(422).json({ success: false, error: stopResult?.error || 'No audio captured' });
      }
    }

    if (audioData && typeof audioData === 'string' && !usedPartialFallback) {
      try {
        const comma = audioData.indexOf(',');
        if (comma === -1) throw new Error('Invalid data URL');
        const base64Data = audioData.substring(comma + 1);
        if (!base64Data || base64Data.length === 0) throw new Error('No data');
        const audioBuffer = Buffer.from(base64Data, 'base64');
        if (audioBuffer.length === 0) throw new Error('Empty buffer');
        const fileName = `recording_${roomName}_${Date.now()}.webm`;
        filePath = path.join(recordingsDir, fileName);
        await fs.writeFile(filePath, audioBuffer);
        const fileStats = await fs.stat(filePath);
        console.log(`[${roomName}] Call ended - saved .webm: ${fileName} (${fileStats.size} bytes)`);
        if (fileStats.size <= 0) {
          await fs.remove(filePath);
          filePath = null;
        } else {
          const baseUrl = getRequestBaseUrl(req);
          console.log(`[${roomName}] Converting .webm to .mp4...`);
          filePath = await ensureMp4AfterCallEnd(filePath);
          const serveFile = path.basename(filePath);
          recordingUrl = `${baseUrl}/recordings/${serveFile}`;
        }
        // Remove partial backup on successful normal stop
        const partialPath = recording.partialPath || path.join(recordingsDir, `recording_${roomName}_partial.webm`);
        await fs.remove(partialPath).catch(() => {});
      } catch (fileError) { console.error('Save error:', fileError); }
    }

    try { if (browser) await browser.close(); } catch (_) { }
    activeRecordings.delete(roomName);

    const response = { success: true, message: 'Recording stopped', recordingUrl };
    const isMp4 = filePath && path.extname(filePath).toLowerCase() === '.mp4';
    if (!isMp4 && filePath && autoUpload) {
      console.log(`[${roomName}] Skipping backend upload - conversion to mp4 failed (recording may be incomplete)`);
    }
    if (autoUpload && filePath && fs.existsSync(filePath) && isMp4) {
      console.log(`Uploading to backend for ${meetingId || roomName}...`);
      try {
        await updateMeetingStatus(backendBaseUrl, meetingId || roomName, 'processing', authToken || null);
        const uploadResult = await uploadToBackend(filePath, meetingId || roomName, roomName, Array.isArray(participants) ? participants : [], authToken || null, backendBaseUrl || null);
        response.uploaded_to_backend = uploadResult.success !== false;
        response.minutes = uploadResult.minutes || uploadResult;
        if (response.minutes && typeof response.minutes === 'object') {
          saveMinutesForRoom(roomName, response.minutes);
        }
        if (response.uploaded_to_backend) {
          await updateMeetingStatus(backendBaseUrl, meetingId || roomName, 'completed', authToken || null);
        } else {
          await updateMeetingStatus(backendBaseUrl, meetingId || roomName, 'failed', authToken || null, { error: uploadResult.error || 'Upload failed' });
        }
      } catch (uploadError) {
        console.error('Upload error:', uploadError);
        response.uploaded_to_backend = false;
        await updateMeetingStatus(backendBaseUrl, meetingId || roomName, 'failed', authToken || null, { error: uploadError?.message || String(uploadError) });
      }
    }

    if (!recordingUrl) {
      const latest = findLatestRecordingForRoom(roomName);
      if (latest) {
        const baseUrl = getRequestBaseUrl(req);
        const finalPath = latest.filePath.toLowerCase().endsWith('.webm') ? await ensureMp4AfterCallEnd(latest.filePath) : latest.filePath;
        const serveFile = path.basename(finalPath);
        return res.json({ success: true, recordingUrl: `${baseUrl}/recordings/${serveFile}` });
      }
      return res.status(422).json({ success: false, error: 'No audio captured' });
    }
    res.json(response);
  } catch (error) {
    console.error('Error stopping recording:', error);
    try { const rec = activeRecordings.get(roomName); if (rec && rec.browser) await rec.browser.close(); } catch (_) { }
    activeRecordings.delete(roomName);
    await updateMeetingStatus(backendBaseUrl, recording?.meetingId || roomName, 'failed', authToken, { error: error?.message || String(error) });
    res.status(500).json({ error: 'Failed to stop recording', details: error.message });
  }
});

app.get('/api/health', (req, res) => { res.json({ status: 'ok', activeRecordings: activeRecordings.size }); });

app.get('/api/recordings', (req, res) => {
  try {
    const baseUrl = getRequestBaseUrl(req);
    const files = fs.readdirSync(recordingsDir)
      .filter(file => file.endsWith('.webm') || file.endsWith('.mp4') || file.endsWith('.mp3') || file.endsWith('.wav') || file.endsWith('.m4a'))
      .map(file => {
        const filePath = path.join(recordingsDir, file);
        const stats = fs.statSync(filePath);
        return { fileName: file, fileUrl: `${baseUrl}/recordings/${file}`, size: stats.size, createdAt: stats.birthtime, modifiedAt: stats.mtime };
      })
      .sort((a, b) => b.createdAt - a.createdAt);
    res.json({ success: true, count: files.length, recordings: files });
  } catch (error) { res.status(500).json({ error: 'Failed to list recordings', details: error.message }); }
});

async function convertOrphanedWebmOnStartup() {
  if (!isFfmpegAvailable()) {
    console.log('[Convert] ffmpeg not found - MP4 conversion disabled. Install from https://ffmpeg.org');
    return;
  }
  try {
    const files = await fs.readdir(recordingsDir);
    const webmFiles = files.filter((f) => f.endsWith('.webm') && !f.endsWith('_partial.webm'));
    const partialFiles = files.filter((f) => f.endsWith('_partial.webm'));
    for (const f of partialFiles) {
      const partialPath = path.join(recordingsDir, f);
      const stats = await fs.stat(partialPath);
      if (stats.size > 0) {
        const roomMatch = f.match(/recording_([^_]+)_partial\.webm/);
        const roomName = roomMatch ? roomMatch[1] : 'unknown';
        const finalName = `recording_${roomName}_${Date.now()}.webm`;
        const finalPath = path.join(recordingsDir, finalName);
        await fs.copy(partialPath, finalPath);
        const mp4Path = await convertWebmToMp4(finalPath);
        if (mp4Path) console.log(`[Startup] Recovered and converted: ${path.basename(mp4Path)}`);
      }
    }
    for (const f of webmFiles) {
      const webmPath = path.join(recordingsDir, f);
      const mp4Path = webmPath.replace(/\.webm$/i, '.mp4');
      if (!(await fs.pathExists(mp4Path))) {
        const result = await convertWebmToMp4(webmPath);
        if (result) console.log(`[Startup] Converted orphaned webm: ${path.basename(result)}`);
      }
    }
  } catch (e) {
    console.warn('[Convert] Startup conversion failed:', e.message);
  }
}

app.listen(PORT, '0.0.0.0', async () => {
  console.log(`Jitsi Recording Bot server running on http://0.0.0.0:${PORT}`);
  console.log(`Backend URL: ${BACKEND_URL}`);
  console.log(`Recordings directory: ${recordingsDir}`);
  console.log(`BOT_HEADLESS: ${BOT_HEADLESS}`);
  await convertOrphanedWebmOnStartup();
});

process.on('SIGINT', async () => {
  console.log('\nShutting down...');
  for (const [roomName, recording] of activeRecordings) {
    try { await recording.browser.close(); } catch (error) { }
  }
  process.exit(0);
});
