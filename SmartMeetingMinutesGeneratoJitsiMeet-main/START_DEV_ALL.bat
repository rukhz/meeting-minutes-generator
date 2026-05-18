@echo off
setlocal
cd /d "%~dp0"
echo Starting bot server + Flask backend + Flutter app...
powershell -ExecutionPolicy Bypass -NoExit -File "%~dp0run_everything.ps1"
endlocal
