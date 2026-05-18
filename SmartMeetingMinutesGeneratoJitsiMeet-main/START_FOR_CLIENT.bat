@echo off
setlocal
cd /d "%~dp0"
echo Starting Flask backend for Smart Meeting Minutes...
powershell -ExecutionPolicy Bypass -NoExit -File "%~dp0run_flask.ps1"
endlocal
