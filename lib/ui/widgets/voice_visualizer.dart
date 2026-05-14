import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Bottom-anchored aurora wave, ported one-for-one from
/// `design/voice-app.html`'s `<svg>` block:
///
///   • A wavy baseline computed from three superposed sine waves with an
///     envelope that zeros the amplitude at the edges and peaks in the
///     middle.
///   • Three glow strokes drawn along the wave path with progressively
///     tighter blur radii (halo / mid / core) — the colour comes from a
///     horizontal palette gradient.
///   • An opaque silhouette fill **below** the wave that clips the bottom
///     half of the blurred glows, leaving a vibrant rim above the wave.
///   • A depth-faded palette fill **below** the wave on top of the
///     silhouette, fading from ~75 % opacity at the baseline to 0 % at the
///     bottom edge.
///
/// Two motion presets switch by [active]:
///   * `true` → **LISTENING** — amps `[32, 20, 11]`, speed `1.0`. Voice
///     mode default; the wave heaves dramatically.
///   * `false` → **CALM** — amps `[4, 2.5, 1]`, speed `0.5`. Chat mode
///     default; almost-flat drift.
///
/// The state crossfades between presets via the same `1 - 0.0001^dt` lerp
/// the HTML uses, so changes feel like a slow breath.
class VoiceVisualizer extends StatefulWidget {
  const VoiceVisualizer({
    super.key,
    required this.level,
    required this.active,
    this.height = 220,
  });

  /// Mic level (0..1). Unused by the design but kept for API parity.
  final double level;
  final bool active;
  final double height;

  @override
  State<VoiceVisualizer> createState() => _VoiceVisualizerState();
}

class _VoiceVisualizerState extends State<VoiceVisualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastTick;

  // Live (lerped) wave parameters. Initialise to LISTENING so the wave is
  // already moving at first frame in voice mode.
  double _a0 = _listening[0];
  double _a1 = _listening[1];
  double _a2 = _listening[2];
  double _speed = _listeningSpeed;
  double _t = 0;

  static const _listening = [32.0, 20.0, 11.0];
  static const _calm = [4.0, 2.5, 1.0];
  static const _listeningSpeed = 1.0;
  static const _calmSpeed = 0.5;

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
    final last = _lastTick ?? elapsed;
    final dt =
        ((elapsed - last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _lastTick = elapsed;

    final target = widget.active ? _listening : _calm;
    final targetSpeed = widget.active ? _listeningSpeed : _calmSpeed;

    // Same lerp shape as the HTML: `1 - 0.0001^dt`. Reaches target slowly
    // at low dt and pops faster at high dt — feels organic.
    final lerp = 1 - pow(0.0001, dt).toDouble();
    _a0 += (target[0] - _a0) * lerp;
    _a1 += (target[1] - _a1) * lerp;
    _a2 += (target[2] - _a2) * lerp;
    _speed += (targetSpeed - _speed) * lerp;

    _t += dt * _speed;

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(
      painter: _WavePainter(t: _t, amps: [_a0, _a1, _a2]),
      size: Size.infinite,
    );
    if (widget.height.isInfinite) return painter;
    return SizedBox(height: widget.height, child: painter);
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.t, required this.amps});

  final double t;
  final List<double> amps;

  // Wave-stage occupies the bottom half of the painter canvas — matches the
  // HTML's `.wave-stage { bottom: 0; height: 50% }` rule.
  static const _stageTopRatio = 0.5;
  // SVG viewBox is 400x400; baseY=230 → wave baseline at 57.5 % of stage.
  static const _baseYInStage = 230.0 / 400.0;
  // Path resolution (HTML uses STEPS = 72).
  static const _steps = 72;

  // Horizontal palette (9 stops) lifted directly from the SVG defs.
  static const _paletteStops = [
    0.0, 0.14, 0.28, 0.42, 0.54, 0.64, 0.76, 0.88, 1.0,
  ];

  // Pre-baked at full opacity; we wrap saveLayer with the layer's alpha.
  static const _paletteRgb = <List<int>>[
    [150, 70,  240], // purple
    [220, 100, 230], // magenta
    [180, 100, 255], // violet
    [80,  180, 255], // blue
    [110, 230, 200], // cyan-green
    [150, 255, 140], // green
    [255, 220, 100], // yellow
    [255, 150, 80],  // orange
    [230, 80,  80],  // red
  ];

  // Silhouette colour (dark mode only — `--silhouette: #000` at 0.86).
  static const _silhouetteColor = Color.fromRGBO(0, 0, 0, 0.86);

  // Mirror fill base opacity.
  static const _mirrorAlpha = 0.7;

  // Mirror depth-fade alpha stops (white where mirror is opaque, transparent
  // where mirror should disappear). SVG used y1=160, y2=395 in user units;
  // translate those to stage-fraction:
  //   160 / 400 = 0.40 (top of fade)
  //   395 / 400 = 0.9875 (bottom of fade)
  // and stops 0/35/75/100 → opacity 0.95/0.55/0.12/0 as in the SVG.
  static const _fadeFromStage = 0.40;
  static const _fadeToStage = 0.9875;
  static const _fadeAlphas = [0.95, 0.55, 0.12, 0.0];
  static const _fadeStops = [0.0, 0.35, 0.75, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    // Background — same as the HTML `var(--bg) = #000` in dark mode.
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000));

    final stageTop = size.height * _stageTopRatio;
    final stageHeight = size.height - stageTop;
    final baseY = stageTop + stageHeight * _baseYInStage;

    // Wave path computation matches the HTML buildWave().
    final topPath = Path();
    for (var i = 0; i <= _steps; i++) {
      final u = i / _steps;
      final x = u * size.width;
      final env = pow(sin(pi * u), 0.4).toDouble();
      final motion = sin(t * 0.45 + i * 0.20) * amps[0] +
          sin(t * 0.31 + i * 0.34) * amps[1] +
          sin(t * 0.78 + i * 0.11) * amps[2];
      // The HTML amps are in the SVG's 400-unit stage; scale to pixels.
      final y = baseY + motion * (stageHeight / 400.0) * env;
      if (i == 0) {
        topPath.moveTo(x, y);
      } else {
        topPath.lineTo(x, y);
      }
    }

    // Closed fill path below the wave to the canvas bottom.
    final fillPath = Path()..addPath(topPath, Offset.zero);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    // Shader the glow strokes & mirror fill share. The SVG palette gradient
    // is `x1=0,y1=0,x2=1,y2=0` (horizontal across the stage).
    final paletteShader = ui.Gradient.linear(
      Offset(0, baseY),
      Offset(size.width, baseY),
      _paletteRgb
          .map((c) => Color.fromRGBO(c[0], c[1], c[2], 1.0))
          .toList(growable: false),
      _paletteStops,
    );

    // Stroke widths & blur sigmas scale from the 400-unit stage.
    final unit = stageHeight / 400.0;
    final haloStroke = 160 * unit;
    final midStroke = 60 * unit;
    final coreStroke = 14 * unit;
    final haloSigma = 38 * unit;
    final midSigma = 14 * unit;
    final coreSigma = 5 * unit;

    // --- Glow strokes (back to front) ---
    _strokeGlow(canvas, topPath, paletteShader,
        width: haloStroke, sigma: haloSigma, alpha: 0.35);
    _strokeGlow(canvas, topPath, paletteShader,
        width: midStroke, sigma: midSigma, alpha: 0.55);
    _strokeGlow(canvas, topPath, paletteShader,
        width: coreStroke, sigma: coreSigma, alpha: 0.85);

    // --- Silhouette fill (clips bottom half of the blurred glows) ---
    canvas.drawPath(fillPath, Paint()..color = _silhouetteColor);

    // --- Wave mirror: palette fill with vertical depth fade ---
    _drawMirror(canvas, fillPath, paletteShader, size,
        stageTop: stageTop, stageHeight: stageHeight);
  }

  void _strokeGlow(Canvas canvas, Path path, ui.Shader palette,
      {required double width, required double sigma, required double alpha}) {
    // saveLayer with alpha → all draws in the layer are flattened to that
    // alpha when composited. Cheaper than baking per-stop alpha into the
    // shader (and lets us reuse one shader across the three glow layers).
    final layerPaint = Paint()..color = Color.fromRGBO(255, 255, 255, alpha);
    canvas.saveLayer(null, layerPaint);
    canvas.drawPath(
      path,
      Paint()
        ..shader = palette
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, sigma),
    );
    canvas.restore();
  }

  void _drawMirror(
    Canvas canvas,
    Path fillPath,
    ui.Shader palette,
    Size size, {
    required double stageTop,
    required double stageHeight,
  }) {
    // Composite layer: palette fill * vertical alpha gradient.
    final layerPaint = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, _mirrorAlpha);
    canvas.saveLayer(null, layerPaint);

    canvas.drawPath(fillPath, Paint()..shader = palette);

    final fadeStart = stageTop + stageHeight * _fadeFromStage;
    final fadeEnd = stageTop + stageHeight * _fadeToStage;
    final maskShader = ui.Gradient.linear(
      Offset(0, fadeStart),
      Offset(0, fadeEnd),
      _fadeAlphas
          .map((a) => Color.fromRGBO(255, 255, 255, a))
          .toList(growable: false),
      _fadeStops,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = maskShader,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.t != t ||
      old.amps[0] != amps[0] ||
      old.amps[1] != amps[1] ||
      old.amps[2] != amps[2];
}
