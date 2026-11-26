import 'package:flutter/material.dart';

import 'models/device_state.dart';
import 'screens/remote_screen.dart';
import 'screens/scan_screen.dart';
import 'services/ble_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeskRemoteApp());
}

class DeskRemoteApp extends StatefulWidget {
  const DeskRemoteApp({super.key});

  @override
  State<DeskRemoteApp> createState() => _DeskRemoteAppState();
}

class _DeskRemoteAppState extends State<DeskRemoteApp> {
  late final BleService _bleService;

  @override
  void initState() {
    super.initState();
    _bleService = BleService();
  }

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F8CFF),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'DeskRemote BLE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: const Color(0xFF0E1117),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0E1117),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: ListenableBuilder(
        listenable: _bleService,
        builder: (context, _) {
          final status = _bleService.state.connectionStatus;
          final showRemote = status == BleConnectionStatus.connected ||
              status == BleConnectionStatus.reconnecting;

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: showRemote
                ? RemoteScreen(
                    key: const ValueKey('remote'),
                    bleService: _bleService,
                  )
                : ScanScreen(
                    key: const ValueKey('scan'),
                    bleService: _bleService,
                  ),
          );
        },
      ),
    );
  }
}
