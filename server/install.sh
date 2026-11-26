#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"
CURRENT_USER="$(whoami)"
DBUS_POLICY_FILE="/etc/dbus-1/system.d/com.deskremote.conf"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SYSTEMD_USER_DIR}/desk-remote-ble.service"

echo "=== DeskRemote BLE Server Installer ==="
echo "Install directory: ${SCRIPT_DIR}"
echo "Target user:       ${CURRENT_USER}"
echo ""

# 1. Install Linux system packages
echo "[1/5] Installing system dependencies (bluez, brightnessctl, playerctl, ddcutil, python3-venv)..."
sudo apt-get update -qq
sudo apt-get install -y bluez brightnessctl playerctl ddcutil python3-venv python3-pip

# 2. Configure user permissions for backlight, DDC/CI, and Bluetooth
echo "[2/5] Configuring hardware group permissions for ${CURRENT_USER}..."
for grp in video i2c bluetooth; do
  if getent group "${grp}" >/dev/null 2>&1; then
    sudo usermod -aG "${grp}" "${CURRENT_USER}"
    echo "  - Added ${CURRENT_USER} to group '${grp}'"
  fi
done

# Ensure i2c-dev kernel module is loaded for external monitor brightness (ddcutil)
if ! lsmod | grep -q '^i2c_dev'; then
  sudo modprobe i2c-dev || true
fi
if [ ! -f /etc/modules-load.d/i2c-dev.conf ]; then
  echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
fi

# 3. Install D-Bus policy so user-session daemon can register BlueZ GATT & LE Advertisements
echo "[3/5] Installing BlueZ D-Bus policy at ${DBUS_POLICY_FILE}..."
sudo tee "${DBUS_POLICY_FILE}" >/dev/null <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="${CURRENT_USER}">
    <allow send_destination="org.bluez"/>
    <allow send_interface="org.bluez.GattManager1"/>
    <allow send_interface="org.bluez.LEAdvertisingManager1"/>
    <allow send_interface="org.bluez.GattService1"/>
    <allow send_interface="org.bluez.GattCharacteristic1"/>
    <allow send_interface="org.bluez.LEAdvertisement1"/>
    <allow send_interface="org.freedesktop.DBus.ObjectManager"/>
    <allow send_interface="org.freedesktop.DBus.Properties"/>
  </policy>
</busconfig>
EOF
sudo systemctl reload dbus || true
sudo systemctl enable --now bluetooth

# 4. Create Python virtual environment and install dependencies
echo "[4/5] Setting up Python virtual environment..."
python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/pip" install --upgrade pip -q
"${VENV_DIR}/bin/pip" install -r "${SCRIPT_DIR}/requirements.txt"

# 5. Install and enable systemd user service (runs in user session for PipeWire/PulseAudio & MPRIS access)
echo "[5/5] Installing systemd user service at ${SERVICE_FILE}..."
mkdir -p "${SYSTEMD_USER_DIR}"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=DeskRemote BLE GATT Peripheral Server
After=bluetooth.target sound.target graphical-session.target

[Service]
Type=simple
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${VENV_DIR}/bin/python ${SCRIPT_DIR}/main.py
Restart=on-failure
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now desk-remote-ble.service

echo ""
echo "=== Installation Complete ==="
echo "Service status:  systemctl --user status desk-remote-ble.service"
echo "Live logs:       journalctl --user -u desk-remote-ble.service -f"
echo ""
echo "NOTE: Log out and log back in (or reboot) once so the new 'video'/'i2c'/'bluetooth'"
echo "      group memberships take effect for passwordless brightness control."
