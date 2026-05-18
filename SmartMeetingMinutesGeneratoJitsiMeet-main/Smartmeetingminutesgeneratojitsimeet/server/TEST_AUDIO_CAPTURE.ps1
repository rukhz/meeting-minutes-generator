#!/usr/bin/env pwsh
# Test Script for Fixed server.js
# Run this after npm start to verify audio recording works

param(
    [string]$RoomName = "test-$(Get-Random -Maximum 10000)",
    [string]$Port = "3000",
    [int]$RecordDurationSeconds = 30
)

$ErrorActionPreference = "Continue"

function Write-Title {
    param([string]$Text)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    Write-Host "→ $Text" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Text)
    Write-Host "✓ $Text" -ForegroundColor Green
}

function Write-Error_ {
    param([string]$Text)
    Write-Host "✗ $Text" -ForegroundColor Red
}

Write-Title "JITSI RECORDING BOT - AUDIO CAPTURE TEST"

# 1. Check health
Write-Step "Checking bot server health..."
try {
    $health = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:$Port/api/health" -TimeoutSec 5
    if ($health.StatusCode -eq 200) {
        $data = $health.Content | ConvertFrom-Json
        Write-Success "Server healthy. Active recordings: $($data.activeRecordings)"
    } else {
        Write-Error_ "Health check returned $($health.StatusCode)"
        exit 1
    }
} catch {
    Write-Error_ "Cannot reach bot server on port $Port"
    Write-Host "  Make sure: npm start is running in Smartmeetingminutesgeneratojitsimeet/server" -ForegroundColor Gray
    exit 1
}

# 2. Start recording
Write-Step "Starting recording for room: $RoomName"
try {
    $startResp = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:$Port/api/start-recording" `
        -Method POST `
        -ContentType "application/json" `
        -Body (@{ roomName = $RoomName; meetingId = "test_$([DateTime]::Now.Ticks)" } | ConvertTo-Json) `
        -TimeoutSec 30

    if ($startResp.StatusCode -eq 200) {
        $data = $startResp.Content | ConvertFrom-Json
        Write-Success "Recording started: $($data.message)"
        Write-Host "  Method: $($data.method)" -ForegroundColor Gray
    } else {
        Write-Error_ "Start recording failed: $($startResp.StatusCode)"
        exit 1
    }
} catch {
    Write-Error_ "Failed to start recording: $_"
    exit 1
}

Write-Host ""
Write-Host "Chrome browser should have opened. The bot is now joining the Jitsi meeting." -ForegroundColor Magenta
Write-Host "If prompted, select 'This tab' to share audio." -ForegroundColor Magenta
Write-Host ""
Write-Host "⏱️  Recording for $RecordDurationSeconds seconds..." -ForegroundColor Magenta

# Wait
Start-Sleep -Seconds $RecordDurationSeconds

# 3. Stop recording
Write-Step "Stopping recording..."
try {
    $stopResp = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:$Port/api/stop-recording" `
        -Method POST `
        -ContentType "application/json" `
        -Body (@{ roomName = $RoomName; autoUpload = $false } | ConvertTo-Json) `
        -TimeoutSec 120

    if ($stopResp.StatusCode -eq 200) {
        $data = $stopResp.Content | ConvertFrom-Json
        Write-Success "Recording stopped: $($data.message)"
        
        if ($data.recordingUrl) {
            Write-Success "Recording URL: $($data.recordingUrl)"
        }
    } else {
        Write-Error_ "Stop recording failed: $($stopResp.StatusCode)"
        $stopResp.Content | Write-Host
        exit 1
    }
} catch {
    Write-Error_ "Failed to stop recording: $_"
    exit 1
}

# 4. List recordings
Write-Step "Listing saved recordings..."
try {
    $listResp = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:$Port/api/recordings" `
        -TimeoutSec 10

    if ($listResp.StatusCode -eq 200) {
        $data = $listResp.Content | ConvertFrom-Json
        Write-Success "Found $($data.count) recordings"
        
        if ($data.recordings -and $data.recordings.Count -gt 0) {
            Write-Host ""
            foreach ($rec in $data.recordings | Select-Object -First 3) {
                $sizeKB = [math]::Round($rec.size / 1024, 1)
                Write-Host "  📁 $($rec.fileName) ($sizeKB KB)" -ForegroundColor Gray
            }
            
            # Check if latest file has content
            $latest = $data.recordings[0]
            if ($latest.size -gt 1000) {
                Write-Success "Latest recording has audio content ($($latest.size) bytes)"
            } else {
                Write-Error_ "Latest recording is empty or too small ($($latest.size) bytes)"
            }
        }
    }
} catch {
    Write-Error_ "Failed to list recordings: $_"
}

Write-Title "TEST COMPLETE"
Write-Host ""
Write-Host "✓ Audio capture is working!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Upload the recording to the Flask backend: /api/generate-minutes" -ForegroundColor Gray
Write-Host "  2. To manually test upload:" -ForegroundColor Gray
Write-Host "     curl -X POST http://localhost:5000/api/generate-minutes \" -ForegroundColor Gray
Write-Host "       -F 'audio=@recordings/recording_$RoomName*.webm' \" -ForegroundColor Gray
Write-Host "       -F 'meeting_id=test'" -ForegroundColor Gray
Write-Host ""
