import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_state.dart';
import '../models/system_telemetry.dart';

/// Custom DeskRemote BLE GATT UUIDs (must match server/ble_gatt.py).
class DeskRemoteUuids {
  static final Guid service = Guid('7e4a0001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid volumeChar = Guid('7e4a0002-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid brightnessChar = Guid('7e4a0003-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid mediaCtrlChar = Guid('7e4a0004-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid mediaStateChar = Guid('7e4a0005-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid appLaunchChar = Guid('7e4a0006-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid telemetryChar = Guid('7e4a0007-b5a3-f393-e0a9-e50e24dcca9e');
}

/// Media control single-byte command codes.
class MediaCommand {
  static const int playPause = 0x01;
  static const int next = 0x02;
  static const int previous = 0x03;
  static const int stop = 0x04;
  static const int toggleMute = 0x05;
  static const int play = 0x06;
  static const int pause = 0x07;
}

/// Coalesced, throttled BLE writer for ultra-low-latency real-time sliders.
///
/// Sends at most one `write-without-response` packet every [minInterval],
/// never dropping the final value when the user lifts their finger.
class _ThrottledByteWriter {
  final Duration minInterval;
  final Future<void> Function(List<int> payload) onWrite;

  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTouchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<int>? _pendingPayload;
  Timer? _flushTimer;
  bool _inFlight = false;

  _ThrottledByteWriter({
    required this.minInterval,
    required this.onWrite,
  });

  /// Returns true while the user is actively dragging or within the settle window,
  /// preventing stale server notifications from causing slider jitter.
  bool get isSuppressingNotifications =>
      DateTime.now().difference(_lastTouchedAt) < const Duration(milliseconds: 400);

  void enqueue(List<int> payload, {bool forceImmediate = false}) {
    _lastTouchedAt = DateTime.now();
    _pendingPayload = payload;

    if (forceImmediate) {
      _flushTimer?.cancel();
      _flushTimer = null;
      _drain();
      return;
    }

    final elapsed = DateTime.now().difference(_lastSentAt);
    if (!_inFlight && elapsed >= minInterval) {
      _drain();
    } else if (_flushTimer == null || !_flushTimer!.isActive) {
      final delay = elapsed >= minInterval ? Duration.zero : (minInterval - elapsed);
      _flushTimer = Timer(delay, _drain);
    }
  }

  Future<void> _drain() async {
    if (_inFlight || _pendingPayload == null) return;
    final payload = _pendingPayload!;
    _pendingPayload = null;
    _inFlight = true;
    _lastSentAt = DateTime.now();

    try {
      await onWrite(payload);
    } catch (_) {
      // Errors are logged by caller
    } finally {
      _inFlight = false;
      if (_pendingPayload != null) {
        _flushTimer?.cancel();
        _flushTimer = Timer(minInterval, _drain);
      }
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _pendingPayload = null;
  }
}

class BleService extends ChangeNotifier {
  static const _prefLastDeviceId = 'deskremote_last_device_id';
  static const _prefLastDeviceName = 'deskremote_last_device_name';

  DeviceState _state = const DeviceState();
  DeviceState get state => _state;

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  BluetoothAdapterState get adapterState => _adapterState;

  List<ScanResult> _scanResults = [];
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  String? _lastSavedDeviceId;
  String? get lastSavedDeviceId => _lastSavedDeviceId;

  String? _lastSavedDeviceName;
  String? get lastSavedDeviceName => _lastSavedDeviceName;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _volumeChar;
  BluetoothCharacteristic? _brightnessChar;
  BluetoothCharacteristic? _mediaCtrlChar;
  BluetoothCharacteristic? _mediaStateChar;
  BluetoothCharacteristic? _appLaunchChar;
  BluetoothCharacteristic? _telemetryChar;

  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _volNotifySub;
  StreamSubscription<List<int>>? _brightNotifySub;
  StreamSubscription<List<int>>? _mediaNotifySub;
  StreamSubscription<List<int>>? _telemetryNotifySub;

  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _manualDisconnect = false;

  late final _ThrottledByteWriter _volumeWriter;
  late final _ThrottledByteWriter _brightnessWriter;

  BleService() {
    _volumeWriter = _ThrottledByteWriter(
      minInterval: const Duration(milliseconds: 25),
      onWrite: _rawWriteVolume,
    );
    _brightnessWriter = _ThrottledByteWriter(
      minInterval: const Duration(milliseconds: 30),
      onWrite: _rawWriteBrightness,
    );
    _init();
  }

  Future<void> _init() async {
    _adapterSub = FlutterBluePlus.adapterState.listen((adapter) {
      _adapterState = adapter;
      notifyListeners();
    });

    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      if (!scanning && _state.connectionStatus == BleConnectionStatus.scanning) {
        _updateState(_state.copyWith(connectionStatus: BleConnectionStatus.disconnected));
      } else {
        notifyListeners();
      }
    });

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      // Sort strongest RSSI first
      final sorted = List<ScanResult>.from(results)
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      _scanResults = sorted;
      notifyListeners();
    });

    final prefs = await SharedPreferences.getInstance();
    _lastSavedDeviceId = prefs.getString(_prefLastDeviceId);
    _lastSavedDeviceName = prefs.getString(_prefLastDeviceName);
    notifyListeners();
  }

  /// Request Android 12+ (and legacy Android) Bluetooth permissions.
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final locationGranted = statuses[Permission.locationWhenInUse]?.isGranted ?? false;

    // Android 12+ requires BLUETOOTH_SCAN & BLUETOOTH_CONNECT; Android <=11 requires location
    if ((scanGranted && connectGranted) || locationGranted) {
      return true;
    }

    _updateState(
      _state.copyWith(
        errorMessage: 'Bluetooth permissions are required to scan and connect.',
      ),
    );
    return false;
  }

  Future<void> turnOnBluetooth() async {
    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        _updateState(_state.copyWith(errorMessage: 'Unable to turn on Bluetooth: $e'));
      }
    }
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    final ok = await ensurePermissions();
    if (!ok) return;

    if (_adapterState != BluetoothAdapterState.on) {
      _updateState(_state.copyWith(errorMessage: 'Please enable Bluetooth first.'));
      return;
    }

    _scanResults = [];
    _updateState(
      _state.copyWith(
        connectionStatus: BleConnectionStatus.scanning,
        clearError: true,
      ),
    );

    try {
      await FlutterBluePlus.startScan(
        withServices: [DeskRemoteUuids.service],
        timeout: timeout,
        androidUsesFineLocation: false,
      );
    } catch (e) {
      _updateState(
        _state.copyWith(
          connectionStatus: BleConnectionStatus.disconnected,
          errorMessage: 'Scan failed: $e',
        ),
      );
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<void> connectToLastSavedDevice() async {
    if (_lastSavedDeviceId == null) return;
    final ok = await ensurePermissions();
    if (!ok) return;
    final device = BluetoothDevice.fromId(_lastSavedDeviceId!);
    await connect(device, displayName: _lastSavedDeviceName ?? 'DeskRemote');
  }

  Future<void> connect(BluetoothDevice device, {String? displayName}) async {
    await stopScan();
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;

    final name = (displayName?.isNotEmpty ?? false)
        ? displayName!
        : (device.platformName.isNotEmpty ? device.platformName : 'DeskRemote');

    _device = device;
    _updateState(
      _state.copyWith(
        connectionStatus: BleConnectionStatus.connecting,
        connectedDeviceName: name,
        connectedDeviceId: device.remoteId.str,
        clearError: true,
      ),
    );

    await _establishConnection(device, name);
  }

  Future<void> _establishConnection(BluetoothDevice device, String name) async {
    try {
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((connState) {
        if (connState == BluetoothConnectionState.disconnected && !_manualDisconnect) {
          _handleUnexpectedDisconnect();
        }
      });

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      // Request larger MTU on Android so media metadata JSON fits in 1 packet
      if (Platform.isAndroid) {
        try {
          await device.requestMtu(247);
        } catch (_) {}
      }

      final services = await device.discoverServices();
      BluetoothService? targetService;
      for (final s in services) {
        if (s.uuid == DeskRemoteUuids.service) {
          targetService = s;
          break;
        }
      }

      if (targetService == null) {
        throw Exception('DeskRemote GATT service not found on device.');
      }

      _volumeChar = null;
      _brightnessChar = null;
      _mediaCtrlChar = null;
      _mediaStateChar = null;
      _appLaunchChar = null;
      _telemetryChar = null;

      for (final c in targetService.characteristics) {
        if (c.uuid == DeskRemoteUuids.volumeChar) {
          _volumeChar = c;
        } else if (c.uuid == DeskRemoteUuids.brightnessChar) {
          _brightnessChar = c;
        } else if (c.uuid == DeskRemoteUuids.mediaCtrlChar) {
          _mediaCtrlChar = c;
        } else if (c.uuid == DeskRemoteUuids.mediaStateChar) {
          _mediaStateChar = c;
        } else if (c.uuid == DeskRemoteUuids.appLaunchChar) {
          _appLaunchChar = c;
        } else if (c.uuid == DeskRemoteUuids.telemetryChar) {
          _telemetryChar = c;
        }
      }

      await _subscribeAndSyncInitialState();

      // Persist last connected device for quick reconnect
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastDeviceId, device.remoteId.str);
      await prefs.setString(_prefLastDeviceName, name);
      _lastSavedDeviceId = device.remoteId.str;
      _lastSavedDeviceName = name;

      _reconnectAttempt = 0;
      _updateState(
        _state.copyWith(
          connectionStatus: BleConnectionStatus.connected,
          connectedDeviceName: name,
          connectedDeviceId: device.remoteId.str,
          clearError: true,
        ),
      );
    } catch (e) {
      if (_manualDisconnect) return;
      _updateState(
        _state.copyWith(
          connectionStatus: BleConnectionStatus.disconnected,
          errorMessage: 'Connection failed: $e',
        ),
      );
    }
  }

  Future<void> _subscribeAndSyncInitialState() async {
    await _cancelCharacteristicSubscriptions();

    if (_volumeChar != null) {
      try {
        final initial = await _volumeChar!.read();
        _applyVolumeBytes(initial, force: true);
      } catch (_) {}

      await _volumeChar!.setNotifyValue(true);
      _volNotifySub = _volumeChar!.onValueReceived.listen((bytes) {
        _applyVolumeBytes(bytes);
      });
    }

    if (_brightnessChar != null) {
      try {
        final initial = await _brightnessChar!.read();
        _applyBrightnessBytes(initial, force: true);
      } catch (_) {}

      await _brightnessChar!.setNotifyValue(true);
      _brightNotifySub = _brightnessChar!.onValueReceived.listen((bytes) {
        _applyBrightnessBytes(bytes);
      });
    }

    if (_mediaStateChar != null) {
      try {
        final initial = await _mediaStateChar!.read();
        _updateState(_state.applyMediaJsonBytes(initial));
      } catch (_) {}

      await _mediaStateChar!.setNotifyValue(true);
      _mediaNotifySub = _mediaStateChar!.onValueReceived.listen((bytes) {
        _updateState(_state.applyMediaJsonBytes(bytes));
      });
    }

    if (_telemetryChar != null) {
      try {
        final initial = await _telemetryChar!.read();
        _applyTelemetryBytes(initial);
      } catch (_) {}

      await _telemetryChar!.setNotifyValue(true);
      _telemetryNotifySub = _telemetryChar!.onValueReceived.listen((bytes) {
        _applyTelemetryBytes(bytes);
      });
    }
  }

  void _handleUnexpectedDisconnect() {
    if (_device == null || _manualDisconnect) return;
    _cancelCharacteristicSubscriptions();

    _reconnectAttempt++;
    final backoffSeconds = (_reconnectAttempt * 2).clamp(1, 8);
    _updateState(
      _state.copyWith(
        connectionStatus: BleConnectionStatus.reconnecting,
        errorMessage: 'Connection lost. Reconnecting in ${backoffSeconds}s...',
      ),
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () async {
      if (_manualDisconnect || _device == null) return;
      await _establishConnection(
        _device!,
        _state.connectedDeviceName ?? 'DeskRemote',
      );
    });
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    await _cancelCharacteristicSubscriptions();
    await _connSub?.cancel();
    _connSub = null;

    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
      _device = null;
    }

    _volumeChar = null;
    _brightnessChar = null;
    _mediaCtrlChar = null;
    _mediaStateChar = null;
    _appLaunchChar = null;
    _telemetryChar = null;

    _updateState(
      _state.copyWith(
        connectionStatus: BleConnectionStatus.disconnected,
        clearDevice: true,
        clearError: true,
      ),
    );
  }

  // ---- Controls (Ultra-Low-Latency GATT Writers) ----

  void setVolume(int percent, {bool finalCommit = false}) {
    final clamped = percent.clamp(0, 100);
    _updateState(_state.copyWith(volume: clamped));
    // Byte 0 = volume (0..100), Byte 1 = 255 (leave mute state unchanged)
    _volumeWriter.enqueue([clamped, 255], forceImmediate: finalCommit);
  }

  void toggleMute() {
    final nextMuted = !_state.isMuted;
    _updateState(_state.copyWith(isMuted: nextMuted));
    // Byte 0 = 255 (unchanged), Byte 1 = 0/1 explicit mute
    _volumeWriter.enqueue([255, nextMuted ? 1 : 0], forceImmediate: true);
  }

  void setBrightness(int percent, {bool finalCommit = false}) {
    final clamped = percent.clamp(1, 100);
    _updateState(_state.copyWith(brightness: clamped));
    _brightnessWriter.enqueue([clamped], forceImmediate: finalCommit);
  }

  Future<void> sendMediaCommand(int cmdCode) async {
    final char = _mediaCtrlChar;
    if (char == null || !_state.isConnected) return;
    try {
      final useNoResp = char.properties.writeWithoutResponse;
      await char.write([cmdCode], withoutResponse: useNoResp);
    } catch (e) {
      debugPrint('Media command write failed: $e');
    }
  }

  Future<void> launchApp(String command) async {
    final char = _appLaunchChar;
    final trimmed = command.trim();
    if (char == null || !_state.isConnected || trimmed.isEmpty) return;

    final payload = utf8.encode(trimmed);
    if (payload.length > 128) {
      debugPrint('App launch command exceeds 128-byte limit');
      return;
    }

    try {
      final useNoResp = char.properties.writeWithoutResponse;
      await char.write(payload, withoutResponse: useNoResp);
    } catch (e) {
      debugPrint('App launch write failed: $e');
    }
  }

  Future<void> _rawWriteVolume(List<int> payload) async {
    final char = _volumeChar;
    if (char == null || !_state.isConnected) return;
    final useNoResp = char.properties.writeWithoutResponse;
    await char.write(payload, withoutResponse: useNoResp);
  }

  Future<void> _rawWriteBrightness(List<int> payload) async {
    final char = _brightnessChar;
    if (char == null || !_state.isConnected) return;
    final useNoResp = char.properties.writeWithoutResponse;
    await char.write(payload, withoutResponse: useNoResp);
  }

  // ---- Incoming Notification Parsers ----

  void _applyVolumeBytes(List<int> bytes, {bool force = false}) {
    if (bytes.isEmpty) return;
    if (!force && _volumeWriter.isSuppressingNotifications) return;
    final vol = bytes[0].clamp(0, 100);
    final muted = bytes.length >= 2 ? bytes[1] == 1 : _state.isMuted;
    _updateState(_state.copyWith(volume: vol, isMuted: muted));
  }

  void _applyBrightnessBytes(List<int> bytes, {bool force = false}) {
    if (bytes.isEmpty) return;
    if (!force && _brightnessWriter.isSuppressingNotifications) return;
    final pct = bytes[0].clamp(0, 100);
    _updateState(_state.copyWith(brightness: pct));
  }

  void _applyTelemetryBytes(List<int> bytes) {
    final parsed = SystemTelemetry.fromBytes(bytes);
    if (parsed != null) {
      _updateState(_state.copyWith(telemetry: parsed));
    }
  }

  Future<void> _cancelCharacteristicSubscriptions() async {
    await _volNotifySub?.cancel();
    await _brightNotifySub?.cancel();
    await _mediaNotifySub?.cancel();
    await _telemetryNotifySub?.cancel();
    _volNotifySub = null;
    _brightNotifySub = null;
    _mediaNotifySub = null;
    _telemetryNotifySub = null;
  }

  void _updateState(DeviceState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _volumeWriter.dispose();
    _brightnessWriter.dispose();
    _adapterSub?.cancel();
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    _connSub?.cancel();
    _cancelCharacteristicSubscriptions();
    super.dispose();
  }
}
