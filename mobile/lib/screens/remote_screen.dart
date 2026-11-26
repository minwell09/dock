import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device_state.dart';
import '../services/ble_service.dart';

class RemoteScreen extends StatelessWidget {
  final BleService bleService;

  const RemoteScreen({super.key, required this.bleService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: bleService,
      builder: (context, _) {
        final state = bleService.state;
        final colorScheme = Theme.of(context).colorScheme;
        final isReconnecting =
            state.connectionStatus == BleConnectionStatus.reconnecting;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.connectedDeviceName ?? 'DeskRemote',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
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
                    Text(
                      isReconnecting ? 'Reconnecting over BLE...' : 'Connected · BLE',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Disconnect',
                onPressed: bleService.disconnect,
                icon: const Icon(Icons.bluetooth_disabled_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                children: [
                  // Dual Large Vertical Sliders: Volume (Left) & Brightness (Right)
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _VerticalControlSlider(
                            label: 'VOLUME',
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
                            onChanged: (v) => bleService.setVolume(v),
                            onChangeEnd: (v) =>
                                bleService.setVolume(v, finalCommit: true),
                            onIconTap: () {
                              HapticFeedback.mediumImpact();
                              bleService.toggleMute();
                            },
                            badgeText: state.isMuted ? 'MUTED' : '${state.volume}%',
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _VerticalControlSlider(
                            label: 'BRIGHTNESS',
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
                            onChanged: (v) => bleService.setBrightness(v),
                            onChangeEnd: (v) =>
                                bleService.setBrightness(v, finalCommit: true),
                            badgeText: '${state.brightness}%',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Media Playback Card & Transport Controls
                  _MediaControlDock(
                    state: state,
                    onPrevious: () {
                      HapticFeedback.lightImpact();
                      bleService.sendMediaCommand(MediaCommand.previous);
                    },
                    onPlayPause: () {
                      HapticFeedback.mediumImpact();
                      bleService.sendMediaCommand(MediaCommand.playPause);
                    },
                    onNext: () {
                      HapticFeedback.lightImpact();
                      bleService.sendMediaCommand(MediaCommand.next);
                    },
                    onToggleMute: () {
                      HapticFeedback.lightImpact();
                      bleService.toggleMute();
                    },
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

/// Tactile, full-height vertical pill slider designed for one-handed remote control.
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
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
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
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withOpacity(0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        // Animated Fill Level
                        FractionallySizedBox(
                          heightFactor: fraction,
                          widthFactor: 1.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: fillColor,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        // Top Percentage Readout
                        Positioned(
                          top: 22,
                          child: Text(
                            widget.badgeText,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: fraction > 0.82 && !widget.isDimmed
                                  ? Colors.black87
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                        // Bottom Interactive Icon
                        Positioned(
                          bottom: 22,
                          child: InkWell(
                            onTap: widget.onIconTap,
                            borderRadius: BorderRadius.circular(24),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Icon(
                                widget.icon,
                                size: 32,
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

class _MediaControlDock extends StatelessWidget {
  final DeviceState state;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onToggleMute;

  const _MediaControlDock({
    required this.state,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
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
                state.isPlaying
                    ? Icons.graphic_eq_rounded
                    : Icons.music_note_rounded,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.hasMediaInfo ? state.mediaTitle : 'No active media',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (state.mediaArtist.isNotEmpty)
                      Text(
                        state.mediaArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: state.isMuted ? 'Unmute' : 'Mute',
                onPressed: onToggleMute,
                icon: Icon(
                  state.isMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: state.isMuted ? colorScheme.error : colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filledTonal(
                iconSize: 28,
                padding: const EdgeInsets.all(14),
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(18),
                ),
                onPressed: onPlayPause,
                child: Icon(
                  state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 34,
                ),
              ),
              IconButton.filledTonal(
                iconSize: 28,
                padding: const EdgeInsets.all(14),
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
