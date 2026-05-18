@echo off
cd /d "%~dp0"
echo.
echo Starting Bot Server (npm + Node)...
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0RUN_BOT_SERVER_EVERYTHING.ps1"
pause
