import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 動態背景：光球呼吸、流動線條、粒子光點，深底藍綠科技風。
class DynamicBackground extends StatefulWidget {
  const DynamicBackground({super.key});

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
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _DynamicBackgroundPainter(t: _controller.value),
        size: Size.infinite,
      ),
    );
  }
}

class _DynamicBackgroundPainter extends CustomPainter {
  _DynamicBackgroundPainter({required this.t});

  final double t;
  static const int _particleCount = 140;
  static const int _lineCount = 18;
  static const int _orbCount = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.5;
    final maxDim = math.max(w, h);

    // 1. 深色基底漸層
    final bgRect = Rect.fromLTWH(0, 0, w, h);
    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF030308),
        const Color(0xFF0a0a18),
        const Color(0xFF06101a),
        const Color(0xFF080510),
      ],
    );
    canvas.drawRect(bgRect, Paint()..shader = bgGradient.createShader(bgRect));

    // 2. 遠景極淡網格（增加層次）
    _drawGrid(canvas, w, h);

    // 3. 流動線條（從中心向外輻射的曲線，光點沿線流動）
    _drawFlowingLines(canvas, cx, cy, maxDim);

    // 4. 粒子層（多層：大光點 + 小光點）
    _drawParticles(canvas, w, h);

    // 5. 中心光球（多層呼吸光）
    _drawCentralOrbs(canvas, cx, cy, maxDim);
  }

  void _drawGrid(Canvas canvas, double w, double h) {
    const step = 48.0;
    final gridPaint = Paint()
      ..color = const Color(0xFF0d1520).withOpacity(0.35)
      ..strokeWidth = 0.8;
    for (double x = 0; x <= w + step; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (double y = 0; y <= h + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }
  }

  void _drawFlowingLines(Canvas canvas, double cx, double cy, double maxDim) {
    for (int i = 0; i < _lineCount; i++) {
      final phase = (i / _lineCount) * 2 * math.pi + t * 2 * math.pi;
      final angle = phase * 0.5 + (i * 0.7);
      final path = Path();
      path.moveTo(cx, cy);
      final ctrl1 = Offset(
        cx + math.cos(angle) * maxDim * 0.35,
        cy + math.sin(angle) * maxDim * 0.35,
      );
      final end = Offset(
        cx + math.cos(angle + 0.8) * maxDim * 0.85,
        cy + math.sin(angle + 0.8) * maxDim * 0.85,
      );
      path.quadraticBezierTo(ctrl1.dx, ctrl1.dy, end.dx, end.dy);

      // 線條本體（半透明青藍）
      final linePaint = Paint()
        ..color = Color.lerp(
          const Color(0xFF00d4ff),
          const Color(0xFF00ffcc),
          (i % 3) / 3,
        )!.withOpacity(0.12 + 0.06 * (i % 2))
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, linePaint);

      // 流動光點（沿路徑多個光球）
      const numLights = 5;
      for (int L = 0; L < numLights; L++) {
        final along = (t * 1.2 + L / numLights) % 1.0;
        final along2 = along * along * (3 - 2 * along); // smoothstep
        final x = cx + (end.dx - cx) * along2 * 0.95;
        final y = cy + (end.dy - cy) * along2 * 0.95;
        final glowRadius = 4.0 + 3.0 * math.sin(t * 2 * math.pi + L);
        final grad = RadialGradient(
          colors: [
            const Color(0xFF00e5ff).withOpacity(0.9),
            const Color(0xFF00e5ff).withOpacity(0.3),
            const Color(0xFF00e5ff).withOpacity(0),
          ],
          stops: const [0.0, 0.4, 1.0],
        );
        canvas.drawCircle(
          Offset(x, y),
          glowRadius,
          Paint()..shader = grad.createShader(Rect.fromCircle(center: Offset(x, y), radius: glowRadius)),
        );
      }
    }
  }

  void _drawParticles(Canvas canvas, double w, double h) {
    for (int i = 0; i < _particleCount; i++) {
      final seed = i * 1.618033988749895;
      final baseX = (math.sin(seed * 1.1) * 0.5 + 0.5) * w;
      final baseY = (math.cos(seed * 0.9) * 0.5 + 0.5) * h;
      final driftX = math.cos(seed * 0.7) * t * 80;
      final driftY = math.sin(seed * 0.5) * t * 60;
      final wrapX = ((baseX + driftX) % (w + 40) + (w + 40)) % (w + 40) - 20;
      final wrapY = ((baseY + driftY) % (h + 40) + (h + 40)) % (h + 40) - 20;
      final twinkle = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 2 * math.pi * 2 + seed * 3));
      final radius = 1.2 + 2.5 * (math.sin(seed * 2) * 0.5 + 0.5);
      final hue = 0.45 + 0.15 * (math.sin(seed * 5) * 0.5 + 0.5);
      final color = HSLColor.fromAHSL(1, hue * 360, 0.9, 0.7).toColor();
      final grad = RadialGradient(
        colors: [
          color.withOpacity(twinkle * 0.85),
          color.withOpacity(twinkle * 0.25),
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

  void _drawCentralOrbs(Canvas canvas, double cx, double cy, double maxDim) {
    for (int o = 0; o < _orbCount; o++) {
      final phase = t * 2 * math.pi + o * 0.8;
      final breath = 0.85 + 0.15 * math.sin(phase);
      final baseRadius = maxDim * (0.18 + 0.08 * o);
      final radius = baseRadius * breath;
      final opacity = 0.15 + 0.08 * math.sin(phase * 0.7) + 0.02 * o;
      final colors = [
        const Color(0xFF00d4ff),
        const Color(0xFF00ffcc),
        const Color(0xFF0066aa),
      ];
      final color = colors[o % colors.length];
      final grad = RadialGradient(
        colors: [
          color.withOpacity(opacity),
          color.withOpacity(opacity * 0.4),
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

    // 最內核：小範圍高亮
    final coreBreath = 0.9 + 0.1 * math.sin(t * 2 * math.pi);
    final coreGrad = RadialGradient(
      colors: [
        const Color(0xFF88ffff).withOpacity(0.5),
        const Color(0xFF00ccff).withOpacity(0.2),
        const Color(0xFF00ccff).withOpacity(0),
      ],
      stops: const [0.0, 0.4, 1.0],
    );
    canvas.drawCircle(
      Offset(cx, cy),
      maxDim * 0.06 * coreBreath,
      Paint()..shader = coreGrad.createShader(Rect.fromCircle(center: Offset(cx, cy), radius: maxDim * 0.08)),
    );
  }

  @override
  bool shouldRepaint(covariant _DynamicBackgroundPainter oldDelegate) =>
      oldDelegate.t != t;
}
