import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 動態背景：漩渦、六角網格、雷達、電路、數據面板、浮動多邊形、可自訂主色。
class DynamicBackground extends StatefulWidget {
  const DynamicBackground({super.key, this.primaryColor});

  final Color? primaryColor;

  @override
  State<DynamicBackground> createState() => _DynamicBackgroundState();
}

class _DynamicBackgroundState extends State<DynamicBackground>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor ?? const Color(0xFF00e5ff);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _DynamicBackgroundPainter(t: _controller.value, primaryColor: color),
        size: Size.infinite,
      ),
    );
  }
}

class _DynamicBackgroundPainter extends CustomPainter {
  _DynamicBackgroundPainter({required this.t, required this.primaryColor});

  final double t;
  final Color primaryColor;

  late final Color _cyan;
  late final Color _cyanDim;
  late final Color _blue;
  late final Color _electric;

  void _deriveColors() {
    final hsl = HSLColor.fromColor(primaryColor);
    _cyan = primaryColor;
    _electric = hsl.withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0)).toColor();
    _blue = hsl.withLightness((hsl.lightness - 0.25).clamp(0.0, 1.0)).withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0)).toColor();
    _cyanDim = hsl.withSaturation((hsl.saturation * 0.6).clamp(0.0, 1.0)).withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0)).toColor();
  }

  static const int _particleCount = 220;
  static const int _lineCount = 24;
  static const int _orbCount = 4;
  static const int _circuitSegments = 32;
  static const int _hexRows = 14;
  static const int _hexCols = 20;
  static const int _vortexArms = 5;
  static const int _floatingPolyCount = 16;

  @override
  void paint(Canvas canvas, Size size) {
    _deriveColors();
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.5;
    final maxDim = math.max(w, h);

    _drawBase(canvas, w, h);
    _drawHexGrid(canvas, w, h);
    _drawConcentricRings(canvas, cx, cy, maxDim);
    _drawVortex(canvas, cx, cy, maxDim);
    _drawRadarSweep(canvas, cx, cy, maxDim);
    _drawCircuitPaths(canvas, cx, cy, w, h);
    _drawFlowingDataLines(canvas, cx, cy, maxDim);
    _drawWireframeSphere(canvas, cx, cy, maxDim);
    _drawDataPanels(canvas, w, h);
    _drawHudCorners(canvas, w, h);
    _drawCentralCore(canvas, cx, cy, maxDim);
    _drawFloatingPolygons(canvas, w, h, cx, cy);
    _drawParticles(canvas, w, h);
    _drawScanLine(canvas, w, h);
  }

  void _drawBase(Canvas canvas, double w, double h) {
    final rect = Rect.fromLTWH(0, 0, w, h);
    final grad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF020510),
        const Color(0xFF040a18),
        const Color(0xFF051025),
        const Color(0xFF030818),
        const Color(0xFF020508),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = grad.createShader(rect));
  }

  void _drawHexGrid(Canvas canvas, double w, double h) {
    const radius = 22.0;
    final vert = radius * math.sqrt(3);
    final paint = Paint()
      ..color = _cyanDim.withOpacity(0.08)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    for (int row = -_hexRows; row <= _hexRows; row++) {
      for (int col = -_hexCols; col <= _hexCols; col++) {
        final x = w * 0.5 + col * (radius * 1.5);
        final y = h * 0.5 + row * vert + (col % 2) * (vert * 0.5);
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = (i * 60) * math.pi / 180;
          final px = x + radius * math.cos(angle);
          final py = y + radius * math.sin(angle);
          if (i == 0) path.moveTo(px, py);
          else path.lineTo(px, py);
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }
    paint.color = _cyan.withOpacity(0.06);
    paint.strokeWidth = 0.4;
    const r2 = 12.0;
    final v2 = r2 * math.sqrt(3);
    for (int row = -_hexRows * 2; row <= _hexRows * 2; row++) {
      for (int col = -_hexCols * 2; col <= _hexCols * 2; col++) {
        final x = w * 0.5 + col * (r2 * 1.5) + (t * 20) % 30;
        final y = h * 0.5 + row * v2 + (col % 2) * (v2 * 0.5) + (t * 15) % 25;
        if (x < -50 || x > w + 50 || y < -50 || y > h + 50) continue;
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = (i * 60) * math.pi / 180;
          if (i == 0) path.moveTo(x + r2 * math.cos(angle), y + r2 * math.sin(angle));
          else path.lineTo(x + r2 * math.cos(angle), y + r2 * math.sin(angle));
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawConcentricRings(Canvas canvas, double cx, double cy, double maxDim) {
    for (int r = 1; r <= 12; r++) {
      final radius = maxDim * (0.08 + 0.06 * r);
      final pulse = 0.92 + 0.08 * math.sin(t * 2 * math.pi + r * 0.3);
      final opacity = (0.2 - r * 0.012) * pulse;
      if (opacity <= 0) continue;
      final paint = Paint()
        ..color = _cyan.withOpacity(opacity.clamp(0.0, 1.0))
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(cx, cy), radius * pulse, paint);
    }
  }

  /// 漩渦：多條螺旋臂從中心旋轉外擴，取代外擴圓圈。
  void _drawVortex(Canvas canvas, double cx, double cy, double maxDim) {
    const turns = 4.5;
    const pointsPerTurn = 45;
    final totalPoints = (turns * pointsPerTurn).toInt();
    final rotation = t * 2 * math.pi;

    for (int arm = 0; arm < _vortexArms; arm++) {
      final armOffset = (arm / _vortexArms) * 2 * math.pi;
      final path = Path();
      for (int i = 0; i <= totalPoints; i++) {
        final theta = (i / totalPoints) * turns * 2 * math.pi + armOffset + rotation;
        final r = maxDim * (0.04 + 0.72 * (i / totalPoints));
        final x = cx + r * math.cos(theta);
        final y = cy + r * math.sin(theta);
        if (i == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      final opacity = 0.08 + 0.06 * (1 - arm / _vortexArms);
      final paint = Paint()
        ..color = _electric.withOpacity(opacity)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, paint);
    }

    for (int arm = 0; arm < _vortexArms; arm++) {
      final armOffset = (arm / _vortexArms) * 2 * math.pi + math.pi / _vortexArms;
      final path = Path();
      for (int i = 0; i <= totalPoints; i++) {
        final theta = (i / totalPoints) * turns * 2 * math.pi + armOffset + rotation * 1.1;
        final r = maxDim * (0.03 + 0.65 * (i / totalPoints));
        final x = cx + r * math.cos(theta);
        final y = cy + r * math.sin(theta);
        if (i == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      final paint = Paint()
        ..color = _cyan.withOpacity(0.06)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, paint);
    }
  }

  void _drawRadarSweep(Canvas canvas, double cx, double cy, double maxDim) {
    final angle = t * 2 * math.pi;
    final sweepGrad = SweepGradient(
      startAngle: angle - 0.15,
      endAngle: angle + 0.25,
      colors: [
        _electric.withOpacity(0),
        _electric.withOpacity(0.35),
        _cyan.withOpacity(0.5),
        _electric.withOpacity(0.2),
        _electric.withOpacity(0),
      ],
    );
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: maxDim * 0.9);
    canvas.saveLayer(rect, Paint());
    canvas.drawCircle(Offset(cx, cy), maxDim * 0.88, Paint()..shader = sweepGrad.createShader(rect));
    canvas.drawCircle(Offset(cx, cy), maxDim * 0.88, Paint()
      ..color = _cyan.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    canvas.restore();
    final lineLen = maxDim * 0.85;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + math.cos(angle) * lineLen, cy + math.sin(angle) * lineLen),
      Paint()
        ..color = _electric.withOpacity(0.6)
        ..strokeWidth = 1.5,
    );
  }

  void _drawCircuitPaths(Canvas canvas, double cx, double cy, double w, double h) {
    final seed = 0.7;
    for (int s = 0; s < _circuitSegments; s++) {
      final phase = (s / _circuitSegments) * 2 * math.pi + t * 0.5;
      final path = Path();
      var x = cx + math.cos(phase) * w * 0.2;
      var y = cy + math.sin(phase) * h * 0.2;
      path.moveTo(x, y);
      for (int step = 0; step < 6; step++) {
        final dir = (phase + step * 0.8 + s * 0.2).floor() % 4;
        final len = 25.0 + 60.0 * (math.sin(seed * s + step) * 0.5 + 0.5);
        if (dir == 0) x += len;
        else if (dir == 1) y += len;
        else if (dir == 2) x -= len;
        else y -= len;
        path.lineTo(x, y);
        canvas.drawCircle(Offset(x, y), 1.5, Paint()..color = _cyan.withOpacity(0.4 + 0.2 * math.sin(t * 4 + s)));
      }
      final paint = Paint()
        ..color = _cyanDim.withOpacity(0.18)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, paint);
    }
  }

  void _drawFlowingDataLines(Canvas canvas, double cx, double cy, double maxDim) {
    for (int i = 0; i < _lineCount; i++) {
      final phase = (i / _lineCount) * 2 * math.pi + t * 2 * math.pi;
      final angle = phase * 0.5 + (i * 0.6);
      final path = Path();
      path.moveTo(cx, cy);
      final ctrl1 = Offset(cx + math.cos(angle) * maxDim * 0.4, cy + math.sin(angle) * maxDim * 0.4);
      final end = Offset(cx + math.cos(angle + 0.9) * maxDim * 0.92, cy + math.sin(angle + 0.9) * maxDim * 0.92);
      path.quadraticBezierTo(ctrl1.dx, ctrl1.dy, end.dx, end.dy);

      final linePaint = Paint()
        ..color = Color.lerp(_cyan, _electric, (i % 4) / 4)!.withOpacity(0.15 + 0.08 * (i % 2))
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, linePaint);

      const numLights = 6;
      for (int L = 0; L < numLights; L++) {
        final along = (t * 1.5 + L / numLights) % 1.0;
        final along2 = along * along * (3 - 2 * along);
        final x = cx + (end.dx - cx) * along2 * 0.95;
        final y = cy + (end.dy - cy) * along2 * 0.95;
        final glowRadius = 5.0 + 4.0 * math.sin(t * 2 * math.pi + L * 0.7);
        final grad = RadialGradient(
          colors: [
            _electric.withOpacity(0.95),
            _cyan.withOpacity(0.4),
            _cyan.withOpacity(0),
          ],
          stops: const [0.0, 0.35, 1.0],
        );
        canvas.drawCircle(
          Offset(x, y),
          glowRadius,
          Paint()..shader = grad.createShader(Rect.fromCircle(center: Offset(x, y), radius: glowRadius)),
        );
      }
    }
  }

  /// 中心周圍的線框球面感（經緯弧線）。
  void _drawWireframeSphere(Canvas canvas, double cx, double cy, double maxDim) {
    final radius = maxDim * 0.35;
    final rotY = t * 0.3;
    for (int lat = 1; lat <= 6; lat++) {
      final phi = (lat / 7) * math.pi;
      final path = Path();
      for (int lon = 0; lon <= 24; lon++) {
        final th = (lon / 24) * 2 * math.pi + rotY;
        final x = cx + radius * math.sin(phi) * math.cos(th);
        final y = cy - radius * math.cos(phi) * 0.6;
        if (lon == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      canvas.drawPath(path, Paint()
        ..color = _cyan.withOpacity(0.06)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke);
    }
    for (int lon = 0; lon < 8; lon++) {
      final th = (lon / 8) * 2 * math.pi + rotY;
      final path = Path();
      for (int lat = 0; lat <= 12; lat++) {
        final phi = (lat / 12) * math.pi;
        final x = cx + radius * math.sin(phi) * math.cos(th);
        final y = cy - radius * math.cos(phi) * 0.6;
        if (lat == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      canvas.drawPath(path, Paint()
        ..color = _cyanDim.withOpacity(0.07)
        ..strokeWidth = 0.7
        ..style = PaintingStyle.stroke);
    }
  }

  void _drawDataPanels(Canvas canvas, double w, double h) {
    final panels = [
      (w * 0.08, h * 0.12, 90.0, 55.0),
      (w * 0.72, h * 0.15, 85.0, 50.0),
      (w * 0.1, h * 0.72, 80.0, 45.0),
      (w * 0.68, h * 0.7, 95.0, 48.0),
      (w * 0.42, h * 0.08, 70.0, 38.0),
      (w * 0.38, h * 0.82, 75.0, 40.0),
    ];
    for (int i = 0; i < panels.length; i++) {
      final (lx, ty, pw, ph) = panels[i];
      final pulse = 0.7 + 0.3 * math.sin(t * 2 * math.pi + i * 0.5);
      final border = Paint()
        ..color = _cyan.withOpacity(0.12 * pulse)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromLTWH(lx, ty, pw, ph), border);
      canvas.drawRect(Rect.fromLTWH(lx + 2, ty + 2, pw - 4, ph - 4), Paint()
        ..color = _cyan.withOpacity(0.03)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5);
      final lineY = ty + 14 + (i % 3) * 8;
      canvas.drawLine(Offset(lx + 6, lineY), Offset(lx + pw - 6, lineY), Paint()
        ..color = _cyanDim.withOpacity(0.15 * (0.5 + 0.5 * math.sin(t * 3 + i))));
    }
  }

  void _drawHudCorners(Canvas canvas, double w, double h) {
    const len = 28.0;
    const thick = 2.0;
    final paint = Paint()
      ..color = _cyan.withOpacity(0.35)
      ..strokeWidth = thick
      ..style = PaintingStyle.stroke;
    final corners = [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)];
    final angles = [0.0, math.pi * 0.5, math.pi, math.pi * 1.5];
    for (int c = 0; c < 4; c++) {
      canvas.save();
      canvas.translate(corners[c].$1, corners[c].$2);
      canvas.rotate(angles[c]);
      canvas.drawPath(Path()
        ..moveTo(0, len)
        ..lineTo(0, 0)
        ..lineTo(len, 0), paint);
      canvas.drawPath(Path()
        ..moveTo(len * 0.5, 0)
        ..lineTo(len, 0)
        ..lineTo(len, thick), paint);
      canvas.restore();
    }
  }

  void _drawCentralCore(Canvas canvas, double cx, double cy, double maxDim) {
    for (int o = 0; o < _orbCount; o++) {
      final phase = t * 2 * math.pi + o * 0.7;
      final breath = 0.88 + 0.12 * math.sin(phase);
      final baseRadius = maxDim * (0.12 + 0.06 * o);
      final radius = baseRadius * breath;
      final opacity = 0.2 + 0.1 * math.sin(phase * 0.6) + 0.02 * o;
      final colors = [_cyan, _electric, _blue, _cyanDim];
      final color = colors[o % colors.length];
      final grad = RadialGradient(
        colors: [
          color.withOpacity(opacity),
          color.withOpacity(opacity * 0.35),
          color.withOpacity(0),
        ],
        stops: const [0.0, 0.5, 1.0],
      );
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()..shader = grad.createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius)),
      );
    }
    final coreBreath = 0.92 + 0.08 * math.sin(t * 2 * math.pi);
    final coreGrad = RadialGradient(
      colors: [
        _electric.withOpacity(0.6),
        _cyan.withOpacity(0.25),
        _cyan.withOpacity(0),
      ],
      stops: const [0.0, 0.4, 1.0],
    );
    canvas.drawCircle(
      Offset(cx, cy),
      maxDim * 0.055 * coreBreath,
      Paint()..shader = coreGrad.createShader(Rect.fromCircle(center: Offset(cx, cy), radius: maxDim * 0.07)),
    );
  }

  /// 浮動多邊形（六角/四邊），半透明發光，參考圖的晶體感。
  void _drawFloatingPolygons(Canvas canvas, double w, double h, double cx, double cy) {
    for (int i = 0; i < _floatingPolyCount; i++) {
      final seed = i * 2.1 + 0.7;
      final side = 4 + (i % 3);
      final size = 12.0 + 18.0 * (math.sin(seed) * 0.5 + 0.5);
      final centerX = (math.sin(seed * 1.3) * 0.5 + 0.5) * w + math.cos(t + seed) * 15;
      final centerY = (math.cos(seed * 0.9) * 0.5 + 0.5) * h + math.sin(t * 0.8 + seed) * 12;
      final rot = t * 0.5 + seed * 0.4;
      final path = Path();
      for (int v = 0; v < side; v++) {
        final angle = (v / side) * 2 * math.pi + rot;
        final px = centerX + size * math.cos(angle);
        final py = centerY + size * math.sin(angle);
        if (v == 0) path.moveTo(px, py);
        else path.lineTo(px, py);
      }
      path.close();
      final opacity = 0.06 + 0.08 * (0.5 + 0.5 * math.sin(t * 2 + seed));
      canvas.drawPath(path, Paint()
        ..color = _cyan.withOpacity(opacity)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke);
      canvas.drawPath(path, Paint()
        ..color = _cyan.withOpacity(opacity * 0.25)
        ..style = PaintingStyle.fill);
    }
  }

  void _drawParticles(Canvas canvas, double w, double h) {
    final hsl = HSLColor.fromColor(primaryColor);
    final hue = hsl.hue;
    for (int i = 0; i < _particleCount; i++) {
      final seed = i * 1.618033988749895;
      final baseX = (math.sin(seed * 1.1) * 0.5 + 0.5) * w;
      final baseY = (math.cos(seed * 0.9) * 0.5 + 0.5) * h;
      final driftX = math.cos(seed * 0.7) * t * 120;
      final driftY = math.sin(seed * 0.5) * t * 90;
      final wrapX = ((baseX + driftX) % (w + 60) + (w + 60)) % (w + 60) - 30;
      final wrapY = ((baseY + driftY) % (h + 60) + (h + 60)) % (h + 60) - 30;
      final twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 2 * math.pi * 2 + seed * 3));
      final radius = 1.0 + 2.8 * (math.sin(seed * 2) * 0.5 + 0.5);
      final color = HSLColor.fromAHSL(1, hue, 0.9, 0.65).toColor();
      final grad = RadialGradient(
        colors: [
          color.withOpacity(twinkle * 0.9),
          color.withOpacity(twinkle * 0.2),
          color.withOpacity(0),
        ],
        stops: const [0.0, 0.5, 1.0],
      );
      canvas.drawCircle(
        Offset(wrapX, wrapY),
        radius,
        Paint()..shader = grad.createShader(Rect.fromCircle(center: Offset(wrapX, wrapY), radius: radius)),
      );
    }
  }

  void _drawScanLine(Canvas canvas, double w, double h) {
    final y = (t * 1.2 % 1.0) * (h + 40) - 20;
    final grad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _cyan.withOpacity(0),
        _electric.withOpacity(0.2),
        _cyan.withOpacity(0),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, y - 25, w, 50),
      Paint()..shader = grad.createShader(Rect.fromLTWH(0, y - 25, w, 50)),
    );
  }

  @override
  bool shouldRepaint(covariant _DynamicBackgroundPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.primaryColor != primaryColor;
}
