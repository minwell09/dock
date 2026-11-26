# DeskRemote BLE

Ultra-low-latency **Stream-Deck style** remote control for a **Linux laptop (Pop!_OS / Ubuntu)** from an **Android phone (Flutter)** exclusively over **Bluetooth Low Energy (BLE GATT)** — no Wi-Fi or local network required.

## Highlights

- **Landscape-Only 3-Pane Stream-Deck Dashboard**: Locked to landscape (`immersiveSticky`) for ergonomic desk-mounted control:
  - **Left Pane**: Side-by-side vertical tactile sliders for **Volume** (tap speaker icon to mute/unmute) and **Brightness** (built-in backlight & external DDC/CI monitors).
  - **Center Pane**: **Customizable Quick App Launcher** grid — create, edit, and delete app shortcut tiles with custom labels, custom icons picked from your phone's gallery, and target Linux commands (`firefox`, `code`, `steam`, `discord`, `vlc`, etc.). Long-press any tile to edit or delete.
  - **Right Pane**: **Real-Time PC Hardware Telemetry** (animated CPU load & temp, RAM usage/GB, GPU load/temp/VRAM, and Battery/AC status streamed every `1.5s`) paired with a compact **Now Playing + Media Transport** card (`Prev`, `Play/Pause`, `Next`) and BLE connection status.
- **Bi-Directional Real-Time Sync**: Changes made on the laptop (volume keys, brightness keys, media player) sync back to the phone automatically.
- **Auto-Reconnect**: Saves your last connected laptop and reconnects automatically with exponential backoff if the BLE link drops.

## Project Structure

```text
desk-remote-ble/
├── server/     # Python BLE GATT Peripheral Server (BlueZ D-Bus + psutil) for Linux
└── mobile/     # Flutter Android BLE Central Client (Landscape Stream-Deck UI)
```

---

## Prerequisites

- **Linux Laptop**: Pop!_OS 22.04+ or Ubuntu 22.04+ with Bluetooth enabled (`bluez`), PipeWire or PulseAudio, and Python 3.10+.
- **Android Phone**: Android 8.0+ (API 26+) with Bluetooth LE.
- **Flutter SDK**: Flutter 3.19+ (only needed to build the Android app locally; GitHub Actions also builds release APKs automatically).

---

## 1. Run the Linux Server (`server/`)

### Option A — Automated Setup + Systemd Service (Recommended)

```bash
git clone https://github.com/minwell09/dock.git
cd dock/server
chmod +x install.sh
./install.sh
```

`install.sh` will:
1. Install `bluez`, `brightnessctl`, `playerctl`, `ddcutil`, and `python3-venv`.
2. Add your user to the `video`, `i2c`, and `bluetooth` groups.
3. Install the BlueZ D-Bus policy (`/etc/dbus-1/system.d/com.deskremote.conf`).
4. Create `.venv` and install Python dependencies (`dbus-next`, `pulsectl`, `psutil`).
5. Enable and start the `desk-remote-ble.service` systemd user service.

> **Important:** Log out and log back in (or reboot) once after running `install.sh` so the `video`/`i2c`/`bluetooth` group permissions take effect.

Check service status & live logs:

```bash
systemctl --user status desk-remote-ble.service
journalctl --user -u desk-remote-ble.service -f
```

### Updating an Existing Installation

```bash
cd dock
git pull
server/.venv/bin/pip install -r server/requirements.txt
systemctl --user restart desk-remote-ble.service
```

### Option B — Manual Run (Foreground / Debug)

```bash
cd dock/server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py --log-level DEBUG
```

Optional flags:

```bash
python main.py --name "DeskRemote" --adapter hci0 --min-brightness 1 --poll-interval 0.4
```

---

## 2. Build & Run the Android App (`mobile/`)

Connect your Android phone via USB (with USB Debugging enabled), then run:

```bash
cd dock/mobile

# Generate Android Gradle wrapper files (preserves AndroidManifest.xml and lib/)
flutter create --platforms=android .

# Install Flutter dependencies
flutter pub get

# Run directly on your connected Android device
flutter run
```

To build a release APK to sideload onto your phone:

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## 3. Connect & Use

1. Ensure Bluetooth is turned on on both your Linux laptop and Android phone (no manual OS pairing required).
2. Open **DeskRemote BLE** on Android (automatically launches in landscape) and grant the requested Bluetooth permissions.
3. Tap **Scan** and select **DeskRemote** from the list.
4. Control **Volume** & **Brightness** on the left, tap any **Quick Launch** tile in the center (or tap **+** to add shortcuts with custom gallery icons, long-press to edit/delete), and monitor **CPU / RAM / GPU / Battery** telemetry + **Media** controls on the right.

---

## BLE GATT Protocol Summary

Primary Service UUID: `7e4a0001-b5a3-f393-e0a9-e50e24dcca9e`

| Characteristic | UUID | Properties | Payload |
| --- | --- | --- | --- |
| **Volume** | `...0002` | Read, Write, WriteNoResp, Notify | `[volume (0..100), muted (0/1)]` |
| **Brightness** | `...0003` | Read, Write, WriteNoResp, Notify | `[brightness (0..100)]` |
| **Media Control** | `...0004` | Write, WriteNoResp | 1-byte command (`0x01` Play/Pause, `0x02` Next, `0x03` Prev, `0x04` Stop, `0x05` Mute Toggle) |
| **Media State** | `...0005` | Read, Notify | Compact UTF-8 JSON: `{"s":"Playing","t":"Title","a":"Artist"}` |
| **App Launch** | `...0006` | Write, WriteNoResp | UTF-8 Linux command string (max 128 bytes, e.g. `"firefox"`, `"code"`) |
| **System Telemetry** | `...0007` | Read, Notify | 12-byte little-endian struct (`<BBBHHBBHB`), pushed every `1.5s` |

See [server/README.md](server/README.md) for the complete byte-level telemetry specification.

---

## Troubleshooting

- **Laptop not showing up in Scan**:
  - Verify the server is running: `systemctl --user status desk-remote-ble.service`
  - Verify Bluetooth is powered on: `bluetoothctl show | grep Powered`
- **Permission denied on `org.bluez`**:
  - Re-run `./install.sh` to install `/etc/dbus-1/system.d/com.deskremote.conf` and reload `dbus`.
- **Brightness slider doesn't change screen brightness**:
  - Test `brightnessctl set 50%` (laptop screen) or `ddcutil setvcp 10 50` (external monitor) in a terminal. Ensure you logged out/in after adding your user to `video` / `i2c`.
- **Media controls don't respond**:
  - Ensure a media player supporting MPRIS2 (Spotify, Chrome, Firefox, VLC, etc.) is open and test with `playerctl play-pause`.
- **App shortcut doesn't launch on Linux**:
  - Verify the executable exists on your `PATH` (e.g., `which firefox`) and check `journalctl --user -u desk-remote-ble.service -f` for launch logs.
- **GPU stats not shown in Telemetry**:
  - NVIDIA GPUs require `nvidia-smi`; AMD/Intel GPUs fall back to `/sys/class/drm/card*/device/gpu_busy_percent`. If no discrete GPU is detected, the GPU row is automatically hidden.
