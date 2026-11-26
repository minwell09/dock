import 'dart:convert';

import 'system_telemetry.dart';

enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  reconnecting,
}

class DeviceState {
  final int volume;
  final bool isMuted;
  final int brightness;
  final String mediaStatus; // Playing | Paused | Stopped
  final String mediaTitle;
  final String mediaArtist;
  final BleConnectionStatus connectionStatus;
  final String? connectedDeviceName;
  final String? connectedDeviceId;
  final String? errorMessage;
  final SystemTelemetry telemetry;

  const DeviceState({
    this.volume = 50,
    this.isMuted = false,
    this.brightness = 50,
    this.mediaStatus = 'Stopped',
    this.mediaTitle = '',
    this.mediaArtist = '',
    this.connectionStatus = BleConnectionStatus.disconnected,
    this.connectedDeviceName,
    this.connectedDeviceId,
    this.errorMessage,
    this.telemetry = const SystemTelemetry(),
  });

  bool get isConnected => connectionStatus == BleConnectionStatus.connected;

  bool get isConnectingOrReconnecting =>
      connectionStatus == BleConnectionStatus.connecting ||
      connectionStatus == BleConnectionStatus.reconnecting;

  bool get isPlaying => mediaStatus.toLowerCase() == 'playing';

  bool get hasMediaInfo => mediaTitle.isNotEmpty || mediaArtist.isNotEmpty;

  DeviceState copyWith({
    int? volume,
    bool? isMuted,
    int? brightness,
    String? mediaStatus,
    String? mediaTitle,
    String? mediaArtist,
    BleConnectionStatus? connectionStatus,
    String? connectedDeviceName,
    String? connectedDeviceId,
    String? errorMessage,
    SystemTelemetry? telemetry,
    bool clearError = false,
    bool clearDevice = false,
  }) {
    return DeviceState(
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      brightness: brightness ?? this.brightness,
      mediaStatus: mediaStatus ?? this.mediaStatus,
      mediaTitle: mediaTitle ?? this.mediaTitle,
      mediaArtist: mediaArtist ?? this.mediaArtist,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      connectedDeviceName:
          clearDevice ? null : (connectedDeviceName ?? this.connectedDeviceName),
      connectedDeviceId:
          clearDevice ? null : (connectedDeviceId ?? this.connectedDeviceId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      telemetry:
          clearDevice ? const SystemTelemetry() : (telemetry ?? this.telemetry),
    );
  }

  /// Parse compact UTF-8 JSON from Media State GATT characteristic:
  /// `{"s":"Playing","t":"Title","a":"Artist"}`
  DeviceState applyMediaJsonBytes(List<int> bytes) {
    if (bytes.isEmpty) return this;
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is Map<String, dynamic>) {
        return copyWith(
          mediaStatus: (decoded['s'] as String?) ?? 'Stopped',
          mediaTitle: (decoded['t'] as String?) ?? '',
          mediaArtist: (decoded['a'] as String?) ?? '',
        );
      }
    } catch (_) {
      // Ignore malformed notification chunks
    }
    return this;
  }
}
