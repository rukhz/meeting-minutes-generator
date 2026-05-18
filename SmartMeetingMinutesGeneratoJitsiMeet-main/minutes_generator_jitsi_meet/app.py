"""Unified backend launcher.

Running ``python app.py`` starts:
1) Node bot server (port 3000) from ``Smartmeetingminutesgeneratojitsimeet/server``
2) Flask modular backend (port 5000) from ``backend.app_main``

If bot server is already running, it is reused.
"""

from __future__ import annotations

import atexit
import datetime
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from backend.app_main import app, main


def _health_ok(url: str, timeout: float = 2.0) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return 200 <= response.status < 400
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def _resolve_npm_command() -> str | None:
    candidates = ["npm.cmd", "npm"] if os.name == "nt" else ["npm"]

    for candidate in candidates:
        resolved = shutil.which(candidate)
        if resolved:
            return resolved

    if os.name == "nt":
        known_windows_paths = [
            Path(r"C:\Program Files\nodejs\npm.cmd"),
            Path(r"C:\Program Files\nodejs\npm"),
            Path(r"C:\Program Files (x86)\nodejs\npm.cmd"),
            Path(r"C:\Program Files (x86)\nodejs\npm"),
            Path.home() / "AppData" / "Roaming" / "npm" / "npm.cmd",
            Path.home() / "AppData" / "Roaming" / "npm" / "npm",
            Path.home() / "AppData" / "Local" / "Programs" / "nodejs" / "npm.cmd",
            Path.home() / "AppData" / "Local" / "Programs" / "nodejs" / "npm",
        ]
        for npm_path in known_windows_paths:
            if npm_path.exists():
                return str(npm_path)
        
    return None


def _start_bot_server_if_needed() -> subprocess.Popen | None:
    if _health_ok("http://localhost:3000/api/health"):
        print("[app.py] Bot server already running on http://localhost:3000")
        return None

    project_root = Path(__file__).resolve().parent.parent
    bot_dir = project_root / "Smartmeetingminutesgeneratojitsimeet" / "server"
    if not bot_dir.exists():
        print(f"[app.py] Bot server folder not found: {bot_dir}")
        return None

    npm_cmd = _resolve_npm_command()
    if npm_cmd is None:
        print("[app.py] npm not found. Install Node.js from https://nodejs.org and ensure npm is in PATH.")
        return None
    print(f"[app.py] Using npm: {npm_cmd}")

    node_modules = bot_dir / "node_modules"
    if not node_modules.exists():
        print("[app.py] Installing bot dependencies (npm install)...")
        install_result = subprocess.run([npm_cmd, "install"], cwd=str(bot_dir), check=False)
        if install_result.returncode != 0:
            print(f"[app.py] npm install failed with exit code {install_result.returncode}")

    print("[app.py] Starting bot server on port 3000...")
    bot_env = os.environ.copy()
    npm_dir = str(Path(npm_cmd).resolve().parent)
    bot_env["PATH"] = npm_dir + os.pathsep + bot_env.get("PATH", "")
    bot_env.setdefault("BOT_HEADLESS", "false")
    bot_env.setdefault("BACKEND_URL", "http://localhost:5000/api/generate-minutes")
    log_path = bot_dir / "bot_server.log"
    log_file = open(log_path, "a", encoding="utf-8", buffering=1)
    log_file.write(f"\n--- Bot starting {datetime.datetime.now().isoformat()} ---\n")
    log_file.flush()
    # Run node server.js directly (more reliable logging than npm start)
    node_dir = Path(npm_cmd).resolve().parent
    node_exe = node_dir / ("node.exe" if os.name == "nt" else "node")
    if not node_exe.exists():
        node_exe = shutil.which("node") or "node"
    else:
        node_exe = str(node_exe)
    server_js = bot_dir / "server.js"
    bot_process = subprocess.Popen(
        [node_exe, str(server_js)],
        cwd=str(bot_dir),
        env=bot_env,
        stdout=log_file,
        stderr=subprocess.STDOUT,
    )
    bot_process.log_file = log_file

    for _ in range(20):
        if _health_ok("http://localhost:3000/api/health"):
            print("[app.py] Bot server is ready: http://localhost:3000")
            return bot_process
        exit_code = bot_process.poll()
        if exit_code is not None:
            print(f"[app.py] Bot process exited with code {exit_code}. Check logs: {log_path}")
            break
        time.sleep(0.8)
    else:
        print(f"[app.py] Bot server did not become ready in time. Check logs: {log_path}")
    return bot_process


def _register_shutdown(bot_process: subprocess.Popen | None) -> None:
    if bot_process is None:
        return

    def _cleanup() -> None:
        if bot_process.poll() is None:
            bot_process.terminate()
            try:
                bot_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                bot_process.kill()
        log_file = getattr(bot_process, "log_file", None)
        if log_file:
            log_file.close()

    atexit.register(_cleanup)


if __name__ == '__main__':
    bot_process = _start_bot_server_if_needed()
    _register_shutdown(bot_process)

    print("[app.py] Starting Flask backend on http://0.0.0.0:5000")
    print("[app.py] Health: http://localhost:5000/api/health")
    print("[app.py] Bot trigger APIs: /api/bot/start-recording and /api/bot/stop-recording")
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)

