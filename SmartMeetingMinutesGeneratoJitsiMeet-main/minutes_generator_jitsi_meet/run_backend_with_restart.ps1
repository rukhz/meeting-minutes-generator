# Run backend with auto-restart on crash.
# Use this if the backend sometimes crashes (e.g. during heavy Whisper transcription).
# Press Ctrl+C to stop.

Set-Location $PSScriptRoot
$venvPython = Join-Path $PSScriptRoot "venv\Scripts\python.exe"
if (Test-Path $venvPython) { $pythonCmd = $venvPython } else { $pythonCmd = "python" }

& $pythonCmd -m pip install -q -r requirements.txt
$env:PYTHONPATH = $PSScriptRoot
$restartDelay = 5

while ($true) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting backend at http://0.0.0.0:5000"
    & $pythonCmd -m backend.app_main
    $exitCode = $LASTEXITCODE
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Backend exited with code $exitCode. Restarting in ${restartDelay}s..."
    Start-Sleep -Seconds $restartDelay
}
