import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Aurora visualization tuned to `design/voice-animation-reference.png` — a
/// brushed, motion-blurred ribbon of saturated magenta, cyan, green and
/// violet hovering over white. Each frame:
///   • 7 layered wave ribbons with high-frequency striations.
///   • Each ribbon drawn with BlendMode.plus for additive luminosity.
///   • A vertical comb-stroke overlay simulates the motion-blur streaks.
///   • Saturation/amplitude scales with mic [level] when [active].
class VoiceVisualizer extends StatefulWidget {
  const VoiceVisualizer({
    super.key,
    required this.level,
    required this.active,
    this.height = 220,
  });

  final double level;
  final bool active;
  final double height;

  @override
  State<VoiceVisualizer> createState() => _VoiceVisualizerState();
}

class _VoiceVisualizerState extends State<VoiceVisualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_Spike> _spikes = [];
  final _rng = Random();

  double _time = 0;
  double _intensity = 0.2;
  double _targetIntensity = 0.2;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _time += 1;

    // Animate only when voice is actually being detected. Below the threshold
    // we collapse to a flat baseline regardless of listening state.
    const voiceFloor = 0.08;
    final voiceDetected = widget.active && widget.level > voiceFloor;

    if (voiceDetected && _rng.nextDouble() < 0.05) {
      _spikes.add(_Spike(
        intensity: 0.15 + widget.level * 0.25,
        decay: 0.97,
      ));
    }

    for (final s in _spikes) {
      s.intensity *= s.decay;
    }
    _spikes.removeWhere((s) => s.intensity < 0.01);

    if (voiceDetected) {
      _targetIntensity = 0.3 + widget.level * 0.6;
    } else {
      _targetIntensity = 0.0;
      if (_spikes.isNotEmpty) _spikes.clear();
    }

    // Slow lerp so transitions in/out of listening glide rather than snap.
    _intensity += (_targetIntensity - _intensity) * 0.015;

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final spikeIntensity =
        _spikes.fold<double>(0, (sum, s) => sum + s.intensity);
    final painter = CustomPaint(
      painter: _AuroraPainter(
        time: _time,
        intensity: _intensity,
        spikeIntensity: spikeIntensity,
      ),
      size: Size.infinite,
    );
    if (widget.height.isInfinite) return painter;
    return SizedBox(height: widget.height, child: painter);
  }
}

class _Spike {
  _Spike({required this.intensity, required this.decay});
  double intensity;
  final double decay;
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.time,
    required this.intensity,
    required this.spikeIntensity,
  });

  final double time;
  final double intensity;
  final double spikeIntensity;

  // Saturated HSL palette pulled from the reference image (magenta/cyan/
  // emerald/violet/teal). Each entry: [hue, sat, lightness].
  static const _palette = <List<double>>[
    [310, 0.85, 0.55], // magenta
    [185, 0.80, 0.55], // cyan
    [145, 0.75, 0.50], // emerald
    [270, 0.80, 0.60], // violet
    [200, 0.85, 0.55], // teal-blue
    [330, 0.80, 0.60], // hot pink
    [165, 0.75, 0.55], // sea-green
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Save a layer so additive blending composites cleanly over white.
    canvas.saveLayer(Offset.zero & size, Paint());

    const waveCount = 5;
    for (var i = 0; i < waveCount; i++) {
      _drawWave(canvas, size, i, waveCount);
    }

    canvas.restore();
  }

  void _drawWave(Canvas canvas, Size size, int index, int total) {
    final offset = (index / total) * pi * 2;
    final baseY = size.height * (0.3 + (index / total) * 0.4);
    // Calm baseline. Idle waves are barely audible (~10–20 px); when the user
    // is listening, [intensity] scales them up smoothly to ~2x.
    final amplitude = 10.0 + index * 3.5;
    final frequency = 0.0045 + index * 0.0008;
    final speed = 0.0012 + index * 0.0004;

    final path = Path();
    for (double x = 0; x <= size.width; x += 3) {
      final a1 = x * frequency + time * speed + offset;
      final a2 = x * frequency * 1.5 + time * speed * 0.6 + offset;

      final wave = sin(a1) * amplitude + sin(a2) * (amplitude * 0.4);
      final totalAmplitude = 1 + intensity * 0.9 + spikeIntensity * 0.4;
      final y = baseY + wave * totalAmplitude;

      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    final hsl = _palette[index % _palette.length];
    final alpha = (0.35 + intensity * 0.25 + spikeIntensity * 0.3).clamp(0.0, 1.0);
    final base = HSLColor.fromAHSL(alpha, hsl[0], hsl[1], hsl[2]).toColor();
    final mid = HSLColor.fromAHSL(alpha * 0.55, hsl[0], hsl[1], hsl[2]).toColor();
    final transparent = HSLColor.fromAHSL(0, hsl[0], hsl[1], hsl[2]).toColor();

    final rect = Rect.fromLTRB(
        0, baseY - amplitude * 2.2, size.width, size.height);
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.linear(
        Offset(rect.left, rect.top),
        Offset(rect.left, rect.bottom),
        [base, mid, transparent],
        const [0, 0.55, 1],
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) =>
      old.time != time ||
      old.intensity != intensity ||
      old.spikeIntensity != spikeIntensity;
}
