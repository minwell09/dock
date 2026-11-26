import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_shortcut.dart';

class ShortcutStorage {
  static const _prefKey = 'deskremote_app_shortcuts_v1';
  static const _iconsFolderName = 'shortcut_icons';

  static const List<AppShortcut> defaultShortcuts = [
    AppShortcut(
      id: 'default_firefox',
      label: 'Firefox',
      command: 'firefox',
    ),
    AppShortcut(
      id: 'default_vscode',
      label: 'VS Code',
      command: 'code',
    ),
    AppShortcut(
      id: 'default_terminal',
      label: 'Terminal',
      command: 'gnome-terminal',
    ),
    AppShortcut(
      id: 'default_files',
      label: 'Files',
      command: 'nautilus',
    ),
  ];

  Future<List<AppShortcut>> loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) {
      await saveShortcuts(defaultShortcuts);
      return List<AppShortcut>.from(defaultShortcuts);
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(AppShortcut.fromJson)
            .where((s) => s.id.isNotEmpty && s.command.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Fall back to defaults if stored JSON is corrupted
    }

    await saveShortcuts(defaultShortcuts);
    return List<AppShortcut>.from(defaultShortcuts);
  }

  Future<void> saveShortcuts(List<AppShortcut> shortcuts) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(shortcuts.map((s) => s.toJson()).toList());
    await prefs.setString(_prefKey, encoded);
  }

  /// Copy a gallery image into app documents storage so it persists across restarts.
  Future<String> persistIconImage(String sourcePath, String shortcutId) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final iconsDir = Directory('${docsDir.path}/$_iconsFolderName');
    if (!await iconsDir.exists()) {
      await iconsDir.create(recursive: true);
    }

    final sourceFile = File(sourcePath);
    final ext = _extractExtension(sourcePath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = '${iconsDir.path}/icon_${shortcutId}_$timestamp$ext';
    final copied = await sourceFile.copy(destPath);
    return copied.path;
  }

  Future<void> deleteIconFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      if (!path.contains(_iconsFolderName)) return;
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }

  String _extractExtension(String filePath) {
    final dotIndex = filePath.lastIndexOf('.');
    final slashIndex = filePath.lastIndexOf(Platform.pathSeparator);
    if (dotIndex > slashIndex && dotIndex != -1) {
      final ext = filePath.substring(dotIndex).toLowerCase();
      if (ext.length <= 6) {
        return ext;
      }
    }
    return '.png';
  }
}
