import 'dart:typed_data';

class SystemTelemetry {
  final int cpuUsage; // 0..100 %
  final int cpuTemp; // 0..150 °C (0 if unavailable)
  final int ramUsage; // 0..100 %
  final double ramUsedGb;
  final double ramTotalGb;
  final int gpuUsage; // 0..100 % (255 if no discrete GPU)
  final int gpuTemp; // 0..150 °C (0 if unavailable)
  final double vramUsedGb;
  final int? batteryPercent; // 0..100 %, null if unavailable
  final bool isCharging;
  final bool hasData;

  const SystemTelemetry({
    this.cpuUsage = 0,
    this.cpuTemp = 0,
    this.ramUsage = 0,
    this.ramUsedGb = 0.0,
    this.ramTotalGb = 0.0,
    this.gpuUsage = 255,
    this.gpuTemp = 0,
    this.vramUsedGb = 0.0,
    this.batteryPercent,
    this.isCharging = false,
    this.hasData = false,
  });

  bool get hasGpu => gpuUsage != 255 && gpuUsage <= 100;

  bool get hasBattery => batteryPercent != null;

  /// Parse the 12-byte little-endian binary telemetry struct (`<BBBHHBBHB`):
  /// - Byte 0 (uint8): cpu_usage (0..100)
  /// - Byte 1 (uint8): cpu_temp (0..150 °C, 0 if unavailable)
  /// - Byte 2 (uint8): ram_usage (0..100)
  /// - Byte 3-4 (uint16 LE): ram_used_mb
  /// - Byte 5-6 (uint16 LE): ram_total_mb
  /// - Byte 7 (uint8): gpu_usage (0..100, 255 if absent)
  /// - Byte 8 (uint8): gpu_temp (0..150 °C, 0 if unavailable)
  /// - Byte 9-10 (uint16 LE): vram_used_mb
  /// - Byte 11 (uint8): battery_percent (0..100, bit 7 = charging, 255 if unavailable)
  static SystemTelemetry? fromBytes(List<int> bytes) {
    if (bytes.length < 12) return null;

    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final cpuUsage = data.getUint8(0).clamp(0, 100);
    final cpuTemp = data.getUint8(1).clamp(0, 150);
    final ramUsage = data.getUint8(2).clamp(0, 100);
    final ramUsedMb = data.getUint16(3, Endian.little);
    final ramTotalMb = data.getUint16(5, Endian.little);
    final gpuUsage = data.getUint8(7);
    final gpuTemp = data.getUint8(8).clamp(0, 150);
    final vramUsedMb = data.getUint16(9, Endian.little);
    final batteryByte = data.getUint8(11);

    final bool batteryAvailable = batteryByte != 255;
    final bool isCharging = batteryAvailable && (batteryByte & 0x80) != 0;
    final int? batteryPercent =
        batteryAvailable ? (batteryByte & 0x7F).clamp(0, 100) : null;

    return SystemTelemetry(
      cpuUsage: cpuUsage,
      cpuTemp: cpuTemp,
      ramUsage: ramUsage,
      ramUsedGb: ramUsedMb / 1024.0,
      ramTotalGb: ramTotalMb / 1024.0,
      gpuUsage: gpuUsage,
      gpuTemp: gpuTemp,
      vramUsedGb: vramUsedMb / 1024.0,
      batteryPercent: batteryPercent,
      isCharging: isCharging,
      hasData: true,
    );
  }
}
