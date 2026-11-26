# DeskRemote BLE

Ultra-low-latency remote control for a **Linux laptop (Pop!_OS / Ubuntu)** from an **Android phone (Flutter)** exclusively over **Bluetooth Low Energy (BLE GATT)** — no Wi-Fi or local network required.

Control **system volume**, **mute**, **screen brightness** (built-in backlight & external DDC/CI monitors), and **media playback** (Play/Pause, Next, Previous + Now Playing metadata) with bi-directional real-time sync.

## Project Structure

```text
desk-remote-ble/
├── server/     # Python BLE GATT Peripheral Server (BlueZ D-Bus) for Linux
└── mobile/     # Flutter Android BLE Central Client
```

---

## Prerequisites

- **Linux Laptop**: Pop!_OS 22.04+ or Ubuntu 22.04+ with Bluetooth enabled (`bluez`), PipeWire or PulseAudio, and Python 3.10+.
- **Android Phone**: Android 8.0+ (API 26+) with Bluetooth LE.
- **Flutter SDK**: Flutter 3.19+ (only needed to build/install the Android app).

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
4. Create `.venv` and install Python dependencies (`dbus-next`, `pulsectl`).
5. Enable and start the `desk-remote-ble.service` systemd user service.

> **Important:** Log out and log back in (or reboot) once after running `install.sh` so the `video`/`i2c`/`bluetooth` group permissions take effect.

Check service status & live logs:

```bash
systemctl --user status desk-remote-ble.service
journalctl --user -u desk-remote-ble.service -f
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
2. Open **DeskRemote BLE** on Android and grant the requested Bluetooth permissions.
3. Tap **Scan** and select **DeskRemote** from the list.
4. Use the dual vertical sliders for **Volume** (tap the speaker icon to mute/unmute) and **Brightness**, and the bottom dock for **Previous / Play-Pause / Next**.
5. If the connection drops, the app automatically reconnects with exponential backoff, and saves your last laptop for one-tap reconnect.

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
