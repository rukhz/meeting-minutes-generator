# Run modular Flask backend (ASR + NLP + Minutes + Firebase)
# From minutes_generator_jitsi_meet directory:
#   .\run_backend_modular.ps1
# Ensures Flask and Flask-Cors are installed before starting.
Set-Location $PSScriptRoot
pip install -q -r requirements.txt
$env:PYTHONPATH = $PSScriptRoot
python -m backend.app_main
