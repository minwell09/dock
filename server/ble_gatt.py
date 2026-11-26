"""BlueZ D-Bus BLE GATT Peripheral & LE Advertisement implementation using dbus-next."""

from __future__ import annotations

import logging
from typing import Callable, Dict, List, Optional

from dbus_next import BusType, Variant
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, dbus_property, method, PropertyAccess

from hardware import HardwareManager

logger = logging.getLogger("deskremote.ble")

# Standard BlueZ D-Bus constants
BLUEZ_SERVICE_NAME = "org.bluez"
DBUS_OM_IFACE = "org.freedesktop.DBus.ObjectManager"
DBUS_PROP_IFACE = "org.freedesktop.DBus.Properties"
ADAPTER_IFACE = "org.bluez.Adapter1"
GATT_MANAGER_IFACE = "org.bluez.GattManager1"
LE_ADVERTISING_MANAGER_IFACE = "org.bluez.LEAdvertisingManager1"
GATT_SERVICE_IFACE = "org.bluez.GattService1"
GATT_CHRC_IFACE = "org.bluez.GattCharacteristic1"
LE_ADVERTISEMENT_IFACE = "org.bluez.LEAdvertisement1"

# DeskRemote Custom GATT UUIDs (must match mobile/lib/services/ble_service.dart)
SERVICE_UUID = "7e4a0001-b5a3-f393-e0a9-e50e24dcca9e"
VOLUME_CHAR_UUID = "7e4a0002-b5a3-f393-e0a9-e50e24dcca9e"
BRIGHTNESS_CHAR_UUID = "7e4a0003-b5a3-f393-e0a9-e50e24dcca9e"
MEDIA_CTRL_CHAR_UUID = "7e4a0004-b5a3-f393-e0a9-e50e24dcca9e"
MEDIA_STATE_CHAR_UUID = "7e4a0005-b5a3-f393-e0a9-e50e24dcca9e"
APP_LAUNCH_CHAR_UUID = "7e4a0006-b5a3-f393-e0a9-e50e24dcca9e"
TELEMETRY_CHAR_UUID = "7e4a0007-b5a3-f393-e0a9-e50e24dcca9e"

APP_ROOT_PATH = "/com/deskremote"
SERVICE_PATH = f"{APP_ROOT_PATH}/service0"
ADV_PATH = f"{APP_ROOT_PATH}/advertisement0"


class GattObjectManager(ServiceInterface):
    """Implements org.freedesktop.DBus.ObjectManager for BlueZ GattManager1."""

    def __init__(self) -> None:
        super().__init__(DBUS_OM_IFACE)
        self._services: List[GattService] = []

    def add_service(self, service: "GattService") -> None:
        self._services.append(service)

    @method()
    def GetManagedObjects(self) -> "a{oa{sa{sv}}}":  # noqa: N802
        response: Dict[str, Dict[str, Dict[str, Variant]]] = {}
        for service in self._services:
            response[service.path] = service.get_properties()
            for chrc in service.characteristics:
                response[chrc.path] = chrc.get_properties()
        return response


class GattService(ServiceInterface):
    """Implements org.bluez.GattService1."""

    def __init__(self, path: str, uuid: str, primary: bool = True) -> None:
        super().__init__(GATT_SERVICE_IFACE)
        self.path = path
        self._uuid = uuid
        self._primary = primary
        self.characteristics: List[GattCharacteristic] = []

    def add_characteristic(self, chrc: "GattCharacteristic") -> None:
        self.characteristics.append(chrc)

    @dbus_property(access=PropertyAccess.READ)
    def UUID(self) -> "s":  # noqa: N802
        return self._uuid

    @dbus_property(access=PropertyAccess.READ)
    def Primary(self) -> "b":  # noqa: N802
        return self._primary

    def get_properties(self) -> Dict[str, Dict[str, Variant]]:
        return {
            GATT_SERVICE_IFACE: {
                "UUID": Variant("s", self._uuid),
                "Primary": Variant("b", self._primary),
                "Characteristics": Variant("ao", [c.path for c in self.characteristics]),
            }
        }


class GattCharacteristic(ServiceInterface):
    """Implements org.bluez.GattCharacteristic1."""

    def __init__(
        self,
        path: str,
        uuid: str,
        flags: List[str],
        service_path: str,
        on_read: Optional[Callable[[], bytes]] = None,
        on_write: Optional[Callable[[bytes], None]] = None,
    ) -> None:
        super().__init__(GATT_CHRC_IFACE)
        self.path = path
        self._uuid = uuid
        self._flags = flags
        self._service_path = service_path
        self._on_read = on_read
        self._on_write = on_write
        self._notifying = False
        self._value: bytes = b""

    @property
    def is_notifying(self) -> bool:
        return self._notifying

    @dbus_property(access=PropertyAccess.READ)
    def UUID(self) -> "s":  # noqa: N802
        return self._uuid

    @dbus_property(access=PropertyAccess.READ)
    def Service(self) -> "o":  # noqa: N802
        return self._service_path

    @dbus_property(access=PropertyAccess.READ)
    def Flags(self) -> "as":  # noqa: N802
        return self._flags

    @dbus_property(access=PropertyAccess.READ)
    def Notifying(self) -> "b":  # noqa: N802
        return self._notifying

    @dbus_property(access=PropertyAccess.READ)
    def Value(self) -> "ay":  # noqa: N802
        return self._value

    def get_properties(self) -> Dict[str, Dict[str, Variant]]:
        return {
            GATT_CHRC_IFACE: {
                "Service": Variant("o", self._service_path),
                "UUID": Variant("s", self._uuid),
                "Flags": Variant("as", self._flags),
                "Descriptors": Variant("ao", []),
            }
        }

    @method()
    def ReadValue(self, options: "a{sv}") -> "ay":  # noqa: N802
        if self._on_read is not None:
            self._value = self._on_read()
        return self._value

    @method()
    def WriteValue(self, value: "ay", options: "a{sv}") -> "":  # noqa: N802
        data = bytes(value)
        self._value = data
        if self._on_write is not None:
            self._on_write(data)

    @method()
    def StartNotify(self) -> "":  # noqa: N802
        if self._notifying:
            return
        self._notifying = True
        logger.debug("Notifications enabled for %s", self._uuid)
        # Immediately push current value so newly connected client syncs cleanly
        if self._on_read is not None:
            self.notify_value(self._on_read())

    @method()
    def StopNotify(self) -> "":  # noqa: N802
        if not self._notifying:
            return
        self._notifying = False
        logger.debug("Notifications disabled for %s", self._uuid)

    def notify_value(self, data: bytes) -> None:
        """Emit PropertiesChanged(Value) if a BLE central has subscribed."""
        self._value = data
        if self._notifying:
            self.emit_properties_changed({"Value": data})


class LEAdvertisement(ServiceInterface):
    """Implements org.bluez.LEAdvertisement1 to broadcast DeskRemote over BLE."""

    def __init__(self, path: str, local_name: str, service_uuids: List[str]) -> None:
        super().__init__(LE_ADVERTISEMENT_IFACE)
        self.path = path
        self._local_name = local_name
        self._service_uuids = service_uuids

    @dbus_property(access=PropertyAccess.READ)
    def Type(self) -> "s":  # noqa: N802
        return "peripheral"

    @dbus_property(access=PropertyAccess.READ)
    def ServiceUUIDs(self) -> "as":  # noqa: N802
        return self._service_uuids

    @dbus_property(access=PropertyAccess.READ)
    def LocalName(self) -> "s":  # noqa: N802
        return self._local_name

    @dbus_property(access=PropertyAccess.READ)
    def Discoverable(self) -> "b":  # noqa: N802
        return True

    @method()
    def Release(self) -> "":  # noqa: N802
        logger.info("BLE advertisement released by BlueZ")


class DeskRemoteGattServer:
    """Manages BlueZ adapter setup, GATT application registration, and advertising."""

    def __init__(
        self,
        hardware: HardwareManager,
        local_name: str = "DeskRemote",
        adapter_name: Optional[str] = None,
    ) -> None:
        self.hardware = hardware
        self.local_name = local_name
        self.adapter_name = adapter_name

        self.bus: Optional[MessageBus] = None
        self._adapter_path: Optional[str] = None
        self._gatt_manager = None
        self._adv_manager = None

        self.volume_char: Optional[GattCharacteristic] = None
        self.brightness_char: Optional[GattCharacteristic] = None
        self.media_ctrl_char: Optional[GattCharacteristic] = None
        self.media_state_char: Optional[GattCharacteristic] = None
        self.app_launch_char: Optional[GattCharacteristic] = None
        self.telemetry_char: Optional[GattCharacteristic] = None

    async def start(self) -> None:
        """Connect to System D-Bus, export GATT hierarchy, and start BLE advertising."""
        self.bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
        self._adapter_path = await self._find_adapter()
        logger.info("Using Bluetooth adapter: %s", self._adapter_path)

        adapter_intro = await self.bus.introspect(BLUEZ_SERVICE_NAME, self._adapter_path)
        adapter_proxy = self.bus.get_proxy_object(
            BLUEZ_SERVICE_NAME, self._adapter_path, adapter_intro
        )

        # Ensure adapter is powered on
        adapter_props = adapter_proxy.get_interface(DBUS_PROP_IFACE)
        powered = await adapter_props.call_get(ADAPTER_IFACE, "Powered")
        if not powered.value:
            logger.info("Powering on Bluetooth adapter %s", self._adapter_path)
            await adapter_props.call_set(ADAPTER_IFACE, "Powered", Variant("b", True))

        self._gatt_manager = adapter_proxy.get_interface(GATT_MANAGER_IFACE)
        self._adv_manager = adapter_proxy.get_interface(LE_ADVERTISING_MANAGER_IFACE)

        # Build GATT hierarchy
        app = GattObjectManager()
        service = GattService(SERVICE_PATH, SERVICE_UUID, primary=True)

        self.volume_char = GattCharacteristic(
            path=f"{SERVICE_PATH}/char0",
            uuid=VOLUME_CHAR_UUID,
            flags=["read", "write-without-response", "write", "notify"],
            service_path=SERVICE_PATH,
            on_read=self._read_volume,
            on_write=self._write_volume,
        )
        self.brightness_char = GattCharacteristic(
            path=f"{SERVICE_PATH}/char1",
            uuid=BRIGHTNESS_CHAR_UUID,
            flags=["read", "write-without-response", "write", "notify"],
            service_path=SERVICE_PATH,
            on_read=self._read_brightness,
            on_write=self._write_brightness,
        )
        self.media_ctrl_char = GattCharacteristic(
            path=f"{SERVICE_PATH}/char2",
            uuid=MEDIA_CTRL_CHAR_UUID,
            flags=["write-without-response", "write"],
            service_path=SERVICE_PATH,
            on_write=self._write_media_ctrl,
        )
        self.media_state_char = GattCharacteristic(
            path=f"{SERVICE_PATH}/char3",
            uuid=MEDIA_STATE_CHAR_UUID,
            flags=["read", "notify"],
            service_path=SERVICE_PATH,
            on_read=self._read_media_state,
        )
        self.app_launch_char = GattCharacteristic(
            path=f"{SERVICE_PATH}/char4",
            uuid=APP_LAUNCH_CHAR_UUID,
            flags=["write-without-response", "write"],
            service_path=SERVICE_PATH,
            on_write=self._write_app_launch,
        )
        self.telemetry_char = GattCharacteristic(
            path=f"{SERVICE_PATH}/char5",
            uuid=TELEMETRY_CHAR_UUID,
            flags=["read", "notify"],
            service_path=SERVICE_PATH,
            on_read=self._read_telemetry,
        )

        for chrc in (
            self.volume_char,
            self.brightness_char,
            self.media_ctrl_char,
            self.media_state_char,
            self.app_launch_char,
            self.telemetry_char,
        ):
            service.add_characteristic(chrc)
            self.bus.export(chrc.path, chrc)

        app.add_service(service)
        self.bus.export(service.path, service)
        self.bus.export(APP_ROOT_PATH, app)

        adv = LEAdvertisement(ADV_PATH, self.local_name, [SERVICE_UUID])
        self.bus.export(ADV_PATH, adv)

        # Register GATT Application and LE Advertisement with BlueZ
        await self._gatt_manager.call_register_application(APP_ROOT_PATH, {})
        logger.info("GATT application registered (Service UUID: %s)", SERVICE_UUID)

        await self._adv_manager.call_register_advertisement(ADV_PATH, {})
        logger.info("BLE advertising started as '%s'", self.local_name)

    async def stop(self) -> None:
        """Unregister advertisement & GATT application and disconnect D-Bus."""
        if self._adv_manager is not None:
            try:
                await self._adv_manager.call_unregister_advertisement(ADV_PATH)
            except Exception as exc:
                logger.debug("Error unregistering advertisement: %s", exc)
        if self._gatt_manager is not None:
            try:
                await self._gatt_manager.call_unregister_application(APP_ROOT_PATH)
            except Exception as exc:
                logger.debug("Error unregistering GATT application: %s", exc)
        if self.bus is not None:
            self.bus.disconnect()
            self.bus = None
        logger.info("BLE GATT server stopped cleanly.")

    async def _find_adapter(self) -> str:
        assert self.bus is not None
        root_intro = await self.bus.introspect(BLUEZ_SERVICE_NAME, "/")
        root_proxy = self.bus.get_proxy_object(BLUEZ_SERVICE_NAME, "/", root_intro)
        om = root_proxy.get_interface(DBUS_OM_IFACE)
        objects = await om.call_get_managed_objects()

        for path, interfaces in objects.items():
            if GATT_MANAGER_IFACE in interfaces and LE_ADVERTISING_MANAGER_IFACE in interfaces:
                if self.adapter_name is None or path.endswith(f"/{self.adapter_name}"):
                    return path

        raise RuntimeError(
            f"No Bluetooth LE GATT-capable adapter found"
            f"{f' matching {self.adapter_name}' if self.adapter_name else ''}. "
            "Ensure bluetoothd is running and Bluetooth hardware is enabled."
        )

    # ---- Characteristic Callbacks ----

    def _read_volume(self) -> bytes:
        vol, muted = self.hardware.audio.get_state()
        return bytes([vol, 1 if muted else 0])

    def _write_volume(self, data: bytes) -> None:
        if not data:
            return
        vol_byte = data[0]
        mute_byte = data[1] if len(data) >= 2 else 255

        if vol_byte <= 100:
            self.hardware.audio.set_volume(vol_byte)

        if mute_byte == 0:
            self.hardware.audio.set_mute(False)
        elif mute_byte == 1:
            self.hardware.audio.set_mute(True)
        elif mute_byte == 2:
            self.hardware.audio.toggle_mute()

        # Notify back authoritative state if mute changed
        if mute_byte in (0, 1, 2) and self.volume_char is not None:
            self.volume_char.notify_value(self._read_volume())

    def _read_brightness(self) -> bytes:
        pct = self.hardware.brightness.get_brightness()
        return bytes([pct])

    def _write_brightness(self, data: bytes) -> None:
        if not data:
            return
        self.hardware.brightness.set_brightness(data[0])

    def _write_media_ctrl(self, data: bytes) -> None:
        if not data:
            return
        cmd = data[0]
        if cmd == 0x05:
            vol, muted = self.hardware.audio.toggle_mute()
            if self.volume_char is not None:
                self.volume_char.notify_value(bytes([vol, 1 if muted else 0]))
            return

        self.hardware.media.send_command(cmd)

    def _read_media_state(self) -> bytes:
        return self.hardware.media.get_state().to_compact_json_bytes()

    def _write_app_launch(self, data: bytes) -> None:
        if not data:
            return
        if len(data) > 128:
            logger.warning("Ignoring oversized app launch payload (%d bytes)", len(data))
            return
        try:
            command = data.decode("utf-8", errors="ignore").replace("\x00", "").strip()
        except Exception as exc:
            logger.warning("Failed to decode app launch payload: %s", exc)
            return
        if command:
            self.hardware.launch_app(command)

    def _read_telemetry(self) -> bytes:
        return self.hardware.get_system_telemetry()
