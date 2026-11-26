import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_shortcut.dart';
import '../models/device_state.dart';
import '../models/system_telemetry.dart';
import '../services/ble_service.dart';
import '../services/shortcut_storage.dart';

class RemoteScreen extends StatefulWidget {
  final BleService bleService;

  const RemoteScreen({super.key, required this.bleService});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  final ShortcutStorage _storage = ShortcutStorage();
  final ImagePicker _imagePicker = ImagePicker();

  List<AppShortcut> _shortcuts = [];
  bool _loadingShortcuts = true;

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  Future<void> _loadShortcuts() async {
    final loaded = await _storage.loadShortcuts();
    if (!mounted) return;
    setState(() {
      _shortcuts = loaded;
      _loadingShortcuts = false;
    });
  }

  Future<void> _launchShortcut(AppShortcut shortcut) async {
    HapticFeedback.mediumImpact();
    await widget.bleService.launchApp(shortcut.command);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Launching ${shortcut.label}...'),
          duration: const Duration(milliseconds: 1100),
          behavior: SnackBarBehavior.floating,
          width: 260,
        ),
      );
  }

  Future<void> _showShortcutDialog({AppShortcut? existing}) async {
    final isEditing = existing != null;
    final labelController = TextEditingController(text: existing?.label ?? '');
    final commandController =
        TextEditingController(text: existing?.command ?? '');
    String? tempIconPath = existing?.iconImagePath;
    bool iconChanged = false;
    bool iconCleared = false;

    const presets = <(String label, String cmd)>[
      ('Firefox', 'firefox'),
      ('VS Code', 'code'),
      ('Steam', 'steam'),
      ('Discord', 'discord'),
      ('VLC', 'vlc'),
    ];

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasValidImage = tempIconPath != null &&
                tempIconPath!.isNotEmpty &&
                File(tempIconPath!).existsSync();

            return AlertDialog(
              title: Text(isEditing ? 'Edit Shortcut' : 'Add Shortcut'),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Icon Picker Row
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: hasValidImage
                                ? Image.file(
                                    File(tempIconPath!),
                                    fit: BoxFit.cover,
                                  )
                                : Icon(
                                    _fallbackIconForCommand(
                                      commandController.text,
                                    ),
                                    size: 28,
                                    color: colorScheme.primary,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: () async {
                                    final picked =
                                        await _imagePicker.pickImage(
                                      source: ImageSource.gallery,
                                      maxWidth: 256,
                                      maxHeight: 256,
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        tempIconPath = picked.path;
                                        iconChanged = true;
                                        iconCleared = false;
                                      });
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.photo_library_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Pick Icon Image'),
                                ),
                                if (hasValidImage)
                                  TextButton(
                                    onPressed: () {
                                      setDialogState(() {
                                        tempIconPath = null;
                                        iconChanged = false;
                                        iconCleared = true;
                                      });
                                    },
                                    child: const Text('Remove'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: labelController,
                              decoration: const InputDecoration(
                                labelText: 'Label',
                                hintText: 'e.g. Firefox',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: commandController,
                              decoration: const InputDecoration(
                                labelText: 'Linux Command',
                                hintText: 'e.g. firefox',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              autocorrect: false,
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: presets.map((preset) {
                          return ActionChip(
                            label: Text(
                              preset.$2,
                              style: const TextStyle(fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setDialogState(() {
                                commandController.text = preset.$2;
                                if (labelController.text.trim().isEmpty) {
                                  labelController.text = preset.$1;
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (isEditing)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop('delete'),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop('cancel'),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (labelController.text.trim().isEmpty ||
                        commandController.text.trim().isEmpty) {
                      return;
                    }
                    Navigator.of(dialogContext).pop('save');
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    final label = labelController.text.trim();
    final command = commandController.text.trim();
    labelController.dispose();
    commandController.dispose();

    if (result == 'delete' && existing != null) {
      await _storage.deleteIconFile(existing.iconImagePath);
      final updated = _shortcuts.where((s) => s.id != existing.id).toList();
      await _storage.saveShortcuts(updated);
      if (mounted) {
        setState(() => _shortcuts = updated);
      }
      return;
    }

    if (result == 'save' && label.isNotEmpty && command.isNotEmpty) {
      final id =
          existing?.id ?? 'sc_${DateTime.now().millisecondsSinceEpoch}';
      String? finalIconPath = existing?.iconImagePath;

      if (iconCleared) {
        await _storage.deleteIconFile(existing?.iconImagePath);
        finalIconPath = null;
      } else if (iconChanged && tempIconPath != null) {
        final persisted = await _storage.persistIconImage(tempIconPath!, id);
        if (existing?.iconImagePath != null &&
            existing!.iconImagePath != persisted) {
          await _storage.deleteIconFile(existing.iconImagePath);
        }
        finalIconPath = persisted;
      }

      final nextShortcut = AppShortcut(
        id: id,
        label: label,
        command: command,
        iconImagePath: finalIconPath,
      );

      final updated = List<AppShortcut>.from(_shortcuts);
      if (isEditing) {
        final idx = updated.indexWhere((s) => s.id == existing.id);
        if (idx != -1) {
          updated[idx] = nextShortcut;
        } else {
          updated.add(nextShortcut);
        }
      } else {
        updated.add(nextShortcut);
      }

      await _storage.saveShortcuts(updated);
      if (mounted) {
        setState(() => _shortcuts = updated);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.bleService,
      builder: (context, _) {
        final state = widget.bleService.state;
        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LEFT PANE (~23%): Dual Tactile Vertical Sliders (Volume & Brightness)
                  Expanded(
                    flex: 23,
                    child: Row(
                      children: [
                        Expanded(
                          child: _VerticalControlSlider(
                            label: 'VOL',
                            value: state.volume,
                            min: 0,
                            max: 100,
                            isDimmed: state.isMuted,
                            accentColor: colorScheme.primary,
                            icon: state.isMuted || state.volume == 0
                                ? Icons.volume_off_rounded
                                : state.volume < 50
                                    ? Icons.volume_down_rounded
                                    : Icons.volume_up_rounded,
                            onChanged: (v) => widget.bleService.setVolume(v),
                            onChangeEnd: (v) => widget.bleService
                                .setVolume(v, finalCommit: true),
                            onIconTap: () {
                              HapticFeedback.mediumImpact();
                              widget.bleService.toggleMute();
                            },
                            badgeText:
                                state.isMuted ? 'MUTE' : '${state.volume}%',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _VerticalControlSlider(
                            label: 'BRI',
                            value: state.brightness,
                            min: 1,
                            max: 100,
                            isDimmed: false,
                            accentColor: Colors.amberAccent.shade200,
                            icon: state.brightness < 35
                                ? Icons.brightness_low_rounded
                                : state.brightness < 75
                                    ? Icons.brightness_medium_rounded
                                    : Icons.brightness_high_rounded,
                            onChanged: (v) =>
                                widget.bleService.setBrightness(v),
                            onChangeEnd: (v) => widget.bleService
                                .setBrightness(v, finalCommit: true),
                            badgeText: '${state.brightness}%',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // CENTER PANE (~47%): Quick App Launcher Stream-Deck Grid
                  Expanded(
                    flex: 47,
                    child: _AppLauncherDeck(
                      shortcuts: _shortcuts,
                      isLoading: _loadingShortcuts,
                      isConnected: state.isConnected,
                      onLaunch: _launchShortcut,
                      onAdd: () => _showShortcutDialog(),
                      onEdit: (shortcut) {
                        HapticFeedback.heavyImpact();
                        _showShortcutDialog(existing: shortcut);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),

                  // RIGHT PANE (~30%): Telemetry Card (Top) + Media & Connection (Bottom)
                  Expanded(
                    flex: 30,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 56,
                          child: _TelemetryCard(telemetry: state.telemetry),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          flex: 44,
                          child: _CompactMediaAndStatusCard(
                            state: state,
                            onDisconnect: widget.bleService.disconnect,
                            onPrevious: () {
                              HapticFeedback.lightImpact();
                              widget.bleService
                                  .sendMediaCommand(MediaCommand.previous);
                            },
                            onPlayPause: () {
                              HapticFeedback.mediumImpact();
                              widget.bleService
                                  .sendMediaCommand(MediaCommand.playPause);
                            },
                            onNext: () {
                              HapticFeedback.lightImpact();
                              widget.bleService
                                  .sendMediaCommand(MediaCommand.next);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

IconData _fallbackIconForCommand(String command) {
  final lower = command.trim().toLowerCase();
  if (lower.contains('firefox') ||
      lower.contains('chrome') ||
      lower.contains('brave')) {
    return Icons.public_rounded;
  }
  if (lower.contains('code') || lower.contains('idea') || lower.contains('vim')) {
    return Icons.code_rounded;
  }
  if (lower.contains('terminal') ||
      lower.contains('alacritty') ||
      lower.contains('kitty') ||
      lower.contains('wezterm')) {
    return Icons.terminal_rounded;
  }
  if (lower.contains('nautilus') ||
      lower.contains('dolphin') ||
      lower.contains('thunar') ||
      lower.contains('files')) {
    return Icons.folder_rounded;
  }
  if (lower.contains('steam') || lower.contains('lutris')) {
    return Icons.sports_esports_rounded;
  }
  if (lower.contains('discord') || lower.contains('slack')) {
    return Icons.headset_mic_rounded;
  }
  if (lower.contains('vlc') || lower.contains('mpv') || lower.contains('spotify')) {
    return Icons.play_circle_filled_rounded;
  }
  return Icons.rocket_launch_rounded;
}

/// Center Pane: Stream-Deck style Quick App Launcher Grid.
class _AppLauncherDeck extends StatelessWidget {
  final List<AppShortcut> shortcuts;
  final bool isLoading;
  final bool isConnected;
  final ValueChanged<AppShortcut> onLaunch;
  final VoidCallback onAdd;
  final ValueChanged<AppShortcut> onEdit;

  const _AppLauncherDeck({
    required this.shortcuts,
    required this.isLoading,
    required this.isConnected,
    required this.onLaunch,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.grid_view_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'QUICK LAUNCH',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                'Hold tile to edit',
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 340 ? 4 : 3;
                      return GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.96,
                        ),
                        itemCount: shortcuts.length + 1,
                        itemBuilder: (context, index) {
                          if (index == shortcuts.length) {
                            return _AddShortcutTile(onTap: onAdd);
                          }
                          final shortcut = shortcuts[index];
                          return _ShortcutTile(
                            shortcut: shortcut,
                            enabled: isConnected,
                            onTap: () => onLaunch(shortcut),
                            onLongPress: () => onEdit(shortcut),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final AppShortcut shortcut;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ShortcutTile({
    required this.shortcut,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasImage = shortcut.iconImagePath != null &&
        shortcut.iconImagePath!.isNotEmpty &&
        File(shortcut.iconImagePath!).existsSync();

    return Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.35),
            ),
          ),
          child: hasImage
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(shortcut.iconImagePath!),
                      fit: BoxFit.cover,
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0xCC0B0E14),
                          ],
                          stops: [0.45, 1.0],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                        child: Text(
                          shortcut.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            shadows: [
                              Shadow(blurRadius: 4, color: Colors.black87),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _fallbackIconForCommand(shortcut.command),
                          size: 26,
                          color: enabled
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        shortcut.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: enabled
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _AddShortcutTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddShortcutTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.4),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                size: 28,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 4),
              Text(
                'Add',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-Right Pane: Real-Time PC Hardware Telemetry Card with animated bars.
class _TelemetryCard extends StatelessWidget {
  final SystemTelemetry telemetry;

  const _TelemetryCard({required this.telemetry});

  Color _tempColor(int tempC) {
    if (tempC >= 80) return const Color(0xFFFF5A5F);
    if (tempC >= 65) return const Color(0xFFFFB74D);
    return const Color(0xFF4CD964);
  }

  Color _batteryColor(int pct, bool charging) {
    if (charging) return const Color(0xFF4CD964);
    if (pct <= 20) return const Color(0xFFFF5A5F);
    if (pct <= 40) return const Color(0xFFFFB74D);
    return const Color(0xFF38BDF8);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_heart_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'TELEMETRY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (!telemetry.hasData)
                Text(
                  'Waiting...',
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AnimatedMetricRow(
                    label: 'CPU',
                    fraction: telemetry.cpuUsage / 100.0,
                    valueText: '${telemetry.cpuUsage}%',
                    trailingBadge:
                        telemetry.cpuTemp > 0 ? '${telemetry.cpuTemp}°C' : null,
                    trailingColor: telemetry.cpuTemp > 0
                        ? _tempColor(telemetry.cpuTemp)
                        : null,
                    barColor: const Color(0xFF4F8CFF),
                  ),
                  const SizedBox(height: 8),
                  _AnimatedMetricRow(
                    label: 'RAM',
                    fraction: telemetry.ramUsage / 100.0,
                    valueText: '${telemetry.ramUsage}%',
                    trailingBadge: telemetry.ramTotalGb > 0
                        ? '${telemetry.ramUsedGb.toStringAsFixed(1)}/${telemetry.ramTotalGb.toStringAsFixed(0)}G'
                        : null,
                    trailingColor: colorScheme.onSurfaceVariant,
                    barColor: const Color(0xFFA78BFA),
                  ),
                  if (telemetry.hasGpu) ...[
                    const SizedBox(height: 8),
                    _AnimatedMetricRow(
                      label: 'GPU',
                      fraction: telemetry.gpuUsage / 100.0,
                      valueText: '${telemetry.gpuUsage}%',
                      trailingBadge: _formatGpuDetail(telemetry),
                      trailingColor: telemetry.gpuTemp > 0
                          ? _tempColor(telemetry.gpuTemp)
                          : colorScheme.onSurfaceVariant,
                      barColor: const Color(0xFF34D399),
                    ),
                  ],
                  if (telemetry.hasBattery) ...[
                    const SizedBox(height: 8),
                    _AnimatedMetricRow(
                      label: 'BAT',
                      fraction: (telemetry.batteryPercent ?? 0) / 100.0,
                      valueText: '${telemetry.batteryPercent}%',
                      trailingIcon:
                          telemetry.isCharging ? Icons.bolt_rounded : null,
                      trailingBadge: telemetry.isCharging ? 'AC' : null,
                      trailingColor: _batteryColor(
                        telemetry.batteryPercent ?? 0,
                        telemetry.isCharging,
                      ),
                      barColor: _batteryColor(
                        telemetry.batteryPercent ?? 0,
                        telemetry.isCharging,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _formatGpuDetail(SystemTelemetry t) {
    final parts = <String>[];
    if (t.gpuTemp > 0) parts.add('${t.gpuTemp}°C');
    if (t.vramUsedGb > 0.05) parts.add('${t.vramUsedGb.toStringAsFixed(1)}G');
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _AnimatedMetricRow extends StatelessWidget {
  final String label;
  final double fraction;
  final String valueText;
  final String? trailingBadge;
  final IconData? trailingIcon;
  final Color? trailingColor;
  final Color barColor;

  const _AnimatedMetricRow({
    required this.label,
    required this.fraction,
    required this.valueText,
    required this.barColor,
    this.trailingBadge,
    this.trailingIcon,
    this.trailingColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final clamped = fraction.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              valueText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (trailingIcon != null)
              Icon(
                trailingIcon,
                size: 13,
                color: trailingColor ?? colorScheme.onSurfaceVariant,
              ),
            if (trailingBadge != null)
              Text(
                trailingBadge!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: trailingColor ?? colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 7,
            color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: clamped),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, animatedValue, _) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: animatedValue,
                    heightFactor: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom-Right Pane: Compact Now Playing + Media Controls + Connection Status.
class _CompactMediaAndStatusCard extends StatelessWidget {
  final DeviceState state;
  final VoidCallback onDisconnect;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  const _CompactMediaAndStatusCard({
    required this.state,
    required this.onDisconnect,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReconnecting =
        state.connectionStatus == BleConnectionStatus.reconnecting;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.35),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connection Status Header
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isReconnecting ? Colors.amber : Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isReconnecting
                      ? 'Reconnecting...'
                      : (state.connectedDeviceName ?? 'DeskRemote'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 17,
                  tooltip: 'Disconnect / Scan',
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.bluetooth_disabled_rounded),
                ),
              ),
            ],
          ),

          // Now Playing Metadata
          Row(
            children: [
              Icon(
                state.isPlaying
                    ? Icons.graphic_eq_rounded
                    : Icons.music_note_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.hasMediaInfo ? state.mediaTitle : 'No active media',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if (state.mediaArtist.isNotEmpty)
                      Text(
                        state.mediaArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          // Media Transport Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(10),
                  minimumSize: const Size(42, 42),
                ),
                onPressed: onPlayPause,
                child: Icon(
                  state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 24,
                ),
              ),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                onPressed: onNext,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tactile, full-height vertical pill slider designed for landscape Stream-Deck control.
class _VerticalControlSlider extends StatefulWidget {
  final String label;
  final String badgeText;
  final int value;
  final int min;
  final int max;
  final bool isDimmed;
  final Color accentColor;
  final IconData icon;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;
  final VoidCallback? onIconTap;

  const _VerticalControlSlider({
    required this.label,
    required this.badgeText,
    required this.value,
    required this.min,
    required this.max,
    required this.isDimmed,
    required this.accentColor,
    required this.icon,
    required this.onChanged,
    required this.onChangeEnd,
    this.onIconTap,
  });

  @override
  State<_VerticalControlSlider> createState() => _VerticalControlSliderState();
}

class _VerticalControlSliderState extends State<_VerticalControlSlider> {
  int _lastHapticBucket = -1;

  int _positionToValue(double localY, double height) {
    final normalized = (1.0 - (localY / height)).clamp(0.0, 1.0);
    return (widget.min + normalized * (widget.max - widget.min)).round();
  }

  void _handleUpdate(double localY, double height) {
    final nextVal = _positionToValue(localY, height);
    if (nextVal != widget.value) {
      final bucket = nextVal ~/ 5;
      if (bucket != _lastHapticBucket) {
        _lastHapticBucket = bucket;
        HapticFeedback.selectionClick();
      }
      widget.onChanged(nextVal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fraction =
        ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
    final fillColor = widget.isDimmed
        ? colorScheme.onSurfaceVariant.withOpacity(0.25)
        : widget.accentColor.withOpacity(0.88);

    return Column(
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (d) =>
                    _handleUpdate(d.localPosition.dy, height),
                onVerticalDragUpdate: (d) =>
                    _handleUpdate(d.localPosition.dy, height),
                onVerticalDragEnd: (_) => widget.onChangeEnd(widget.value),
                onTapDown: (d) {
                  final val = _positionToValue(d.localPosition.dy, height);
                  HapticFeedback.selectionClick();
                  widget.onChanged(val);
                  widget.onChangeEnd(val);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color:
                          colorScheme.surfaceContainerHighest.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withOpacity(0.35),
                        width: 1.4,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        FractionallySizedBox(
                          heightFactor: fraction,
                          widthFactor: 1.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: fillColor,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          child: Text(
                            widget.badgeText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: fraction > 0.82 && !widget.isDimmed
                                  ? Colors.black87
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 10,
                          child: InkWell(
                            onTap: widget.onIconTap,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                widget.icon,
                                size: 24,
                                color: fraction > 0.14 && !widget.isDimmed
                                    ? Colors.black87
                                    : colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
