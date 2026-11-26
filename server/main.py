#!/usr/bin/env python3
"""DeskRemote BLE Peripheral Server entrypoint."""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import signal
from typing import Optional, Tuple

from ble_gatt import DeskRemoteGattServer
from hardware import HardwareManager, MediaState

logger = logging.getLogger("deskremote.main")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="DeskRemote BLE GATT Peripheral Server for Linux"
    )
    parser.add_argument(
        "--name",
        default=os.environ.get("DESKREMOTE_NAME", "DeskRemote"),
        help="BLE advertised local name (default: DeskRemote)",
    )
    parser.add_argument(
        "--adapter",
        default=os.environ.get("DESKREMOTE_ADAPTER"),
        help="Bluetooth adapter name, e.g. hci0 (default: auto-detect)",
    )
    parser.add_argument(
        "--poll-interval",
        type=float,
        default=float(os.environ.get("DESKREMOTE_POLL_INTERVAL", "0.4")),
        help="State polling interval in seconds for BLE notifications (default: 0.4)",
    )
    parser.add_argument(
        "--min-brightness",
        type=int,
        default=int(os.environ.get("DESKREMOTE_MIN_BRIGHTNESS", "1")),
        help="Minimum allowed brightness percentage 0..50 (default: 1)",
    )
    parser.add_argument(
        "--log-level",
        default=os.environ.get("DESKREMOTE_LOG_LEVEL", "INFO"),
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging verbosity (default: INFO)",
    )
    return parser.parse_args()


async def state_sync_loop(
    hardware: HardwareManager,
    server: DeskRemoteGattServer,
    poll_interval: float,
    stop_event: asyncio.Event,
) -> None:
    """Poll Linux audio, brightness, and MPRIS media state and push BLE notifications on change."""
    last_audio: Optional[Tuple[int, bool]] = None
    last_brightness: Optional[int] = None
    last_media: Optional[MediaState] = None

    # Brightness polling via ddcutil is slow over I2C, so throttle it compared to brightnessctl
    brightness_tick_mod = 1 if hardware.brightness.backend == "brightnessctl" else 8
    tick = 0

    while not stop_event.is_set():
        try:
            # 1. Audio state
            if server.volume_char and server.volume_char.is_notifying:
                audio_state = await asyncio.to_thread(hardware.audio.get_state)
                if audio_state != last_audio:
                    last_audio = audio_state
                    vol, muted = audio_state
                    server.volume_char.notify_value(bytes([vol, 1 if muted else 0]))

            # 2. Brightness state
            if (
                server.brightness_char
                and server.brightness_char.is_notifying
                and tick % brightness_tick_mod == 0
            ):
                brightness = await asyncio.to_thread(hardware.brightness.get_brightness)
                if brightness != last_brightness:
                    last_brightness = brightness
                    server.brightness_char.notify_value(bytes([brightness]))

            # 3. Media state (poll every ~2 ticks to minimize subprocess overhead)
            if (
                server.media_state_char
                and server.media_state_char.is_notifying
                and tick % 2 == 0
            ):
                media_state = await asyncio.to_thread(hardware.media.get_state)
                if media_state != last_media:
                    last_media = media_state
                    server.media_state_char.notify_value(
                        media_state.to_compact_json_bytes()
                    )

            tick += 1
        except Exception as exc:
            logger.debug("State sync iteration error: %s", exc)

        try:
            await asyncio.wait_for(stop_event.wait(), timeout=poll_interval)
        except asyncio.TimeoutError:
            pass


async def run_server(args: argparse.Namespace) -> None:
    hardware = HardwareManager(min_brightness=args.min_brightness)
    server = DeskRemoteGattServer(
        hardware=hardware,
        local_name=args.name,
        adapter_name=args.adapter,
    )

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop_event.set)

    try:
        await server.start()
        logger.info(
            "DeskRemote BLE server ready (audio=PipeWire/PulseAudio, brightness=%s)",
            hardware.brightness.backend,
        )
        await state_sync_loop(hardware, server, args.poll_interval, stop_event)
    finally:
        await server.stop()
        hardware.close()


def main() -> None:
    args = parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    try:
        asyncio.run(run_server(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
