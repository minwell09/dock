"""Hardware abstraction layer for Linux audio, display brightness, and MPRIS media."""

from __future__ import annotations

import asyncio
import json
import logging
import shutil
import subprocess
import threading
from dataclasses import dataclass
from typing import Optional, Tuple

try:
    import pulsectl
except ImportError:  # pragma: no cover - fallback to CLI if pulsectl missing
    pulsectl = None

logger = logging.getLogger("deskremote.hardware")


@dataclass(frozen=True)
class MediaState:
    """Snapshot of the active MPRIS media player."""

    status: str = "Stopped"  # Playing | Paused | Stopped
    title: str = ""
    artist: str = ""

    def to_compact_json_bytes(self, max_bytes: int = 220) -> bytes:
        """Serialize to compact UTF-8 JSON that fits safely in a single BLE MTU."""
        title = self.title[:80]
        artist = self.artist[:60]
        payload = json.dumps(
            {"s": self.status, "t": title, "a": artist},
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")

        while len(payload) > max_bytes and (len(title) > 8 or len(artist) > 8):
            title = title[:-8] if len(title) > 8 else title
            artist = artist[:-8] if len(artist) > 8 else artist
            payload = json.dumps(
                {"s": self.status, "t": title, "a": artist},
                ensure_ascii=False,
                separators=(",", ":"),
            ).encode("utf-8")

        return payload


class AudioController:
    """Low-latency PipeWire / PulseAudio volume & mute controller."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._pulse: Optional["pulsectl.Pulse"] = None
        self._pactl_bin = shutil.which("pactl")
        self._wpctl_bin = shutil.which("wpctl")

    def _get_pulse(self) -> Optional["pulsectl.Pulse"]:
        if pulsectl is None:
            return None
        if self._pulse is None:
            try:
                self._pulse = pulsectl.Pulse("deskremote-ble")
            except Exception as exc:
                logger.warning("Unable to connect to PulseAudio/PipeWire via pulsectl: %s", exc)
                self._pulse = None
        return self._pulse

    def _reset_pulse(self) -> None:
        if self._pulse is not None:
            try:
                self._pulse.close()
            except Exception:
                pass
            self._pulse = None

    def _get_default_sink(self, pulse: "pulsectl.Pulse"):
        server_info = pulse.server_info()
        default_name = getattr(server_info, "default_sink_name", None)
        if default_name:
            try:
                return pulse.get_sink_by_name(default_name)
            except Exception:
                pass
        sinks = pulse.sink_list()
        return sinks[0] if sinks else None

    def get_state(self) -> Tuple[int, bool]:
        """Return (volume_percent 0..100, is_muted)."""
        with self._lock:
            pulse = self._get_pulse()
            if pulse is not None:
                try:
                    sink = self._get_default_sink(pulse)
                    if sink is not None:
                        vol = int(round(pulse.volume_get_all_chans(sink) * 100))
                        vol = max(0, min(100, vol))
                        muted = bool(sink.mute)
                        return vol, muted
                except Exception as exc:
                    logger.debug("pulsectl get_state failed, resetting connection: %s", exc)
                    self._reset_pulse()

        return self._get_state_cli()

    def set_volume(self, percent: int) -> Tuple[int, bool]:
        """Set default sink volume (0..100) and return updated (volume, muted)."""
        percent = max(0, min(100, int(percent)))
        with self._lock:
            pulse = self._get_pulse()
            if pulse is not None:
                try:
                    sink = self._get_default_sink(pulse)
                    if sink is not None:
                        pulse.volume_set_all_chans(sink, percent / 100.0)
                        return percent, bool(sink.mute)
                except Exception as exc:
                    logger.debug("pulsectl set_volume failed, resetting connection: %s", exc)
                    self._reset_pulse()

        if self._pactl_bin:
            subprocess.run(
                [self._pactl_bin, "set-sink-volume", "@DEFAULT_SINK@", f"{percent}%"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        elif self._wpctl_bin:
            subprocess.run(
                [self._wpctl_bin, "set-volume", "@DEFAULT_AUDIO_SINK@", f"{percent}%"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        return self._get_state_cli()

    def set_mute(self, muted: bool) -> Tuple[int, bool]:
        """Set default sink mute state."""
        with self._lock:
            pulse = self._get_pulse()
            if pulse is not None:
                try:
                    sink = self._get_default_sink(pulse)
                    if sink is not None:
                        pulse.mute(sink, muted)
                        vol = int(round(pulse.volume_get_all_chans(sink) * 100))
                        return max(0, min(100, vol)), muted
                except Exception as exc:
                    logger.debug("pulsectl set_mute failed, resetting connection: %s", exc)
                    self._reset_pulse()

        if self._pactl_bin:
            subprocess.run(
                [self._pactl_bin, "set-sink-mute", "@DEFAULT_SINK@", "1" if muted else "0"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        elif self._wpctl_bin:
            subprocess.run(
                [self._wpctl_bin, "set-mute", "@DEFAULT_AUDIO_SINK@", "1" if muted else "0"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        return self._get_state_cli()

    def toggle_mute(self) -> Tuple[int, bool]:
        vol, muted = self.get_state()
        return self.set_mute(not muted)

    def _get_state_cli(self) -> Tuple[int, bool]:
        if self._pactl_bin:
            try:
                vol_out = subprocess.check_output(
                    [self._pactl_bin, "get-sink-volume", "@DEFAULT_SINK@"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=1.5,
                )
                mute_out = subprocess.check_output(
                    [self._pactl_bin, "get-sink-mute", "@DEFAULT_SINK@"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=1.5,
                )
                vol = 0
                for token in vol_out.split():
                    if token.endswith("%"):
                        vol = int(token.rstrip("%"))
                        break
                muted = "yes" in mute_out.lower()
                return max(0, min(100, vol)), muted
            except Exception as exc:
                logger.debug("pactl fallback failed: %s", exc)
        return 0, False

    def close(self) -> None:
        with self._lock:
            self._reset_pulse()


class BrightnessController:
    """Display brightness controller supporting brightnessctl (laptop) and ddcutil (external)."""

    def __init__(self, min_brightness: int = 1) -> None:
        self.min_brightness = max(0, min(50, int(min_brightness)))
        self._brightnessctl = shutil.which("brightnessctl")
        self._ddcutil = shutil.which("ddcutil")
        self._backend: str = self._detect_backend()
        self._cached_brightness: int = 50

        # Coalescing state for slower DDC/CI writes
        self._pending_ddc_value: Optional[int] = None
        self._ddc_worker_task: Optional[asyncio.Task] = None

        logger.info("Brightness backend selected: %s", self._backend)

    def _detect_backend(self) -> str:
        if self._brightnessctl:
            try:
                res = subprocess.run(
                    [self._brightnessctl, "-c", "backlight", "info"],
                    capture_output=True,
                    text=True,
                    timeout=1.5,
                )
                if res.returncode == 0 and res.stdout.strip():
                    return "brightnessctl"
            except Exception:
                pass
        if self._ddcutil:
            return "ddcutil"
        return "none"

    @property
    def backend(self) -> str:
        return self._backend

    def get_brightness(self) -> int:
        """Return current screen brightness (0..100)."""
        if self._backend == "brightnessctl" and self._brightnessctl:
            try:
                curr = int(
                    subprocess.check_output(
                        [self._brightnessctl, "-c", "backlight", "get"],
                        text=True,
                        stderr=subprocess.DEVNULL,
                        timeout=1.5,
                    ).strip()
                )
                maximum = int(
                    subprocess.check_output(
                        [self._brightnessctl, "-c", "backlight", "max"],
                        text=True,
                        stderr=subprocess.DEVNULL,
                        timeout=1.5,
                    ).strip()
                )
                if maximum > 0:
                    pct = max(0, min(100, int(round(curr * 100 / maximum))))
                    self._cached_brightness = pct
                    return pct
            except Exception as exc:
                logger.debug("brightnessctl get failed: %s", exc)

        elif self._backend == "ddcutil" and self._ddcutil:
            try:
                out = subprocess.check_output(
                    [self._ddcutil, "getvcp", "10", "--brief"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=2.5,
                )
                # Expected brief format: "VCP 10 C 65 100"
                parts = out.strip().split()
                if len(parts) >= 4:
                    pct = max(0, min(100, int(parts[3])))
                    self._cached_brightness = pct
                    return pct
            except Exception as exc:
                logger.debug("ddcutil getvcp failed: %s", exc)

        return self._cached_brightness

    def set_brightness(self, percent: int) -> int:
        """Set display brightness synchronously (fast for brightnessctl, coalesced for ddcutil)."""
        pct = max(self.min_brightness, min(100, int(percent)))
        self._cached_brightness = pct

        if self._backend == "brightnessctl" and self._brightnessctl:
            try:
                subprocess.run(
                    [self._brightnessctl, "-c", "backlight", "-q", "set", f"{pct}%"],
                    check=False,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=1.5,
                )
            except Exception as exc:
                logger.warning("brightnessctl set failed: %s", exc)
        elif self._backend == "ddcutil" and self._ddcutil:
            self._schedule_ddc_write(pct)

        return pct

    def _schedule_ddc_write(self, pct: int) -> None:
        self._pending_ddc_value = pct
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            # No running loop; execute synchronously
            self._write_ddc_sync(pct)
            return

        if self._ddc_worker_task is None or self._ddc_worker_task.done():
            self._ddc_worker_task = loop.create_task(self._ddc_worker())

    async def _ddc_worker(self) -> None:
        while self._pending_ddc_value is not None:
            target = self._pending_ddc_value
            self._pending_ddc_value = None
            await asyncio.to_thread(self._write_ddc_sync, target)

    def _write_ddc_sync(self, pct: int) -> None:
        if not self._ddcutil:
            return
        try:
            subprocess.run(
                [self._ddcutil, "setvcp", "10", str(pct), "--noverify"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=3.0,
            )
        except Exception as exc:
            logger.warning("ddcutil setvcp failed: %s", exc)


class MediaController:
    """MPRIS2 media playback controller via playerctl."""

    COMMAND_MAP = {
        0x01: "play-pause",
        0x02: "next",
        0x03: "previous",
        0x04: "stop",
        0x06: "play",
        0x07: "pause",
    }

    def __init__(self) -> None:
        self._playerctl = shutil.which("playerctl")
        if not self._playerctl:
            logger.warning("playerctl not found; media controls will be unavailable.")

    def send_command(self, cmd_code: int) -> bool:
        """Execute a media command code."""
        action = self.COMMAND_MAP.get(cmd_code)
        if not action or not self._playerctl:
            return False
        try:
            subprocess.run(
                [self._playerctl, action],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=1.5,
            )
            return True
        except Exception as exc:
            logger.debug("playerctl %s failed: %s", action, exc)
            return False

    def get_state(self) -> MediaState:
        """Query active player playback status, title, and artist."""
        if not self._playerctl:
            return MediaState()
        try:
            out = subprocess.check_output(
                [
                    self._playerctl,
                    "metadata",
                    "--format",
                    "{{status}}\x1f{{title}}\x1f{{artist}}",
                ],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=1.5,
            ).strip()
            parts = out.split("\x1f")
            status = parts[0] if len(parts) > 0 and parts[0] else "Stopped"
            title = parts[1] if len(parts) > 1 else ""
            artist = parts[2] if len(parts) > 2 else ""
            return MediaState(status=status, title=title, artist=artist)
        except Exception:
            return MediaState()


class HardwareManager:
    """Unified facade for Linux system audio, brightness, and media."""

    def __init__(self, min_brightness: int = 1) -> None:
        self.audio = AudioController()
        self.brightness = BrightnessController(min_brightness=min_brightness)
        self.media = MediaController()

    def close(self) -> None:
        self.audio.close()
