import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/device_state.dart';
import '../services/ble_service.dart';

class ScanScreen extends StatefulWidget {
  final BleService bleService;

  const ScanScreen({super.key, required this.bleService});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.bleService.adapterState == BluetoothAdapterState.on) {
        widget.bleService.startScan();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.bleService,
      builder: (context, _) {
        final ble = widget.bleService;
        final state = ble.state;
        final btOn = ble.adapterState == BluetoothAdapterState.on;
        final isBusy = state.connectionStatus == BleConnectionStatus.connecting;

        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.bluetooth_connected_rounded, size: 24),
                SizedBox(width: 10),
                Text('DeskRemote BLE'),
              ],
            ),
            actions: [
              if (btOn)
                IconButton(
                  tooltip: ble.isScanning ? 'Stop Scan' : 'Scan',
                  onPressed: isBusy
                      ? null
                      : () => ble.isScanning ? ble.stopScan() : ble.startScan(),
                  icon: ble.isScanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!btOn) _buildBluetoothOffCard(ble),
                  if (state.errorMessage != null) ...[
                    _buildErrorBanner(state.errorMessage!),
                    const SizedBox(height: 12),
                  ],
                  if (btOn && ble.lastSavedDeviceId != null) ...[
                    _buildQuickReconnectCard(ble, isBusy),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'NEARBY DESKREMOTES',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              letterSpacing: 1.2,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      if (ble.isScanning)
                        Text(
                          'Scanning...',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _buildDeviceList(context, ble, btOn, isBusy),
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: btOn
              ? FloatingActionButton.extended(
                  onPressed: isBusy
                      ? null
                      : () => ble.isScanning ? ble.stopScan() : ble.startScan(),
                  icon: Icon(
                    ble.isScanning ? Icons.stop_rounded : Icons.bluetooth_searching_rounded,
                  ),
                  label: Text(ble.isScanning ? 'Stop' : 'Scan'),
                )
              : null,
        );
      },
    );
  }

  Widget _buildBluetoothOffCard(BleService ble) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.bluetooth_disabled_rounded,
              size: 32,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bluetooth is Off',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Enable Bluetooth to discover your Linux laptop.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: ble.turnOnBluetooth,
              child: const Text('Turn On'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickReconnectCard(BleService ble, bool isBusy) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          child: Icon(
            Icons.laptop_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(ble.lastSavedDeviceName ?? 'DeskRemote'),
        subtitle: Text(
          'Last connected · ${ble.lastSavedDeviceId}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: FilledButton.tonal(
          onPressed: isBusy ? null : ble.connectToLastSavedDevice,
          child: isBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Reconnect'),
        ),
      ),
    );
  }

  Widget _buildDeviceList(
    BuildContext context,
    BleService ble,
    bool btOn,
    bool isBusy,
  ) {
    if (!btOn) {
      return const Center(
        child: Text('Waiting for Bluetooth adapter...'),
      );
    }

    if (ble.scanResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.radar_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              ble.isScanning
                  ? 'Looking for DeskRemote laptops...'
                  : 'No DeskRemote peripherals found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Make sure desk-remote-ble is running on your Linux laptop.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: ble.scanResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final result = ble.scanResults[index];
        final advName = result.advertisementData.advName;
        final platformName = result.device.platformName;
        final name = advName.isNotEmpty
            ? advName
            : (platformName.isNotEmpty ? platformName : 'DeskRemote');

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              child: Icon(
                Icons.computer_rounded,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('${result.device.remoteId.str}  ·  ${result.rssi} dBm'),
            trailing: FilledButton(
              onPressed: isBusy
                  ? null
                  : () => ble.connect(result.device, displayName: name),
              child: const Text('Connect'),
            ),
          ),
        );
      },
    );
  }
}
