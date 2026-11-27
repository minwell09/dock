import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 60fps music-reactive neon LED spectrum visualizer with peak-hold caps and glow.
class AudioLightVisualizer extends StatefulWidget {
  final bool isPlaying;
  final int volume;
  final bool isMuted;
  final int barCount;
  final double height;
  final bool segmented;
  final double opacity;

  const AudioLightVisualizer({
    super.key,
    required this.isPlaying,
    required this.volume,
    required this.isMuted,
    this.barCount = 20,
    this.height = 36,
    this.segmented = true,
    this.opacity = 1.0,
  });

  @override
  State<AudioLightVisualizer> createState() => _AudioLightVisualizerState();
}

class _AudioLightVisualizerState extends State<AudioLightVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<double> _barLevels;
  late List<double> _peakLevels;
  late List<double> _peakHoldTimers;
  Duration _lastElapsed = Duration.zero;
  double _time = 0.0;

  @override
  void initState() {
    super.initState();
    _initArrays(widget.barCount);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )
      ..addListener(_onTick)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant AudioLightVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barCount != widget.barCount) {
      _initArrays(widget.barCount);
    }
  }

  void _initArrays(int count) {
    _barLevels = List<double>.filled(count, 0.08);
    _peakLevels = List<double>.filled(count, 0.08);
    _peakHoldTimers = List<double>.filled(count, 0.0);
  }

  void _onTick() {
    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    double dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1) {
      dt = 1 / 60;
    }

    _time += dt;
    _stepSpectrum(dt);
  }

  void _stepSpectrum(double dt) {
    final count = _barLevels.length;
    final volNorm = widget.isMuted ? 0.0 : (widget.volume.clamp(0, 100) / 100.0);
    final activeAudio = widget.isPlaying && !widget.isMuted && volNorm > 0.0;

    // Multi-tempo rhythmic envelope (~122 BPM kick + syncopated groove)
    final beatPhase = _time * 2.04 * math.pi * 2.0; // ~122 BPM
    final kick = math.pow((math.sin(beatPhase) * 0.5 + 0.5), 3.0).toDouble();
    final halfBeat =
        math.pow((math.sin(beatPhase * 0.5 + 0.7) * 0.5 + 0.5), 2.0).toDouble();
    final snare =
        math.pow((math.sin(beatPhase * 2.0 + 1.4) * 0.5 + 0.5), 4.0).toDouble();

    final energyScale = 0.24 + 0.76 * volNorm;

    for (int i = 0; i < count; i++) {
      final pos = count > 1 ? i / (count - 1) : 0.5;
      double target;

      if (activeAudio) {
        // Frequency-band shaping: bass on left, punchy mids in center, crisp highs on right
        final bassWeight = math.exp(-math.pow((pos - 0.14) * 3.4, 2));
        final midWeight = math.exp(-math.pow((pos - 0.50) * 3.0, 2));
        final highWeight = math.exp(-math.pow((pos - 0.84) * 3.6, 2));

        final w1 = math.sin(_time * (5.8 + i * 0.42) + i * 0.65) * 0.5 + 0.5;
        final w2 = math.sin(_time * (9.3 + i * 0.27) - i * 1.15) * 0.5 + 0.5;
        final w3 = math.cos(_time * (14.1 + i * 0.51) + i * 0.38) * 0.5 + 0.5;

        final rawBand = (bassWeight * (0.42 + 0.58 * kick) +
                midWeight * (0.35 + 0.40 * halfBeat + 0.25 * w1) +
                highWeight * (0.28 + 0.36 * snare + 0.36 * w3)) *
            0.78 +
            (w1 * 0.14 + w2 * 0.16 + w3 * 0.08);

        target = (0.10 + rawBand * energyScale).clamp(0.08, 1.0);
      } else if (widget.isPlaying && (widget.isMuted || volNorm == 0.0)) {
        // Muted while playing: dim flat baseline
        target = 0.04;
      } else {
        // Paused / Stopped: calm slow breathing idle wave
        final wave = math.sin(_time * 1.65 + pos * math.pi * 2.2) * 0.5 + 0.5;
        final breath = math.sin(_time * 0.75) * 0.5 + 0.5;
        target = 0.05 + (0.04 + 0.06 * breath) * wave;
      }

      // Fast attack, smooth decay
      final current = _barLevels[i];
      final rate = target > current ? 18.0 : (activeAudio ? 7.5 : 4.2);
      final alpha = (1.0 - math.exp(-rate * dt)).clamp(0.0, 1.0);
      final nextVal = current + (target - current) * alpha;
      _barLevels[i] = nextVal;

      // Peak-hold cap physics
      if (nextVal >= _peakLevels[i]) {
        _peakLevels[i] = nextVal;
        _peakHoldTimers[i] = activeAudio ? 0.26 : 0.05;
      } else if (_peakHoldTimers[i] > 0) {
        _peakHoldTimers[i] -= dt;
      } else {
        final fallSpeed = activeAudio ? 0.75 : 0.45;
        _peakLevels[i] = math.max(nextVal, _peakLevels[i] - fallSpeed * dt);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive =
        widget.isPlaying && !widget.isMuted && widget.volume > 0;
    return Opacity(
      opacity: widget.opacity.clamp(0.0, 1.0),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _AudioLightBarPainter(
                  barLevels: _barLevels,
                  peakLevels: _peakLevels,
                  isActive: isActive,
                  isMuted: widget.isMuted,
                  segmented: widget.segmented,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AudioLightBarPainter extends CustomPainter {
  final List<double> barLevels;
  final List<double> peakLevels;
  final bool isActive;
  final bool isMuted;
  final bool segmented;

  const _AudioLightBarPainter({
    required this.barLevels,
    required this.peakLevels,
    required this.isActive,
    required this.isMuted,
    required this.segmented,
  });

  Color _colorForHeight(double t, double barPos) {
    // Shift smoothly from cyan/emerald at bottom to violet/magenta/amber on high peaks
    if (isMuted) {
      return Color.lerp(
        const Color(0xFF475569),
        const Color(0xFF94A3B8),
        t,
      )!;
    }

    final lowColor = Color.lerp(
      const Color(0xFF22D3EE), // Cyan
      const Color(0xFF34D399), // Emerald
      barPos,
    )!;
    const midColor = Color(0xFFA78BFA); // Violet
    final highColor = Color.lerp(
      const Color(0xFFF472B6), // Magenta
      const Color(0xFFFBBF24), // Amber
      (barPos * 0.5 + 0.5).clamp(0.0, 1.0),
    )!;

    if (t < 0.52) {
      return Color.lerp(lowColor, midColor, t / 0.52)!;
    }
    return Color.lerp(midColor, highColor, (t - 0.52) / 0.48)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final count = barLevels.length;
    if (count == 0 || size.width <= 0 || size.height <= 0) return;

    const gap = 3.0;
    final totalGap = gap * (count - 1);
    final barWidth = ((size.width - totalGap) / count).clamp(2.0, 18.0);
    final startX = (size.width - (barWidth * count + totalGap)) * 0.5;

    final glowPaint = Paint()
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        isActive ? 6.0 : 3.0,
      );

    final segmentPaint = Paint()..style = PaintingStyle.fill;
    final dimSegmentPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..style = PaintingStyle.fill;

    final segmentCount = (size.height / 4.2).floor().clamp(6, 14);
    const segmentGap = 1.6;
    final segmentHeight =
        ((size.height - segmentGap * (segmentCount - 1)) / segmentCount)
            .clamp(1.5, 6.0);

    for (int i = 0; i < count; i++) {
      final level = barLevels[i].clamp(0.0, 1.0);
      final peak = peakLevels[i].clamp(0.0, 1.0);
      final x = startX + i * (barWidth + gap);
      final barPos = count > 1 ? i / (count - 1) : 0.5;
      final barHeight = (level * size.height).clamp(2.0, size.height);
      final barTop = size.height - barHeight;

      // Soft neon outer glow behind active bar
      if (level > 0.08) {
        final topColor = _colorForHeight(level, barPos);
        glowPaint.color = topColor.withValues(alpha: isActive ? 0.42 : 0.16);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, barTop, barWidth, barHeight),
            const Radius.circular(3),
          ),
          glowPaint,
        );
      }

      if (segmented) {
        final litSegments = (level * segmentCount).ceil().clamp(0, segmentCount);
        for (int s = 0; s < segmentCount; s++) {
          final segY = size.height - (s + 1) * segmentHeight - s * segmentGap;
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(x, segY, barWidth, segmentHeight),
            const Radius.circular(1.6),
          );
          if (s < litSegments) {
            final t = segmentCount > 1 ? s / (segmentCount - 1) : 1.0;
            final color = _colorForHeight(t, barPos);
            segmentPaint.color =
                color.withValues(alpha: isActive ? 0.95 : 0.52);
            canvas.drawRRect(rect, segmentPaint);
          } else {
            canvas.drawRRect(rect, dimSegmentPaint);
          }
        }
      } else {
        final gradient = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            _colorForHeight(0.0, barPos).withValues(alpha: isActive ? 0.92 : 0.45),
            _colorForHeight(0.55, barPos).withValues(alpha: isActive ? 0.95 : 0.50),
            _colorForHeight(1.0, barPos).withValues(alpha: isActive ? 1.0 : 0.55),
          ],
        );
        segmentPaint.shader = gradient.createShader(
          Rect.fromLTWH(x, 0, barWidth, size.height),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, barTop, barWidth, barHeight),
            const Radius.circular(3),
          ),
          segmentPaint,
        );
        segmentPaint.shader = null;
      }

      // Peak-hold cap
      if (peak > 0.08 && !isMuted) {
        final peakY = (size.height - peak * size.height)
            .clamp(0.0, size.height - 2.2);
        final peakColor = Color.lerp(
          _colorForHeight(peak, barPos),
          Colors.white,
          isActive ? 0.45 : 0.15,
        )!;
        final capPaint = Paint()
          ..color = peakColor.withValues(alpha: isActive ? 0.95 : 0.45);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, peakY, barWidth, 2.2),
            const Radius.circular(1.2),
          ),
          capPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AudioLightBarPainter oldDelegate) => true;
}
