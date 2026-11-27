import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundSettings {
  static const double defaultDimOpacity = 0.45;
  static const double defaultBlurSigma = 3.0;

  final String? filePath;
  final double dimOpacity;
  final double blurSigma;

  const BackgroundSettings({
    this.filePath,
    this.dimOpacity = defaultDimOpacity,
    this.blurSigma = defaultBlurSigma,
  });

  bool get hasCustomBackground =>
      filePath != null &&
      filePath!.isNotEmpty &&
      File(filePath!).existsSync();

  BackgroundSettings copyWith({
    String? filePath,
    bool clearFilePath = false,
    double? dimOpacity,
    double? blurSigma,
  }) {
    return BackgroundSettings(
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
      dimOpacity: (dimOpacity ?? this.dimOpacity).clamp(0.0, 0.85),
      blurSigma: (blurSigma ?? this.blurSigma).clamp(0.0, 15.0),
    );
  }
}

class BackgroundStorage {
  static const _prefFilePath = 'deskremote_bg_file_path_v1';
  static const _prefDimOpacity = 'deskremote_bg_dim_opacity_v1';
  static const _prefBlurSigma = 'deskremote_bg_blur_sigma_v1';
  static const _filePrefix = 'custom_background.';

  Future<BackgroundSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final storedPath = prefs.getString(_prefFilePath);
    final dimOpacity =
        (prefs.getDouble(_prefDimOpacity) ?? BackgroundSettings.defaultDimOpacity)
            .clamp(0.0, 0.85);
    final blurSigma =
        (prefs.getDouble(_prefBlurSigma) ?? BackgroundSettings.defaultBlurSigma)
            .clamp(0.0, 15.0);

    String? validPath;
    if (storedPath != null &&
        storedPath.isNotEmpty &&
        await File(storedPath).exists()) {
      validPath = storedPath;
    }

    return BackgroundSettings(
      filePath: validPath,
      dimOpacity: dimOpacity,
      blurSigma: blurSigma,
    );
  }

  Future<void> saveSettings(BackgroundSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    if (settings.filePath == null || settings.filePath!.isEmpty) {
      await prefs.remove(_prefFilePath);
    } else {
      await prefs.setString(_prefFilePath, settings.filePath!);
    }
    await prefs.setDouble(_prefDimOpacity, settings.dimOpacity.clamp(0.0, 0.85));
    await prefs.setDouble(_prefBlurSigma, settings.blurSigma.clamp(0.0, 15.0));
  }

  /// Copies the picked image or animated GIF into app documents storage,
  /// preserving its original file extension (e.g., .gif, .png, .jpg, .webp)
  /// so animated GIFs keep all frames intact.
  Future<String> persistBackgroundFile(String sourcePath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    await _deleteExistingBackgroundFiles(docsDir);

    final ext = _extractExtension(sourcePath);
    final destPath = '${docsDir.path}/custom_background$ext';
    final sourceFile = File(sourcePath);
    final copied = await sourceFile.copy(destPath);

    // Evict any cached FileImage at this path so newly picked files render immediately.
    await FileImage(copied).evict();
    return copied.path;
  }

  Future<BackgroundSettings> resetToDefault() async {
    final docsDir = await getApplicationDocumentsDirectory();
    await _deleteExistingBackgroundFiles(docsDir);
    const defaults = BackgroundSettings();
    await saveSettings(defaults);
    return defaults;
  }

  Future<void> _deleteExistingBackgroundFiles(Directory docsDir) async {
    try {
      if (!await docsDir.exists()) return;
      await for (final entity in docsDir.list()) {
        if (entity is File) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith(_filePrefix)) {
            await FileImage(entity).evict();
            await entity.delete();
          }
        }
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
      if (ext.length <= 6 && RegExp(r'^\.[a-z0-9]+$').hasMatch(ext)) {
        return ext;
      }
    }
    return '.png';
  }
}
