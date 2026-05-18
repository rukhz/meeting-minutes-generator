# Run modular Flask backend (ASR + NLP + Minutes API) for the Flutter app.
# From a terminal: .\run_backend.ps1
# Then in the Flutter app set Backend URL to http://YOUR_PC_IP:5000

Set-Location $PSScriptRoot
$venvPython = Join-Path $PSScriptRoot "venv\Scripts\python.exe"
if (Test-Path $venvPython) {
	$pythonCmd = $venvPython
} else {
	$pythonCmd = "python"
}

& $pythonCmd -m pip install -q -r requirements.txt
$env:PYTHONPATH = $PSScriptRoot
Write-Host "Starting modular backend at http://0.0.0.0:5000"
Write-Host "Health: http://localhost:5000/api/health"
Write-Host "Use http://YOUR_PC_IP:5000 in the Flutter app (same Wi-Fi)."
& $pythonCmd -m backend.app_main
