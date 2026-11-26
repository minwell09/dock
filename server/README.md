# DeskRemote BLE — Linux Peripheral Server

A lightweight, ultra-low-latency Python BLE GATT Peripheral server for Linux (Pop!_OS / Ubuntu) built directly on **BlueZ D-Bus** (`dbus-next`), **PipeWire / PulseAudio** (`pulsectl`), `brightnessctl` / `ddcutil`, and `playerctl`.

## Features

- **Zero Wi-Fi / LAN Required**: Communicates exclusively over Bluetooth Low Energy (BLE GATT).
- **Ultra-Low Latency**: Binary 1–2 byte `write-without-response` GATT payloads for smooth real-time volume and brightness slider dragging.
- **Bi-Directional Sync**: Polls system audio, brightness, and MPRIS media metadata and sends BLE GATT notifications whenever state changes on the laptop.
- **Hybrid Brightness Support**: Uses `brightnessctl` (<5 ms latency) for laptop displays and automatically falls back to coalesced `ddcutil` (DDC/CI) for external monitors.
- **User-Session Systemd Service**: Runs as a systemd user service (preserving PipeWire/PulseAudio & MPRIS access) with a scoped BlueZ D-Bus policy.

## Quick Setup (Pop!_OS / Ubuntu)

```bash
cd server
chmod +x install.sh
./install.sh
```

Log out and back in once so `video` / `i2c` / `bluetooth` group permissions apply.

## Manual Run

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py --log-level DEBUG
```

### CLI Options

| Flag | Env Var | Default | Description |
| --- | --- | --- | --- |
| `--name` | `DESKREMOTE_NAME` | `DeskRemote` | BLE advertised device name |
| `--adapter` | `DESKREMOTE_ADAPTER` | auto | Bluetooth adapter (e.g., `hci0`) |
| `--poll-interval` | `DESKREMOTE_POLL_INTERVAL` | `0.4` | State sync interval in seconds |
| `--min-brightness` | `DESKREMOTE_MIN_BRIGHTNESS` | `1` | Minimum brightness floor (%) |
| `--log-level` | `DESKREMOTE_LOG_LEVEL` | `INFO` | `DEBUG`, `INFO`, `WARNING`, `ERROR` |

## BLE GATT Specification

**Primary Service UUID**: `7e4a0001-b5a3-f393-e0a9-e50e24dcca9e`

| Characteristic | UUID | Properties | Payload |
| --- | --- | --- | --- |
| **Volume** | `7e4a0002-b5a3-f393-e0a9-e50e24dcca9e` | Read, Write, WriteNoResp, Notify | `[volume (0..100), muted (0/1)]`. Write supports `255` as "unchanged" and `2` for mute toggle. |
| **Brightness** | `7e4a0003-b5a3-f393-e0a9-e50e24dcca9e` | Read, Write, WriteNoResp, Notify | `[brightness (0..100)]` |
| **Media Control** | `7e4a0004-b5a3-f393-e0a9-e50e24dcca9e` | Write, WriteNoResp | 1 byte: `0x01` Play/Pause, `0x02` Next, `0x03` Prev, `0x04` Stop, `0x05` Mute Toggle, `0x06` Play, `0x07` Pause |
| **Media State** | `7e4a0005-b5a3-f393-e0a9-e50e24dcca9e` | Read, Notify | Compact UTF-8 JSON: `{"s":"Playing","t":"Title","a":"Artist"}` |

## Troubleshooting

- **Check service logs**:
  ```bash
  journalctl --user -u desk-remote-ble.service -f
  ```
- **Permission denied on `org.bluez`**: Re-run `./install.sh` to install `/etc/dbus-1/system.d/com.deskremote.conf` and reload `dbus`.
- **Brightness doesn't change**: Verify `brightnessctl info` works without `sudo`. Ensure your user is in the `video` group (`groups`).
