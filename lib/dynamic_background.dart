import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 動態背景：自繪螺旋銀河 + 緩慢旋轉與星光閃爍。
class DynamicBackground extends StatefulWidget {
  const DynamicBackground({super.key, this.primaryColor, this.meteorCount = 0});

  final Color? primaryColor;
  final int meteorCount;

  @override
  State<DynamicBackground> createState() => _DynamicBackgroundState();
}

class _DynamicBackgroundState extends State<DynamicBackground>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _twinkleController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _twinkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _twinkleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _GalaxyPainter(t: _controller.value),
            size: Size.infinite,
          ),
        ),
        AnimatedBuilder(
          animation: _twinkleController,
          builder: (context, _) => CustomPaint(
            painter: _TwinklePainter(t: _twinkleController.value),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }
}

class _GalaxyPainter extends CustomPainter {
  _GalaxyPainter({required this.t});

  final double t;

  static const int _armCount = 8;
  static const int _armSegments = 80;
  static const int _coreStars = 900;
  static const int _armStars = 2400;
  static const int _fieldStars = 1300;
  static const int _dustPatches = 180;
  static const double _twoPi = 2 * 3.141592653589793;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.5;
    final maxDim = math.max(w, h);

    _drawBase(canvas, w, h);
    _drawNebulaGlow(canvas, cx, cy, maxDim);
    _drawSpiralArms(canvas, cx, cy, maxDim);
    _drawDustPatches(canvas, cx, cy, maxDim);
    _drawCore(canvas, cx, cy, maxDim);
    _drawArmStars(canvas, cx, cy, maxDim);
    _drawCoreStars(canvas, cx, cy, maxDim);
    _drawFieldStars(canvas, w, h);
    _drawRandomJapanese(canvas, w, h, t);
  }

  static const _japaneseChars = 'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン';

  static const _colorPalette = [
    Color(0xFFf472b6),
    Color(0xFFa78bfa),
    Color(0xFF38bdf8),
    Color(0xFF34d399),
    Color(0xFFfbbf24),
    Color(0xFFfb923c),
    Color(0xFFc084fc),
    Color(0xFF67e8f9),
  ];

  void _drawRandomJapanese(Canvas canvas, double w, double h, double t) {
    const flashWindow = 0.12;
    final phase = (t / flashWindow).floor();
    final inFlash = (t % flashWindow) < flashWindow * 0.6;
    if (!inFlash) return;
    final rnd = math.Random(phase);
    final charCount = 4 + rnd.nextInt(8);
    for (int i = 0; i < charCount; i++) {
      final idx = rnd.nextInt(_japaneseChars.length);
      final char = _japaneseChars[idx];
      final x = rnd.nextDouble() * (w - 80) + 20;
      final y = rnd.nextDouble() * (h - 80) + 20;
      final size = 18.0 + rnd.nextDouble() * 22;
      final color = _colorPalette[rnd.nextInt(_colorPalette.length)];
      final opacity = 0.75 + rnd.nextDouble() * 0.25;
      final tp = TextPainter(
        text: TextSpan(
          text: char,
          style: TextStyle(
            fontSize: size,
            color: color.withOpacity(opacity),
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
    }
  }

  void _drawBase(Canvas canvas, double w, double h) {
    final rect = Rect.fromLTWH(0, 0, w, h);
    final grad = RadialGradient(
      center: Alignment.center,
      radius: 1.2,
      colors: [
        const Color(0xFF0a0612),
        const Color(0xFF050308),
        const Color(0xFF000000),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = grad.createShader(rect));
  }

  void _drawNebulaGlow(Canvas canvas, double cx, double cy, double maxDim) {
    final r = maxDim * 0.55;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    final grad = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        const Color(0x302a1a4a),
        const Color(0x18102040),
        const Color(0x08081020),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 0.6, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTWH(cx - r, cy - r, r * 2, r * 2),
      Paint()..shader = grad.createShader(rect),
    );
  }

  double _spiralAngle(double progress) {
    const turns = 0.65;
    return progress * turns * 2 * math.pi;
  }

  double _spiralRadius(double progress, double maxR) {
    return 0.08 * maxR + progress * 0.92 * maxR;
  }

  void _drawSpiralArms(Canvas canvas, double cx, double cy, double maxDim) {
    final maxR = maxDim * 0.58;
    final baseRotation = -t * _twoPi;
    for (int arm = 0; arm < _armCount; arm++) {
      final baseAngle = (arm / _armCount) * _twoPi + baseRotation;
      for (int i = 0; i < _armSegments; i++) {
        final progress = (i + 1) / (_armSegments + 1);
        final angle = baseAngle + _spiralAngle(progress);
        final r = _spiralRadius(progress, maxR);
        final armWidth = 0.06 * maxR * (0.4 + 0.6 * progress);
        final x = cx + r * math.cos(angle);
        final y = cy + r * math.sin(angle);
        final alpha = (0.35 * (1 - progress * 0.5)).clamp(0.0, 1.0);
        final paint = Paint()
          ..color = Color.fromRGBO(120, 80, 180, alpha * 0.5)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(x, y), armWidth, paint);
      }
    }
    for (int arm = 0; arm < _armCount; arm++) {
      final baseAngle = (arm / _armCount) * _twoPi + baseRotation;
      for (int i = 0; i < _armSegments; i++) {
        final progress = (i + 1) / (_armSegments + 1);
        final angle = baseAngle + _spiralAngle(progress);
        final r = _spiralRadius(progress, maxR);
        final armWidth = 0.03 * maxR * (0.5 + 0.5 * progress);
        final x = cx + r * math.cos(angle);
        final y = cy + r * math.sin(angle);
        final alpha = (0.5 * (1 - progress * 0.4)).clamp(0.0, 1.0);
        final paint = Paint()
          ..color = Color.fromRGBO(180, 140, 255, alpha * 0.4)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(x, y), armWidth, paint);
      }
    }
  }

  void _drawDustPatches(Canvas canvas, double cx, double cy, double maxDim) {
    final maxR = maxDim * 0.58;
    for (int i = 0; i < _dustPatches; i++) {
      final progress = (i * 0.0041 + 0.02).abs() % 0.92;
      final angle = (i * 0.61 - t * _twoPi) % _twoPi;
      final r = _spiralRadius(progress, maxR) + (i % 11 - 5) * 3;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      final size = 2.5 + (i % 5) * 1.2;
      final alpha = (0.06 + 0.12 * (1 - progress)).clamp(0.0, 1.0);
      // 星雲斑塊也帶一點顏色變化
      final dustPalette = [
        const Color(0xFF9F7BE8),
        const Color(0xFF7AC9FF),
        const Color(0xFFFF9FD6),
        const Color(0xFF7FFFE3),
      ];
      final c = dustPalette[i % dustPalette.length].withOpacity(alpha);
      final paint = Paint()
        ..color = c
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), size, paint);
    }
  }

  void _drawCore(Canvas canvas, double cx, double cy, double maxDim) {
    final r = maxDim * 0.055;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    final grad = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        const Color(0xFFf8f0ff),
        const Color(0xFFe8d8f8),
        const Color(0xFFc0a8e8),
        const Color(0xFF8060c0),
        const Color(0xFF302050),
        Colors.transparent,
      ],
      stops: const [0.0, 0.2, 0.4, 0.6, 0.85, 1.0],
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..shader = grad.createShader(rect),
    );
  }

  double _starX(int i, double w) {
    final s = (i * 0.131 + 1) * (i % 7 + 1);
    return (s * 0.17).abs() % 1.0 * w;
  }

  double _starY(int i, double h) {
    final s = (i * 0.077 + 2) * (i % 11 + 1);
    return (s * 0.23).abs() % 1.0 * h;
  }

  void _drawCoreStars(Canvas canvas, double cx, double cy, double maxDim) {
    final coreR = maxDim * 0.1;
    final baseRotation = -t * _twoPi;
    for (int i = 0; i < _coreStars; i++) {
      final angle = (i * 0.417 + baseRotation) % _twoPi;
      final r = (i * 0.013 + 0.02).abs() % 1.0 * coreR;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      final brightness = (1 - r / coreR).clamp(0.2, 1.0);
      final size = 0.8 + (i % 3) * 0.4;
      final paint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, brightness * 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), size, paint);
    }
  }

  void _drawArmStars(Canvas canvas, double cx, double cy, double maxDim) {
    final maxR = maxDim * 0.58;
    final baseRotation = -t * _twoPi;
    for (int i = 0; i < _armStars; i++) {
      final progress = (i * 0.0007 + 0.05).abs() % 0.95;
      final arm = i % _armCount;
      final baseAngle = (arm / _armCount) * _twoPi + baseRotation;
      final angle = baseAngle + _spiralAngle(progress) + (i % 5) * 0.15;
      final r = _spiralRadius(progress, maxR) + (i % 7 - 3) * 4;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      final brightness = (0.3 + 0.7 * (1 - progress)).clamp(0.0, 1.0);
      final size = 0.5 + (i % 4) * 0.35;
      // 各式顏色的星光點綴在螺旋臂上
      Color baseColor;
      switch (i % 6) {
        case 0:
          baseColor = const Color(0xFFFFE6FF); // 淡粉白
          break;
        case 1:
          baseColor = const Color(0xFFBFE3FF); // 淡藍白
          break;
        case 2:
          baseColor = const Color(0xFFFFD6C2); // 橘粉
          break;
        case 3:
          baseColor = const Color(0xFFC4FFE6); // 淡青綠
          break;
        case 4:
          baseColor = const Color(0xFFE4D4FF); // 淡紫
          break;
        default:
          baseColor = const Color(0xFFE8F0FF); // 淡冷白
      }
      final paint = Paint()
        ..color = baseColor.withOpacity(brightness * 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), size, paint);
    }
  }

  void _drawFieldStars(Canvas canvas, double w, double h) {
    for (int i = 0; i < _fieldStars; i++) {
      final x = _starX(i, w);
      final y = _starY(i, h);
      final brightness = 0.2 + (i % 10) / 10 * 0.6;
      final size = 0.4 + (i % 3) * 0.3;
      final paint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, brightness)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter oldDelegate) => oldDelegate.t != t;
}

class _TwinklePainter extends CustomPainter {
  _TwinklePainter({required this.t});

  final double t;
  static const int _starCount = 120;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    for (int i = 0; i < _starCount; i++) {
      final seed = (i * 1.0 + t * 3).abs();
      final x = (seed * 0.13 + i * 0.07) % 1.0 * w;
      final y = (seed * 0.17 + i * 0.11) % 1.0 * h;
      final phase = (t + i * 0.1) % 1.0;
      // 呼吸式閃爍：整體明暗隨時間起伏，再疊加每顆星自己的位相。
      final global = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
      final local = 0.5 + 0.5 * math.sin(phase * 2 * math.pi);
      final opacity = (0.08 + 0.7 * global * local).clamp(0.0, 1.0);
      final r = 1.0 + 0.5 * (i % 3);
      final paint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TwinklePainter oldDelegate) => oldDelegate.t != t;
}
