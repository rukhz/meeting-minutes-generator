"""
Jitsi Meet Bot - Joins Jitsi meetings programmatically via browser automation.
Designed for the Smart Meeting Minutes Generator project.
"""

import subprocess
import threading
import time
from dataclasses import dataclass
from typing import Callable, Optional
from urllib.parse import urlencode

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait
from webdriver_manager.chrome import ChromeDriverManager


@dataclass
class BotConfig:
    """Configuration for the Jitsi bot."""
    room_name: str
    display_name: str = "MeetingBot"
    server_url: str = "https://meet.jit.si"
    start_with_audio_muted: bool = False  # False = bot can hear (for transcription)
    start_with_video_muted: bool = True   # True = no video (typical for bot)
    skip_prejoin: bool = True
    headless: bool = False  # Headless may limit audio capture


class JitsiBot:
    """A bot that joins Jitsi Meet conferences using Selenium."""

    def __init__(self, config: BotConfig):
        self.config = config
        self.driver: Optional[webdriver.Chrome] = None
        self._on_joined: Optional[Callable] = None
        self._on_left: Optional[Callable] = None
        self._poll_stop = threading.Event()

    def _is_meeting_still_active(self) -> bool:
        """Check if we're still in the meeting (vs left/disconnected)."""
        if not self.driver:
            return False
        try:
            url = self.driver.current_url.lower()
            if "close" in url or "static/close" in url:
                return False
            body = self.driver.find_element(By.TAG_NAME, "body").text.lower()
            if "thanks for" in body or "you left" in body or "left the meeting" in body:
                return False
            self.driver.find_element(
                By.CSS_SELECTOR,
                "[data-testid='meeting'], .filmstrip, #videoconference, .toolbox-content"
            )
            return True
        except Exception:
            return False

    def _build_meeting_url(self) -> str:
        """Build Jitsi Meet URL with bot configuration parameters."""
        params = {
            "config.startWithAudioMuted": str(self.config.start_with_audio_muted).lower(),
            "config.startWithVideoMuted": str(self.config.start_with_video_muted).lower(),
            "userInfo.displayName": self.config.display_name,
            "config.prejoinPageEnabled": str(not self.config.skip_prejoin).lower(),
        }
        base = f"{self.config.server_url.rstrip('/')}/{self.config.room_name}"
        return f"{base}?{urlencode(params)}"

    def _create_driver(self) -> webdriver.Chrome:
        """Create and configure Chrome WebDriver."""
        options = Options()

        if self.config.headless:
            options.add_argument("--headless=new")

        # Reduce Chromium stderr noise (PdhAddEnglishCounter, GCM, TURN, etc.)
        options.add_argument("--log-level=3")  # Only fatal
        options.add_argument("--disable-logging")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--disable-gpu-logging")
        options.add_argument("--silent-debugger-extension-api")

        # Required for WebRTC and media capture
        options.add_argument("--use-fake-ui-for-media-stream")  # Auto-accept media permissions
        options.add_argument("--use-fake-device-for-media-stream")  # Fake devices if needed
        options.add_argument("--autoplay-policy=no-user-gesture-required")
        options.add_argument("--allow-running-insecure-content")
        options.add_argument("--disable-features=VizDisplayCompositor")
        options.add_experimental_option("excludeSwitches", ["enable-automation", "enable-logging"])
        options.add_experimental_option("useAutomationExtension", False)

        service = Service(
            ChromeDriverManager().install(),
            log_output=subprocess.DEVNULL,  # Suppress chromedriver stdout/stderr
        )
        driver = webdriver.Chrome(service=service, options=options)
        driver.maximize_window()
        return driver

    def on_joined(self, callback: Callable):
        """Register callback when bot joins the meeting."""
        self._on_joined = callback

    def on_left(self, callback: Callable):
        """Register callback when bot leaves the meeting."""
        self._on_left = callback

    def join(self) -> bool:
        """Join the configured Jitsi meeting. Returns True if join initiated successfully."""
        try:
            self.driver = self._create_driver()
            url = self._build_meeting_url()

            self.driver.get(url)

            # Wait for the meeting to load (Jitsi meeting UI elements vary by version)
            wait = WebDriverWait(self.driver, 30)
            try:
                wait.until(EC.presence_of_element_located(
                    (By.CSS_SELECTOR, "[data-testid='meeting'], .filmstrip, #videoconference, .toolbox-content")
                ))
            except Exception:
                # Fallback: wait for page to settle
                time.sleep(5)

            if self._on_joined:
                self._on_joined()

            # Poll until meeting ends (user clicked hangup in Jitsi)
            self._poll_stop.clear()
            while not self._poll_stop.is_set():
                time.sleep(3)
                if not self.driver or not self._is_meeting_still_active():
                    break
            self.leave()
            return True

        except Exception as e:
            print(f"Bot join failed: {e}")
            self.leave()
            return False

    def leave(self):
        """Leave the meeting and close the browser."""
        self._poll_stop.set()
        if self.driver:
            try:
                # Try to click leave button if available
                try:
                    leave_btn = self.driver.find_element(
                        By.CSS_SELECTOR,
                        "[aria-label='Leave meeting'], [data-testid='hangup-button'], .hangup-button"
                    )
                    leave_btn.click()
                    time.sleep(1)
                except Exception:
                    pass

                self.driver.quit()
            except Exception as e:
                print(f"Error closing driver: {e}")
            finally:
                self.driver = None
                if self._on_left:
                    self._on_left()

    def is_in_meeting(self) -> bool:
        """Check if the bot is currently in a meeting."""
        return self.driver is not None
