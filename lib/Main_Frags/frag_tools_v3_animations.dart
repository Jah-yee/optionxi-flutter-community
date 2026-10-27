import 'dart:math' as math;
import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';

// ALL tool animations live in this file.
// To add a new one: copy any animation class below, change what it draws,
// then register it in `ToolsRegistry` (tools_section.dart).

/// Brand colours used by the tool cards and animations.
/// Change them here and everything follows.
class ToolPalette {
  ToolPalette._();

  static const green = Color(0xFF22A06B);
  static const red = Color(0xFFE5566A);
  static const amber = Color(0xFFD97706);
  static const sky = Color(0xFF0EA5E9);
  static const blue = Color(0xFF3B82F6);
  static const violet = Color(0xFF7C5CFC);
  static const pink = Color(0xFFEC4899);
}

// ────────────────────────────────────────────────────────────
/// Runs forever and hands your builder a value `t` from 0.0 to 1.0.
///
/// Every tool animation is built on this, so a new animation is just:
///   LoopingAnimation(builder: (context, t) => ...draw something using t...)
///
/// - Pauses automatically when the tab/page is not visible (TickerMode).
/// - Shows a calm still frame if the phone has "Reduce motion" turned on.
class LoopingAnimation extends StatefulWidget {
  const LoopingAnimation({
    super.key,
    required this.builder,
    this.duration = const Duration(milliseconds: 3200),
  });

  final Widget Function(BuildContext context, double t) builder;
  final Duration duration;

  @override
  State<LoopingAnimation> createState() => _LoopingAnimationState();
}

class _LoopingAnimationState extends State<LoopingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    if (reduce) {
      _controller
        ..stop()
        ..value = 0.85; // a nice "finished" frame
    } else {
      _controller.repeat();
    }
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
      builder: (context, _) => widget.builder(context, _controller.value),
    );
  }
}

/// Turns the global loop value [t] into a local 0..1 value
/// that only moves between [begin] and [end].
///
/// Example: phase(t, 0.2, 0.6) is 0 until t=0.2, rises to 1 at t=0.6, then stays 1.
double phase(double t, double begin, double end,
    [Curve curve = Curves.linear]) {
  final v = ((t - begin) / (end - begin)).clamp(0.0, 1.0);
  return curve.transform(v);
}

// ────────────────────────────────────────────────────────────
/// A scan line moves down a list of stocks and ticks the ones that match.
class ScreenerAnimation extends StatelessWidget {
  const ScreenerAnimation({super.key});

  static const _matches = [true, false, true, false];
  static const _barWidths = [0.9, 0.65, 0.8, 0.55];

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 3400),
      builder: (context, t) {
        final scan = phase(t, 0.08, 0.72, Curves.easeInOut);
        final fadeOut = 1 - phase(t, 0.92, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, box) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      children: [
                        for (var i = 0; i < _matches.length; i++)
                          Expanded(
                            child: _Row(
                              scanned: scan > (i + 0.5) / _matches.length,
                              isMatch: _matches[i],
                              widthFactor: _barWidths[i],
                              mutedColor: muted,
                            ),
                          ),
                      ],
                    ),
                    Positioned(
                      top: scan * box.maxHeight - 1,
                      left: -6,
                      right: -6,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(colors: [
                            ToolPalette.green.withValues(alpha: 0),
                            ToolPalette.green,
                            ToolPalette.green.withValues(alpha: 0),
                          ]),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.scanned,
    required this.isMatch,
    required this.widthFactor,
    required this.mutedColor,
  });

  final bool scanned;
  final bool isMatch;
  final double widthFactor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (!scanned) {
      color = mutedColor.withValues(alpha: 0.28);
    } else {
      color = isMatch ? ToolPalette.green : mutedColor.withValues(alpha: 0.12);
    }

    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: scanned && isMatch
              ? const Icon(Icons.check_rounded, size: 10, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: widthFactor,
            child: Container(
              height: 7,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
/// A green "gainer" bar rises while a red "loser" bar falls, then they swap.
class MoversAnimation extends StatelessWidget {
  const MoversAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    return LoopingAnimation(
      duration: const Duration(milliseconds: 2800),
      builder: (context, t) {
        final wave = math.sin(t * 2 * math.pi); // -1..1
        final up = 0.55 + 0.35 * wave;
        final down = 0.55 - 0.35 * wave;

        return Center(
          child: SizedBox(
            height: 68,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _MoverBar(
                  color: ToolPalette.green,
                  icon: Icons.arrow_upward_rounded,
                  level: up,
                ),
                const SizedBox(width: 16),
                _MoverBar(
                  color: ToolPalette.red,
                  icon: Icons.arrow_downward_rounded,
                  level: down,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MoverBar extends StatelessWidget {
  const _MoverBar({
    required this.color,
    required this.icon,
    required this.level,
  });

  final Color color;
  final IconData icon;

  /// 0..1 – how tall the bar is.
  final double level;

  static const _maxBarHeight = 50.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(height: 4),
        Container(
          width: 20,
          height: _maxBarHeight * level,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
/// Two rules get "typed" one after another, then an alert bell pops and rings.
class CustomScreenerAnimation extends StatelessWidget {
  const CustomScreenerAnimation({super.key});

  static const _line1 = 'SMA > EMA';
  static const _line2 = '+ RSI < 30';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const total = 19; // _line1.length + _line2.length

    return LoopingAnimation(
      duration: const Duration(milliseconds: 4200),
      builder: (context, t) {
        final typing = phase(t, 0.05, 0.62);
        final typed = (typing * total).round();
        final stillTyping = typing < 1;
        final cursorOn = ((t * 14).floor() % 2) == 0;
        final cursor = stillTyping && cursorOn ? '▎' : '';

        final first = _line1.substring(0, math.min(typed, _line1.length));
        final second = typed > _line1.length
            ? _line2.substring(0, typed - _line1.length)
            : '';
        final onSecondLine = typed > _line1.length;

        final bellScale = phase(t, 0.68, 0.80, Curves.elasticOut);
        final ringing = phase(t, 0.76, 0.94);
        final bellAngle = math.sin(ringing * 28) * 0.35 * (1 - ringing);
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                child: Column(
                  children: [
                    _RuleChip(
                      text: first + (onSecondLine ? '' : cursor),
                      visible: typed > 0,
                      scheme: scheme,
                    ),
                    const SizedBox(height: 6),
                    _RuleChip(
                      text: second + (onSecondLine ? cursor : ''),
                      visible: onSecondLine,
                      scheme: scheme,
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 9,
                bottom: 8,
                child: Transform.scale(
                  scale: bellScale,
                  child: Transform.rotate(
                    angle: bellAngle,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: ToolPalette.amber,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({
    required this.text,
    required this.visible,
    required this.scheme,
  });

  final String text;
  final bool visible;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: visible ? 1 : 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          text.isEmpty ? ' ' : text,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 9.5,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
/// A price line climbs past a dashed level. The moment it crosses, a pulse
/// ring appears – just like a breakout alert.
class AlertsAnimation extends StatelessWidget {
  const AlertsAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 3400),
      builder: (context, t) {
        final draw = phase(t, 0.05, 0.62, Curves.easeInOut);
        final pulse = phase(t, 0.60, 0.92);
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: CustomPaint(
              size: Size.infinite,
              painter: _BreakoutPainter(
                draw: draw,
                pulse: pulse,
                levelColor: muted.withValues(alpha: 0.35),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BreakoutPainter extends CustomPainter {
  _BreakoutPainter({
    required this.draw,
    required this.pulse,
    required this.levelColor,
  });

  final double draw;
  final double pulse;
  final Color levelColor;

  static const _levelY = 0.45;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Dashed "breakout level".
    final dash = Paint()
      ..color = levelColor
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final y = h * _levelY;
    for (double x = 0; x < w; x += 7) {
      canvas.drawLine(Offset(x, y), Offset(x + 3.5, y), dash);
    }

    // Price path.
    final path = Path()
      ..moveTo(w * 0.02, h * 0.86)
      ..cubicTo(w * 0.35, h * 0.88, w * 0.5, h * 0.30, w * 0.98, h * 0.14);

    final PathMetric metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * draw);

    canvas.drawPath(
      drawn,
      Paint()
        ..color = ToolPalette.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );

    // Dot at the tip of the line.
    final tangent = metric.getTangentForOffset(metric.length * draw);
    if (tangent == null) return;
    final tip = tangent.position;

    if (tip.dy < y && pulse > 0) {
      canvas.drawCircle(
        tip,
        5 + 13 * pulse,
        Paint()
          ..color = ToolPalette.green.withValues(alpha: 0.30 * (1 - pulse)),
      );
    }
    canvas.drawCircle(tip, 4, Paint()..color = ToolPalette.green);
    canvas.drawCircle(tip, 1.8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_BreakoutPainter old) =>
      old.draw != draw || old.pulse != pulse || old.levelColor != levelColor;
}

// ────────────────────────────────────────────────────────────
/// A shaded "normal range" band scrolls by with a price line inside it.
/// When the price steps outside the band, a dot lights up at the edge:
/// green for a move up, red for a move down.
class BollingerAnimation extends StatelessWidget {
  const BollingerAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    return LoopingAnimation(
      duration: const Duration(milliseconds: 4200),
      builder: (context, t) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: CustomPaint(
            size: Size.infinite,
            painter: _BollingerPainter(phase: t * 2 * math.pi),
          ),
        );
      },
    );
  }
}

class _BollingerPainter extends CustomPainter {
  _BollingerPainter({required this.phase});

  final double phase;

  static const _steps = 36;

  // Band half-width and price offset (both as a share of the height).
  double _halfBand(double a, double h) => h * (0.16 + 0.035 * math.sin(a));
  double _offset(double a, double h) => h * 0.23 * math.sin(a + 0.9);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final mid = h / 2;

    final upper = <Offset>[];
    final lower = <Offset>[];
    final price = <Offset>[];

    for (var i = 0; i <= _steps; i++) {
      final xf = i / _steps;
      final x = xf * w;
      final a = xf * 2 * math.pi * 1.2 + phase;
      final half = _halfBand(a, h);
      upper.add(Offset(x, mid - half));
      lower.add(Offset(x, mid + half));
      price.add(Offset(x, mid + _offset(a, h)));
    }

    // Shaded band.
    final band = Path()..moveTo(upper.first.dx, upper.first.dy);
    for (final p in upper.skip(1)) {
      band.lineTo(p.dx, p.dy);
    }
    for (final p in lower.reversed) {
      band.lineTo(p.dx, p.dy);
    }
    band.close();
    canvas.drawPath(
      band,
      Paint()..color = ToolPalette.violet.withValues(alpha: 0.14),
    );

    // Band edges.
    final edge = Paint()
      ..color = ToolPalette.violet.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(_line(upper), edge);
    canvas.drawPath(_line(lower), edge);

    // Price line.
    canvas.drawPath(
      _line(price),
      Paint()
        ..color = ToolPalette.violet
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Breakout dot on the right edge, only when price is outside the band.
    final a = 2 * math.pi * 1.2 + phase;
    final off = _offset(a, h);
    final half = _halfBand(a, h);
    if (off.abs() > half) {
      final color = off < 0 ? ToolPalette.green : ToolPalette.red;
      final tip = price.last;
      canvas.drawCircle(tip, 8, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(tip, 4, Paint()..color = color);
    }
  }

  Path _line(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_BollingerPainter old) => old.phase != phase;
}

// ────────────────────────────────────────────────────────────
/// One stock collects signal dots, one from each screener that picked it.
/// With 3 dots it climbs above the others to rank #1 and gets a star.
class TopPicksAnimation extends StatelessWidget {
  const TopPicksAnimation({super.key});

  static const _signalColors = [
    ToolPalette.green,
    ToolPalette.blue,
    ToolPalette.amber,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 4200),
      builder: (context, t) {
        final dots = [
          phase(t, 0.08, 0.18, Curves.elasticOut),
          phase(t, 0.24, 0.34, Curves.elasticOut),
          phase(t, 0.40, 0.50, Curves.elasticOut),
        ];
        final move = phase(t, 0.52, 0.74, Curves.easeInOutCubic);
        final glow = phase(t, 0.74, 0.86);
        final star = phase(t, 0.74, 0.88, Curves.elasticOut);
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, box) {
                final slotH = box.maxHeight / 3;

                Widget slot(double index, Widget child) => Positioned(
                      top: index * slotH + 2,
                      left: 0,
                      right: 0,
                      height: slotH - 4,
                      child: child,
                    );

                final dim = scheme.onSurface.withValues(alpha: 0.28);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Other stocks: 1 signal each, slide down when the winner climbs.
                    slot(
                      move,
                      _PickRow(
                        widthFactor: 0.6,
                        scheme: scheme,
                        dots: [_dot(dim, 1)],
                      ),
                    ),
                    slot(
                      1 + move,
                      _PickRow(
                        widthFactor: 0.75,
                        scheme: scheme,
                        dots: [_dot(dim, 1)],
                      ),
                    ),
                    // The stock that is picked by many screeners (drawn last = on top).
                    slot(
                      2 * (1 - move),
                      _PickRow(
                        widthFactor: 0.85,
                        scheme: scheme,
                        glow: glow,
                        starScale: star,
                        dots: [
                          for (var i = 0; i < 3; i++)
                            _dot(_signalColors[i], dots[i]),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  static Widget _dot(Color color, double scale) => Padding(
        padding: const EdgeInsets.only(left: 3),
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      );
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.widthFactor,
    required this.scheme,
    required this.dots,
    this.glow = 0,
    this.starScale = 0,
  });

  final double widthFactor;
  final ColorScheme scheme;
  final List<Widget> dots;
  final double glow; // 0..1 highlight strength
  final double starScale;

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(
      scheme.surface,
      ToolPalette.pink.withValues(alpha: 0.16),
      glow,
    )!;
    final border = Color.lerp(scheme.outlineVariant, ToolPalette.pink, glow)!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: widthFactor,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              ...dots,
            ],
          ),
        ),
        if (starScale > 0)
          Positioned(
            top: -7,
            right: -6,
            child: Transform.scale(
              scale: starScale,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: ToolPalette.pink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star_rounded,
                    size: 11, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
/// Option chain: CALL rows on the left, PUT rows on the right, strike in the
/// middle. A highlight moves across strikes and the ATM row glows.
class OptionChainAnimation extends StatelessWidget {
  const OptionChainAnimation({super.key});

  static const _callBars = [0.9, 0.7, 0.45, 0.25, 0.15];
  static const _putBars = [0.15, 0.3, 0.5, 0.75, 0.9];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 4000),
      builder: (context, t) {
        final grow = phase(t, 0.05, 0.40, Curves.easeOutCubic);
        final scan = phase(t, 0.40, 0.85, Curves.easeInOut);
        final fadeOut = 1 - phase(t, 0.94, 1.0);
        final active = (scan * (_callBars.length - 1)).round();
        final scanning = t > 0.40;

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              children: [
                for (var i = 0; i < _callBars.length; i++)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 1.5),
                      decoration: BoxDecoration(
                        color: scanning && i == active
                            ? ToolPalette.blue.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          // CALL side (grows right to left)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FractionallySizedBox(
                                widthFactor: _callBars[i] * grow,
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: ToolPalette.green,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Strike
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == 2
                                  ? ToolPalette.blue
                                  : scheme.onSurface.withValues(alpha: 0.2),
                            ),
                          ),
                          // PUT side (grows left to right)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: _putBars[i] * grow,
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: ToolPalette.red,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────
/// Option budget: a slider handle moves to set a budget. Options priced
/// above it dim out, the ones that fit get a green tick.
class OptionBudgetAnimation extends StatelessWidget {
  const OptionBudgetAnimation({super.key});

  // Premium of each option as a share of the track (0..1).
  static const _prices = [0.22, 0.45, 0.68, 0.9];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 4000),
      builder: (context, t) {
        // Budget goes 0.3 -> 0.78 -> 0.5
        final up = phase(t, 0.10, 0.50, Curves.easeInOut);
        final down = phase(t, 0.60, 0.85, Curves.easeInOut);
        final budget = 0.3 + 0.48 * up - 0.28 * down;
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              children: [
                // Option chips
                Expanded(
                  child: Column(
                    children: [
                      for (final p in _prices)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: _BudgetRow(
                              price: p,
                              fits: p <= budget,
                              scheme: scheme,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Slider
                LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth;
                    return SizedBox(
                      height: 14,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: scheme.onSurface.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Container(
                            height: 4,
                            width: w * budget,
                            decoration: BoxDecoration(
                              color: ToolPalette.amber,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Positioned(
                            left: w * budget - 7,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: ToolPalette.amber, width: 3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.price,
    required this.fits,
    required this.scheme,
  });

  final double price;
  final bool fits;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final color =
        fits ? ToolPalette.green : scheme.onSurface.withValues(alpha: 0.18);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: fits ? 1 : 0.55,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: fits
                ? const Icon(Icons.check_rounded, size: 9, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: price,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
/// Option OI: cycles through the 4 OI + price combinations.
/// Long buildup (OI up, price up), short buildup (OI up, price down),
/// short covering (OI down, price up), long unwinding (OI down, price down).
class OptionOiAnimation extends StatelessWidget {
  const OptionOiAnimation({super.key});

  static const _labels = [
    'LONG BUILDUP',
    'SHORT BUILDUP',
    'SHORT COVER',
    'LONG UNWIND'
  ];
  static const _colors = [
    ToolPalette.green,
    ToolPalette.red,
    ToolPalette.sky,
    ToolPalette.amber,
  ];
  // (oiUp, priceUp)
  static const _dirs = [
    (true, true),
    (true, false),
    (false, true),
    (false, false),
  ];

  @override
  Widget build(BuildContext context) {
    // final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 6400),
      builder: (context, t) {
        final slot = (t * 4).floor().clamp(0, 3);
        final local = (t * 4) - slot; // 0..1 inside this step
        final grow = Curves.easeOutCubic.transform(phase(local, 0.0, 0.5));
        final badge = Curves.easeOutBack.transform(phase(local, 0.45, 0.7));
        final fade = 1 - phase(local, 0.9, 1.0);

        final (oiUp, priceUp) = _dirs[slot];
        final color = _colors[slot];

        // OI bar height, from a baseline of 0.5
        final oiLevel = 0.5 + (oiUp ? 0.4 : -0.3) * grow;
        // Price arrow offset
        final arrowShift = (priceUp ? -1 : 1) * 6 * grow;

        return Opacity(
          opacity: fade,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // OI bar
                      Container(
                        width: 20,
                        height: 44 * oiLevel,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Price arrow
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Transform.translate(
                          offset: Offset(0, arrowShift),
                          child: Icon(
                            priceUp
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            size: 26,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Transform.scale(
                  scale: badge,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      _labels[slot],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────
/// Two lanes: NIFTY and BANK NIFTY. Each has a dashed day-high and day-low.
/// The price line draws in. NIFTY pushes above its high (green pulse),
/// then BANK NIFTY drops below its low (red pulse).
class IndexBreakoutAnimation extends StatelessWidget {
  const IndexBreakoutAnimation({super.key});

  // Normalised path points: x 0..1, y 0..1 (0 = top of the lane).
  // The high level sits at y=0.28 and the low level at y=0.72.
  static const _niftyPts = [
    Offset(0.00, 0.58),
    Offset(0.18, 0.46),
    Offset(0.36, 0.62),
    Offset(0.56, 0.42),
    Offset(0.76, 0.32),
    Offset(1.00, 0.06),
  ];
  static const _bankPts = [
    Offset(0.00, 0.42),
    Offset(0.18, 0.60),
    Offset(0.36, 0.40),
    Offset(0.56, 0.58),
    Offset(0.76, 0.66),
    Offset(1.00, 0.96),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 4200),
      builder: (context, t) {
        final niftyDraw = phase(t, 0.05, 0.45, Curves.easeInOut);
        final niftyPulse = phase(t, 0.42, 0.75);
        final bankDraw = phase(t, 0.25, 0.65, Curves.easeInOut);
        final bankPulse = phase(t, 0.62, 0.92);
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              children: [
                Expanded(
                  child: _IndexLane(
                    label: 'NF',
                    points: _niftyPts,
                    draw: niftyDraw,
                    pulse: niftyPulse,
                    breakUp: true,
                    scheme: scheme,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: _IndexLane(
                    label: 'BN',
                    points: _bankPts,
                    draw: bankDraw,
                    pulse: bankPulse,
                    breakUp: false,
                    scheme: scheme,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IndexLane extends StatelessWidget {
  const _IndexLane({
    required this.label,
    required this.points,
    required this.draw,
    required this.pulse,
    required this.breakUp,
    required this.scheme,
  });

  final String label;
  final List<Offset> points;
  final double draw;
  final double pulse;
  final bool breakUp;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _IndexLanePainter(
              points: points,
              draw: draw,
              pulse: pulse,
              breakUp: breakUp,
              levelColor: scheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ),
      ],
    );
  }
}

class _IndexLanePainter extends CustomPainter {
  _IndexLanePainter({
    required this.points,
    required this.draw,
    required this.pulse,
    required this.breakUp,
    required this.levelColor,
  });

  final List<Offset> points;
  final double draw;
  final double pulse;
  final bool breakUp;
  final Color levelColor;

  static const _highY = 0.28;
  static const _lowY = 0.72;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final highY = h * _highY;
    final lowY = h * _lowY;

    // Dashed day-high and day-low.
    final dash = Paint()
      ..color = levelColor
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (double x = 0; x < w; x += 6) {
      canvas.drawLine(Offset(x, highY), Offset(x + 3, highY), dash);
      canvas.drawLine(Offset(x, lowY), Offset(x + 3, lowY), dash);
    }

    // Price path.
    final path = Path()..moveTo(points.first.dx * w, points.first.dy * h);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx * w, p.dy * h);
    }

    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * draw);

    canvas.drawPath(
      drawn,
      Paint()
        ..color = ToolPalette.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dot at the tip. It turns green / red once it is past the level.
    final tangent = metric.getTangentForOffset(metric.length * draw);
    if (tangent == null) return;
    final tip = tangent.position;

    final broke = breakUp ? tip.dy < highY : tip.dy > lowY;
    final color = broke
        ? (breakUp ? ToolPalette.green : ToolPalette.red)
        : ToolPalette.blue;

    if (broke && pulse > 0) {
      canvas.drawCircle(
        tip,
        4 + 10 * pulse,
        Paint()..color = color.withValues(alpha: 0.30 * (1 - pulse)),
      );
    }
    canvas.drawCircle(tip, 3.6, Paint()..color = color);
    canvas.drawCircle(tip, 1.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_IndexLanePainter old) =>
      old.draw != draw ||
      old.pulse != pulse ||
      old.breakUp != breakUp ||
      old.levelColor != levelColor;
}

// ────────────────────────────────────────────────────────────
/// Strategy backtest: a price line draws in, signal markers pop on it
/// (SMA crosses EMA), then each signal gets checked against the next candle
/// window: a green tick if it hit, a red cross if it missed. A small accuracy
/// bar fills at the bottom, and a PRO badge sits in the corner.
class StrategyBacktestAnimation extends StatelessWidget {
  const StrategyBacktestAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 4600),
      builder: (context, t) {
        final draw = phase(t, 0.04, 0.40, Curves.easeInOut);
        final s1 = phase(t, 0.18, 0.26, Curves.elasticOut);
        final s2 = phase(t, 0.30, 0.38, Curves.elasticOut);
        final s3 = phase(t, 0.42, 0.50, Curves.elasticOut);
        final r1 = phase(t, 0.54, 0.62, Curves.elasticOut);
        final r2 = phase(t, 0.64, 0.72, Curves.elasticOut);
        final r3 = phase(t, 0.74, 0.82, Curves.elasticOut);
        final acc = phase(t, 0.54, 0.84, Curves.easeOutCubic);
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _BacktestPainter(
                      draw: draw,
                      signals: [s1, s2, s3],
                      results: [r1, r2, r3],
                      lineColor: ToolPalette.green,
                      mutedColor: scheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Accuracy bar: fills to ~67 % (2 of 3 hit).
                Container(
                  height: 5,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 0.67 * acc,
                    child: Container(
                      decoration: BoxDecoration(
                        color: ToolPalette.green,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BacktestPainter extends CustomPainter {
  _BacktestPainter({
    required this.draw,
    required this.signals,
    required this.results,
    required this.lineColor,
    required this.mutedColor,
  });

  final double draw;
  final List<double> signals; // 0..1 pop-in of each signal marker
  final List<double> results; // 0..1 pop-in of each tick / cross
  final Color lineColor;
  final Color mutedColor;

  // Signal x positions (share of width) and whether each one "hit".
  static const _sx = [0.22, 0.52, 0.78];
  static const _hit = [true, false, true];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0, h * 0.70)
      ..cubicTo(w * 0.12, h * 0.80, w * 0.16, h * 0.40, w * 0.26, h * 0.46)
      ..cubicTo(w * 0.38, h * 0.54, w * 0.42, h * 0.28, w * 0.54, h * 0.42)
      ..cubicTo(w * 0.64, h * 0.54, w * 0.68, h * 0.30, w * 0.80, h * 0.34)
      ..cubicTo(w * 0.90, h * 0.38, w * 0.95, h * 0.20, w, h * 0.16);

    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * draw),
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    for (var i = 0; i < _sx.length; i++) {
      if (signals[i] <= 0) continue;
      final tan = metric.getTangentForOffset(metric.length * _sx[i]);
      if (tan == null) continue;
      final p = tan.position;

      // The "next 5 min" window after the signal.
      final win = results[i];
      if (win > 0) {
        final rect = Rect.fromLTWH(p.dx, 0, w * 0.16, h);
        canvas.drawRect(
          rect,
          Paint()
            ..color = (_hit[i] ? ToolPalette.green : ToolPalette.red)
                .withValues(alpha: 0.10 * win),
        );
      }

      // Signal dot.
      canvas.drawCircle(p, 4.5 * signals[i], Paint()..color = ToolPalette.blue);
      canvas.drawCircle(p, 1.8 * signals[i], Paint()..color = Colors.white);

      // Result badge above the signal.
      if (win > 0) {
        final c = _hit[i] ? ToolPalette.green : ToolPalette.red;
        final badge = Offset(p.dx, p.dy - 13);
        canvas.drawCircle(badge, 6.5 * win, Paint()..color = c);
        final mark = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * win
          ..strokeCap = StrokeCap.round;
        if (_hit[i]) {
          canvas.drawPath(
            Path()
              ..moveTo(badge.dx - 2.6, badge.dy)
              ..lineTo(badge.dx - 0.6, badge.dy + 2)
              ..lineTo(badge.dx + 2.8, badge.dy - 2),
            mark,
          );
        } else {
          canvas.drawLine(Offset(badge.dx - 2.2, badge.dy - 2.2),
              Offset(badge.dx + 2.2, badge.dy + 2.2), mark);
          canvas.drawLine(Offset(badge.dx + 2.2, badge.dy - 2.2),
              Offset(badge.dx - 2.2, badge.dy + 2.2), mark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BacktestPainter old) =>
      old.draw != draw ||
      old.signals != signals ||
      old.results != results ||
      old.lineColor != lineColor ||
      old.mutedColor != mutedColor;
}

// ────────────────────────────────────────────────────────────
/// Option testing: a Nifty line is drawn up to a "BUY" marker. A virtual
/// position is placed, then the chart is dragged forward to a new point
/// and a P&L chip pops up (green when it ends higher).
class OptionTestingAnimation extends StatelessWidget {
  const OptionTestingAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 5000),
      builder: (context, t) {
        final base = phase(t, 0.04, 0.34, Curves.easeInOut); // line to entry
        final buy = phase(t, 0.34, 0.44, Curves.elasticOut); // BUY marker
        final move = phase(t, 0.48, 0.80, Curves.easeInOut); // drag forward
        final pnl = phase(t, 0.78, 0.90, Curves.easeOutBack); // P&L chip
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OptionTestPainter(
                      base: base,
                      buy: buy,
                      move: move,
                      lineColor: ToolPalette.violet,
                      muted: scheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Transform.scale(
                    scale: pnl,
                    alignment: Alignment.bottomRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: ToolPalette.green,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '+₹1,250',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OptionTestPainter extends CustomPainter {
  _OptionTestPainter({
    required this.base,
    required this.buy,
    required this.move,
    required this.lineColor,
    required this.muted,
  });

  final double base; // 0..1 line drawn up to entry
  final double buy; // 0..1 marker pop
  final double move; // 0..1 extension after entry
  final Color lineColor;
  final Color muted;

  static const _entryAt = 0.50; // share of path length where BUY happens

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0, h * 0.62)
      ..cubicTo(w * 0.10, h * 0.78, w * 0.18, h * 0.40, w * 0.30, h * 0.52)
      ..cubicTo(w * 0.40, h * 0.62, w * 0.44, h * 0.50, w * 0.50, h * 0.54)
      ..cubicTo(w * 0.62, h * 0.60, w * 0.70, h * 0.30, w * 0.82, h * 0.26)
      ..cubicTo(w * 0.90, h * 0.24, w * 0.95, h * 0.14, w, h * 0.10);

    final metric = path.computeMetrics().first;
    final entryLen = metric.length * _entryAt;

    // Visible length: up to entry, then extends forward while "moving".
    final visible = entryLen * base + (metric.length - entryLen) * move;

    // Faint future path hint (ghost) so the drag feels like a chart move.
    if (buy > 0) {
      canvas.drawPath(
        metric.extractPath(entryLen, metric.length),
        Paint()
          ..color = muted.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    canvas.drawPath(
      metric.extractPath(0, visible),
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // Entry marker with a vertical guide and BUY flag.
    final entry = metric.getTangentForOffset(entryLen)?.position;
    if (entry != null && buy > 0) {
      canvas.drawLine(
        Offset(entry.dx, entry.dy),
        Offset(entry.dx, h),
        Paint()
          ..color = muted
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(entry, 4.5 * buy, Paint()..color = ToolPalette.blue);
      canvas.drawCircle(entry, 1.8 * buy, Paint()..color = Colors.white);

      final flag = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(entry.dx, entry.dy - 14), width: 22, height: 11),
        const Radius.circular(3),
      );
      canvas.save();
      canvas.translate(entry.dx, entry.dy - 14);
      canvas.scale(buy);
      canvas.translate(-entry.dx, -(entry.dy - 14));
      canvas.drawRRect(flag, Paint()..color = ToolPalette.blue);
      final tp = TextPainter(
        text: const TextSpan(
          text: 'BUY',
          style: TextStyle(
              fontSize: 7, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(entry.dx - tp.width / 2, entry.dy - 14 - tp.height / 2));
      canvas.restore();
    }

    // Tip dot while the chart is moving forward.
    if (move > 0) {
      final tip = metric.getTangentForOffset(visible)?.position;
      if (tip != null) {
        canvas.drawCircle(tip, 3.8, Paint()..color = ToolPalette.green);
        canvas.drawCircle(tip, 1.5, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(_OptionTestPainter old) =>
      old.base != base ||
      old.buy != buy ||
      old.move != move ||
      old.lineColor != lineColor ||
      old.muted != muted;
}

// ────────────────────────────────────────────────────────────
/// Market news: a pulsing LIVE badge sits on top while headline cards slide
/// in one by one. The first card then lights up with a green trend chip,
/// like a news item that is moving a stock.
class NewsAnimation extends StatelessWidget {
  const NewsAnimation({super.key});

  static const _thumbColors = [
    ToolPalette.green,
    ToolPalette.blue,
    ToolPalette.amber,
  ];
  static const _titleWidths = [0.95, 0.8, 0.9];
  static const _subWidths = [0.6, 0.5, 0.65];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 4200),
      builder: (context, t) {
        final pulse = (t * 4) % 1.0; // LIVE dot pulses ~4x per loop
        final chip = phase(t, 0.62, 0.74, Curves.elasticOut);
        final glow = phase(t, 0.60, 0.70);
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _LiveBadge(pulse: pulse),
                const SizedBox(height: 6),
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _NewsRow(
                        progress: phase(t, 0.10 + i * 0.14, 0.28 + i * 0.14,
                            Curves.easeOutCubic),
                        thumbColor: _thumbColors[i],
                        titleWidth: _titleWidths[i],
                        subWidth: _subWidths[i],
                        glow: i == 0 ? glow : 0,
                        chip: i == 0 ? chip : 0,
                        scheme: scheme,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.pulse});

  final double pulse; // 0..1 loop

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: ToolPalette.red.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 5 + 7 * pulse,
                      height: 5 + 7 * pulse,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ToolPalette.red
                            .withValues(alpha: 0.35 * (1 - pulse)),
                      ),
                    ),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: ToolPalette.red,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              const Text(
                'LIVE',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: ToolPalette.red,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        const Icon(Icons.article_rounded, size: 14, color: ToolPalette.sky),
      ],
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({
    required this.progress,
    required this.thumbColor,
    required this.titleWidth,
    required this.subWidth,
    required this.glow,
    required this.chip,
    required this.scheme,
  });

  final double progress; // 0..1 slide-in
  final Color thumbColor;
  final double titleWidth;
  final double subWidth;
  final double glow; // 0..1 highlight
  final double chip; // 0..1 trend chip pop
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(
      scheme.surface,
      ToolPalette.sky.withValues(alpha: 0.16),
      glow,
    )!;
    final border = Color.lerp(scheme.outlineVariant, ToolPalette.sky, glow)!;

    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(20 * (1 - progress), 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: thumbColor.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: titleWidth,
                      child: Container(
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2.5),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: subWidth,
                      child: Container(
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (chip > 0)
                Transform.scale(
                  scale: chip,
                  child: const Icon(
                    Icons.trending_up_rounded,
                    size: 11,
                    color: ToolPalette.green,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
/// Sector pulse: a mini version of the page. The breadth bar fills (mostly
/// red, a little green), sector rows slide in, the top row turns "hot"
/// (amber border + flame), then the Going up / Going down toggle flips and
/// every row switches from green up-trend to red down-trend.
class SectorPulseAnimation extends StatelessWidget {
  const SectorPulseAnimation({super.key});

  static const _nameWidths = [0.85, 0.65, 0.75];
  static const _subWidths = [0.55, 0.7, 0.5];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 5000),
      builder: (context, t) {
        final breadth = phase(t, 0.04, 0.22, Curves.easeOutCubic);
        final hot = phase(t, 0.46, 0.56);
        final flame = phase(t, 0.48, 0.60, Curves.elasticOut);
        final flip = phase(t, 0.68, 0.80, Curves.easeInOut); // 0 up, 1 down
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        final color = Color.lerp(ToolPalette.green, ToolPalette.red, flip)!;
        final isDown = flip > 0.5;

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                // Breadth bar: small green share, rest red.
                Container(
                  height: 5,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: ToolPalette.red.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 0.18 * breadth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: ToolPalette.green,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _SectorToggle(flip: flip, scheme: scheme),
                const SizedBox(height: 5),
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: _SectorRow(
                        progress: phase(t, 0.14 + i * 0.09, 0.30 + i * 0.09,
                            Curves.easeOutCubic),
                        color: color,
                        isDown: isDown,
                        nameWidth: _nameWidths[i],
                        subWidth: _subWidths[i],
                        hot: i == 0 ? hot * (1 - flip) : 0,
                        flame: i == 0 ? flame * (1 - flip) : 0,
                        scheme: scheme,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectorToggle extends StatelessWidget {
  const _SectorToggle({required this.flip, required this.scheme});

  final double flip; // 0 = Going up, 1 = Going down
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        children: [
          // Sliding thumb.
          Align(
            alignment: Alignment(-1 + 2 * flip, 0),
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
          // Tiny up / down markers.
          Row(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: 14,
                    height: 3,
                    decoration: BoxDecoration(
                      color:
                          ToolPalette.green.withValues(alpha: 1 - 0.55 * flip),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Container(
                    width: 14,
                    height: 3,
                    decoration: BoxDecoration(
                      color:
                          ToolPalette.red.withValues(alpha: 0.45 + 0.55 * flip),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectorRow extends StatelessWidget {
  const _SectorRow({
    required this.progress,
    required this.color,
    required this.isDown,
    required this.nameWidth,
    required this.subWidth,
    required this.hot,
    required this.flame,
    required this.scheme,
  });

  final double progress; // 0..1 slide-in
  final Color color; // green -> red
  final bool isDown;
  final double nameWidth;
  final double subWidth;
  final double hot; // 0..1 amber highlight
  final double flame; // 0..1 flame pop
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final border = Color.lerp(scheme.outlineVariant, ToolPalette.amber, hot)!;

    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - progress)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              // Round trend icon, like the page cards.
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18),
                ),
                child: Icon(
                  isDown
                      ? Icons.trending_down_rounded
                      : Icons.trending_up_rounded,
                  size: 8,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              // Name + sub line.
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: nameWidth,
                              child: Container(
                                height: 3.5,
                                decoration: BoxDecoration(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.30),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (flame > 0)
                          SizedBox(
                            width: 9,
                            height: 4,
                            child: OverflowBox(
                              maxHeight: 9,
                              child: Transform.scale(
                                scale: flame,
                                child: const Icon(
                                  Icons.local_fire_department_rounded,
                                  size: 9,
                                  color: ToolPalette.amber,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: subWidth,
                        child: Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: scheme.onSurface.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Percent chip.
              Container(
                width: 14,
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
/// Deploy Algo: three sources (</> custom code, F&O, index) drop in and fly
/// into a cloud. Gears spin inside the cloud while it runs your algo with a
/// progress bar and glow. A lightning bolt fires when the condition is met,
/// and a PRO notification card slides in while the bell rings.
class DeployAlgoAnimation extends StatelessWidget {
  const DeployAlgoAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 6400),
      builder: (context, t) {
        final cloudIn = phase(t, 0.0, 0.10, Curves.easeOutBack);
        final active = phase(t, 0.34, 0.46, Curves.easeOut);
        final progress = phase(t, 0.38, 0.60);
        final spin = t * math.pi * 16;

        final flash =
            phase(t, 0.60, 0.63) * (1 - phase(t, 0.63, 0.70, Curves.easeOut));
        final bolt = phase(t, 0.60, 0.66, Curves.elasticOut);
        final boltFade = phase(t, 0.60, 0.63) * (1 - phase(t, 0.72, 0.78));

        final note = phase(t, 0.66, 0.78, Curves.easeOutBack);
        final ring = phase(t, 0.72, 0.88);
        final bellAngle = math.sin(ring * math.pi * 6) * 0.45 * (1 - ring);
        final pro = phase(t, 0.82, 0.90, Curves.elasticOut);

        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final h = box.maxHeight;
                final cx = w / 2;

                final cw = w * 0.64;
                final ch = cw * 0.62;
                const cloudTop = 12.0;
                final cloudCy = cloudTop + ch / 2;

                // Source chip that drops in, then flies into the cloud.
                Widget source(
                    int i, String label, Color color, double dxFactor) {
                  final appear = phase(
                      t, 0.03 + i * 0.05, 0.11 + i * 0.05, Curves.easeOutBack);
                  final fly = phase(
                      t, 0.22 + i * 0.05, 0.38 + i * 0.05, Curves.easeInCubic);
                  final x = cx + (w * dxFactor) * (1 - fly) - 13;
                  final endY = cloudCy - 5;
                  final y = 1 + (endY - 1) * fly;
                  return Positioned(
                    left: x,
                    top: y,
                    width: 26,
                    child: Opacity(
                      opacity: (appear * (1 - fly * fly)).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: appear * (1 - 0.7 * fly),
                        child: Center(
                          child: _AlgoSourceChip(label: label, color: color),
                        ),
                      ),
                    ),
                  );
                }

                final strokeBase = Color.lerp(
                    scheme.outlineVariant, ToolPalette.blue, active)!;
                final stroke =
                    Color.lerp(strokeBase, ToolPalette.amber, flash)!;
                final fill = Color.alphaBlend(
                  Color.lerp(ToolPalette.blue, ToolPalette.amber, flash)!
                      .withValues(alpha: 0.14 * active + 0.18 * flash),
                  scheme.surface,
                );
                final glow =
                    (0.5 * active * (0.6 + 0.4 * math.sin(t * math.pi * 20)) +
                            0.8 * flash)
                        .clamp(0.0, 1.0);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Sources (drawn first, so the cloud covers them as they enter)
                    source(0, '</>', ToolPalette.pink, -0.34),
                    source(1, 'F&O', ToolPalette.violet, 0.0),
                    source(2, 'INDEX', ToolPalette.blue, 0.34),

                    // Cloud
                    Positioned(
                      left: cx - cw / 2,
                      top: cloudTop,
                      width: cw,
                      height: ch,
                      child: Transform.scale(
                        scale: 0.85 + 0.15 * cloudIn,
                        child: Opacity(
                          opacity: cloudIn.clamp(0.0, 1.0),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _CloudPainter(
                                    fill: fill,
                                    stroke: stroke,
                                    glow: glow,
                                    glowColor: Color.lerp(ToolPalette.blue,
                                        ToolPalette.amber, flash)!,
                                  ),
                                ),
                              ),
                              // Gears
                              Positioned(
                                left: cw * 0.28,
                                top: ch * 0.22,
                                child: Opacity(
                                  opacity: active,
                                  child: Transform.rotate(
                                    angle: spin,
                                    child: const Icon(
                                      Icons.settings_rounded,
                                      size: 12,
                                      color: ToolPalette.blue,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: cw * 0.50,
                                top: ch * 0.40,
                                child: Opacity(
                                  opacity: active,
                                  child: Transform.rotate(
                                    angle: -spin * 1.3,
                                    child: const Icon(
                                      Icons.settings_rounded,
                                      size: 8,
                                      color: ToolPalette.violet,
                                    ),
                                  ),
                                ),
                              ),
                              // Progress bar
                              Positioned(
                                left: cw * 0.25,
                                top: ch * 0.78,
                                width: cw * 0.50,
                                height: 2.5,
                                child: Opacity(
                                  opacity: active,
                                  child: Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                      FractionallySizedBox(
                                        widthFactor: progress,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: ToolPalette.green,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Trigger bolt between cloud and notification
                    Positioned(
                      left: cx - 8,
                      top: cloudTop + ch - 1,
                      width: 16,
                      height: 16,
                      child: Opacity(
                        opacity: boltFade.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: bolt,
                          child: const Icon(
                            Icons.bolt_rounded,
                            size: 15,
                            color: ToolPalette.amber,
                          ),
                        ),
                      ),
                    ),

                    // Notification card
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 20,
                      child: Opacity(
                        opacity: note.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - note)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: ToolPalette.amber
                                        .withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Transform.rotate(
                                    angle: bellAngle,
                                    child: const Icon(
                                      Icons.notifications_active_rounded,
                                      size: 9,
                                      color: ToolPalette.amber,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      FractionallySizedBox(
                                        widthFactor: 0.8,
                                        child: Container(
                                          height: 3.5,
                                          decoration: BoxDecoration(
                                            color: scheme.onSurface
                                                .withValues(alpha: 0.45),
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      FractionallySizedBox(
                                        widthFactor: 0.5,
                                        child: Container(
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color: scheme.onSurface
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Transform.scale(
                                  scale: pro,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 3, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: ToolPalette.amber,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text(
                                      'PRO',
                                      style: TextStyle(
                                        fontSize: 5.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _AlgoSourceChip extends StatelessWidget {
  const _AlgoSourceChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 6,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _CloudPainter extends CustomPainter {
  _CloudPainter({
    required this.fill,
    required this.stroke,
    required this.glow,
    required this.glowColor,
  });

  final Color fill;
  final Color stroke;
  final double glow; // 0..1
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final base = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.02, h * 0.42, w * 0.96, h * 0.56),
        Radius.circular(h * 0.28),
      ));
    final bumpLeft = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(w * 0.34, h * 0.46), radius: h * 0.30));
    final bumpRight = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(w * 0.60, h * 0.38), radius: h * 0.36));

    final cloud = Path.combine(
      PathOperation.union,
      Path.combine(PathOperation.union, base, bumpLeft),
      bumpRight,
    );

    if (glow > 0) {
      canvas.drawPath(
        cloud,
        Paint()
          ..color = glowColor.withValues(alpha: 0.55 * glow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    canvas.drawPath(cloud, Paint()..color = fill);
    canvas.drawPath(
      cloud,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CloudPainter old) =>
      old.fill != fill ||
      old.stroke != stroke ||
      old.glow != glow ||
      old.glowColor != glowColor;
}

// ────────────────────────────────────────────────────────────
/// Practice trade, told with money only (no jargon):
///
///   1. You have practice money (the bar at the bottom).
///   2. Tap BUY  -> some money turns into stock (bar goes blue).
///   3. The price line climbs -> the blue part grows.
///   4. Tap SELL -> stock turns back into money, and you end up with MORE
///      than you started with. A green "+₹850" pops.
///
/// Only three words on screen: BUY, SELL and the profit.
class PracticeTradeAnimation extends StatelessWidget {
  const PracticeTradeAnimation({super.key});

  // Where on the price line (0..1 of its length) we buy and sell.
  static const _buyAt = 0.25;
  static const _sellAt = 0.88;

  // When the line draws, and the loop times that match BUY / SELL.
  static const _drawStart = 0.04;
  static const _drawEnd = 0.78;
  static const _buyT = _drawStart + (_drawEnd - _drawStart) * _buyAt; // 0.23
  static const _sellT = _drawStart + (_drawEnd - _drawStart) * _sellAt; // 0.71

  static double _pulse(double t, double center, double half) =>
      1 - ((t - center).abs() / half).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 5200),
      builder: (context, t) {
        final draw = phase(t, _drawStart, _drawEnd); // linear: markers line up
        final buyPop = phase(t, _buyT, _buyT + 0.06, Curves.elasticOut);
        final sellPop = phase(t, _sellT, _sellT + 0.06, Curves.elasticOut);

        // Practice money: cash (green) and money-in-stock (blue).
        final buyMove = phase(t, _buyT, _buyT + 0.08, Curves.easeOutCubic);
        final sellMove = phase(t, _sellT, _sellT + 0.08, Curves.easeOutCubic);
        final grow = phase(t, _buyT + 0.08, _sellT);
        final stockHold = 0.40 + 0.15 * grow; // stock grows as price climbs
        final cash = 0.70 - 0.40 * buyMove + stockHold * sellMove;
        final stock = stockHold * buyMove * (1 - sellMove);

        final chip = phase(t, _sellT + 0.04, _sellT + 0.12, Curves.easeOutBack);

        final isSell = t >= _buyT + 0.03;
        final press = math.max(
          _pulse(t, _buyT - 0.02, 0.03),
          _pulse(t, _sellT - 0.02, 0.03),
        );
        final done = t >= _sellT + 0.02;
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              children: [
                // Price line with a BUY dot and a SELL dot.
                Expanded(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _TradeChartPainter(
                      draw: draw,
                      buy: buyPop,
                      sell: sellPop,
                      guide: scheme.onSurface.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // One button: BUY, then it turns into SELL.
                _TradeButton(
                  label: isSell ? 'SELL' : 'BUY',
                  color: isSell ? ToolPalette.red : ToolPalette.blue,
                  press: press,
                  dim: done ? 0.45 : 1,
                ),
                const SizedBox(height: 8),
                // Practice money + profit.
                SizedBox(
                  height: 16,
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 14,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MoneyBar(
                          cash: cash,
                          stock: stock,
                          trackColor: scheme.onSurface.withValues(alpha: 0.12),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 38,
                        child: Transform.scale(
                          scale: chip,
                          alignment: Alignment.centerRight,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 2.5),
                            decoration: BoxDecoration(
                              color: ToolPalette.green,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              '+₹850',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Big, obvious button. Shrinks and fills with colour when "tapped".
class _TradeButton extends StatelessWidget {
  const _TradeButton({
    required this.label,
    required this.color,
    required this.press,
    required this.dim,
  });

  final String label;
  final Color color;
  final double press; // 0..1 tap strength
  final double dim; // 1 normal, lower = used up

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(color.withValues(alpha: 0.14), color, press)!;
    final fg = Color.lerp(color, Colors.white, press)!;

    return Opacity(
      opacity: dim,
      child: Transform.scale(
        scale: 1 - 0.07 * press,
        child: Container(
          height: 20,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.7)),
            boxShadow: [
              if (press > 0)
                BoxShadow(
                  color: color.withValues(alpha: 0.35 * press),
                  blurRadius: 8 * press,
                ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// Your practice money: green = cash, blue = money sitting in the stock.
class _MoneyBar extends StatelessWidget {
  const _MoneyBar({
    required this.cash,
    required this.stock,
    required this.trackColor,
  });

  final double cash; // 0..1 share of the bar
  final double stock; // 0..1 share of the bar
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return Align(
          alignment: Alignment.center,
          child: Container(
            height: 8,
            width: w,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: w * cash.clamp(0.0, 1.0),
                    height: 8,
                    color: ToolPalette.green,
                  ),
                  Container(
                    width: w * stock.clamp(0.0, 1.0),
                    height: 8,
                    color: ToolPalette.blue,
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

class _TradeChartPainter extends CustomPainter {
  _TradeChartPainter({
    required this.draw,
    required this.buy,
    required this.sell,
    required this.guide,
  });

  final double draw; // 0..1 how much of the line is drawn
  final double buy; // 0..1 BUY dot pop
  final double sell; // 0..1 SELL dot pop
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Dips, then climbs: buy low, sell high.
    final path = Path()
      ..moveTo(0, h * 0.50)
      ..cubicTo(w * 0.12, h * 0.45, w * 0.18, h * 0.80, w * 0.30, h * 0.74)
      ..cubicTo(w * 0.44, h * 0.68, w * 0.52, h * 0.50, w * 0.62, h * 0.38)
      ..cubicTo(w * 0.74, h * 0.24, w * 0.84, h * 0.16, w, h * 0.10);

    final metric = path.computeMetrics().first;
    final len = metric.length;
    final visible = len * draw;
    final entryLen = len * PracticeTradeAnimation._buyAt;
    final exitLen = len * PracticeTradeAnimation._sellAt;

    final entry = metric.getTangentForOffset(entryLen)?.position;
    final exit = metric.getTangentForOffset(exitLen)?.position;

    // Profit zone grows between BUY and SELL.
    if (entry != null && visible > entryLen) {
      final end = visible < exitLen ? visible : exitLen;
      final endPos = metric.getTangentForOffset(end)!.position;
      final zone = metric.extractPath(entryLen, end)
        ..lineTo(endPos.dx, entry.dy)
        ..lineTo(entry.dx, entry.dy)
        ..close();
      canvas.drawPath(
        zone,
        Paint()..color = ToolPalette.green.withValues(alpha: 0.16),
      );
      canvas.drawLine(
        entry,
        Offset(endPos.dx, entry.dy),
        Paint()
          ..color = guide
          ..strokeWidth = 1,
      );
    }

    // Price line.
    canvas.drawPath(
      metric.extractPath(0, visible),
      Paint()
        ..color = ToolPalette.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // BUY dot (blue) and SELL dot (red).
    if (entry != null && buy > 0) {
      canvas.drawCircle(entry, 5 * buy, Paint()..color = ToolPalette.blue);
      canvas.drawCircle(entry, 2 * buy, Paint()..color = Colors.white);
    }
    if (exit != null && sell > 0) {
      canvas.drawCircle(exit, 5 * sell, Paint()..color = ToolPalette.red);
      canvas.drawCircle(exit, 2 * sell, Paint()..color = Colors.white);
    }

    // Moving tip while the line draws.
    final tip = metric.getTangentForOffset(visible)?.position;
    if (tip != null && draw > 0 && draw < 1) {
      canvas.drawCircle(tip, 3.4, Paint()..color = ToolPalette.green);
      canvas.drawCircle(tip, 1.3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_TradeChartPainter old) =>
      old.draw != draw ||
      old.buy != buy ||
      old.sell != sell ||
      old.guide != guide;
}

/// AI Stock Analysis: a ticker is typed into a search pill, an AI sparkle
/// lights up, the price line draws itself, and an insight card slides in
/// with a score bar and a BULLISH badge.
class AiStockAnimation extends StatelessWidget {
  const AiStockAnimation({super.key});

  static const _ticker = 'RELIANCE';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 6000),
      builder: (context, t) {
        final appear = phase(t, 0.0, 0.06, Curves.easeOut);

        // Typing in the search pill.
        final typed = phase(t, 0.08, 0.28);
        final chars = (typed * _ticker.length).round().clamp(0, _ticker.length);
        final caret = t < 0.34 && ((t * 36).floor() % 2 == 0);
        final searchText = _ticker.substring(0, chars) + (caret ? '|' : '');

        // AI sparkle lights up after the search.
        final ai = phase(t, 0.30, 0.38, Curves.easeOutBack);
        final spin = phase(t, 0.30, 0.60) * math.pi * 2;

        final draw = phase(t, 0.36, 0.64, Curves.easeInOut);

        // Insight card.
        final card = phase(t, 0.66, 0.76, Curves.easeOutBack);
        final score = phase(t, 0.72, 0.86, Curves.easeOut);
        final badge = phase(t, 0.82, 0.90, Curves.elasticOut);

        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              children: [
                // Search pill + AI sparkle
                Opacity(
                  opacity: appear,
                  child: Container(
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: Color.lerp(
                          scheme.outlineVariant,
                          ToolPalette.violet,
                          typed > 0 && ai < 1 ? 1 : ai,
                        )!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 10,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            searchText,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Transform.scale(
                          scale: ai.clamp(0.0, 1.4),
                          child: Transform.rotate(
                            angle: spin,
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 10,
                              color: ToolPalette.violet,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Price line
                Expanded(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _AiStockChartPainter(draw: draw),
                  ),
                ),
                const SizedBox(height: 4),
                // Insight card
                Opacity(
                  opacity: card.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - card)),
                    child: Container(
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: ToolPalette.violet.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 8,
                              color: ToolPalette.violet,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Score bar
                                Container(
                                  height: 3.5,
                                  alignment: Alignment.centerLeft,
                                  decoration: BoxDecoration(
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: FractionallySizedBox(
                                    widthFactor: 0.82 * score,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: ToolPalette.green,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                FractionallySizedBox(
                                  widthFactor: 0.55,
                                  child: Container(
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 3),
                          Transform.scale(
                            scale: badge,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 3, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: ToolPalette.green,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'BULLISH',
                                style: TextStyle(
                                  fontSize: 4.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AiStockChartPainter extends CustomPainter {
  _AiStockChartPainter({required this.draw});

  final double draw; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0, h * 0.70)
      ..cubicTo(w * 0.10, h * 0.60, w * 0.16, h * 0.86, w * 0.28, h * 0.74)
      ..cubicTo(w * 0.40, h * 0.62, w * 0.46, h * 0.70, w * 0.56, h * 0.48)
      ..cubicTo(w * 0.68, h * 0.24, w * 0.82, h * 0.34, w, h * 0.10);

    final metric = path.computeMetrics().first;
    final visible = metric.length * draw;
    if (visible <= 0) return;

    final lineSoFar = metric.extractPath(0, visible);
    final end = metric.getTangentForOffset(visible)!.position;

    // Soft fill under the line.
    final fill = Path.from(lineSoFar)
      ..lineTo(end.dx, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ToolPalette.green.withValues(alpha: 0.28),
            ToolPalette.green.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.drawPath(
      lineSoFar,
      Paint()
        ..color = ToolPalette.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    if (draw < 1) {
      canvas.drawCircle(end, 3.2, Paint()..color = ToolPalette.green);
      canvas.drawCircle(end, 1.2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_AiStockChartPainter old) => old.draw != draw;
}

// ────────────────────────────────────────────────────────────
/// AI Index Status: a NIFTY chip drops in, a mood gauge (red / amber / green)
/// appears and the needle swings to the green side. Three signal bars
/// (trend, momentum, OI) fill up, then a BULLISH badge pops.
class AiIndexAnimation extends StatelessWidget {
  const AiIndexAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 6000),
      builder: (context, t) {
        final chip = phase(t, 0.0, 0.08, Curves.easeOutBack);
        final gauge = phase(t, 0.08, 0.18, Curves.easeOut);

        // Needle: wobbles around the middle while "thinking", then settles.
        final think = phase(t, 0.18, 0.40);
        final settle = phase(t, 0.40, 0.56, Curves.easeOutBack);
        final wobble = math.sin(think * math.pi * 6) * 0.12 * (1 - settle);
        final needle = (0.5 + wobble + 0.30 * settle).clamp(0.0, 1.0);

        final sparkle = phase(t, 0.18, 0.26, Curves.easeOutBack) *
            (1 - phase(t, 0.56, 0.62));
        final spin = t * math.pi * 12;

        double bar(int i) =>
            phase(t, 0.56 + i * 0.06, 0.68 + i * 0.06, Curves.easeOut);
        final badge = phase(t, 0.80, 0.88, Curves.elasticOut);

        final fadeOut = 1 - phase(t, 0.94, 1.0);

        Widget signal(int i, Color color) => Expanded(
              child: Container(
                height: 4,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  widthFactor: bar(i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            );

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              children: [
                // NIFTY chip + AI sparkle
                Transform.scale(
                  scale: chip,
                  child: Opacity(
                    opacity: chip.clamp(0.0, 1.0),
                    child: Container(
                      height: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: ToolPalette.blue.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: ToolPalette.blue.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'NIFTY',
                            style: TextStyle(
                              fontSize: 6.5,
                              fontWeight: FontWeight.w800,
                              color: ToolPalette.blue,
                            ),
                          ),
                          SizedBox(width: 3 * sparkle.clamp(0.0, 1.0)),
                          if (sparkle > 0)
                            Transform.scale(
                              scale: sparkle.clamp(0.0, 1.4),
                              child: Transform.rotate(
                                angle: spin,
                                child: const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 8,
                                  color: ToolPalette.violet,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Mood gauge
                Expanded(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _MoodGaugePainter(
                      appear: gauge,
                      value: needle,
                      needleColor: scheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                // Trend, momentum, OI
                Row(
                  children: [
                    signal(0, ToolPalette.green),
                    const SizedBox(width: 3),
                    signal(1, ToolPalette.green),
                    const SizedBox(width: 3),
                    signal(2, ToolPalette.amber),
                  ],
                ),
                const SizedBox(height: 5),
                Transform.scale(
                  scale: badge,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: ToolPalette.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'BULLISH',
                      style: TextStyle(
                        fontSize: 6,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MoodGaugePainter extends CustomPainter {
  _MoodGaugePainter({
    required this.appear,
    required this.value,
    required this.needleColor,
  });

  final double appear; // 0..1
  final double value; // 0 (bearish) .. 1 (bullish)
  final Color needleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 3);
    final r = math.min(size.width / 2 - 4, size.height - 8);
    final rect = Rect.fromCircle(center: c, radius: r);

    // Three arc segments: red, amber, green.
    const colors = [ToolPalette.red, ToolPalette.amber, ToolPalette.green];
    const gap = 0.07;
    final seg = math.pi / 3;
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(
        rect,
        math.pi + i * seg + gap / 2,
        seg - gap,
        false,
        Paint()
          ..color = colors[i].withValues(alpha: 0.9 * appear)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.butt,
      );
    }

    // Needle + hub.
    final angle = math.pi + value * math.pi;
    final tip = Offset(
      c.dx + math.cos(angle) * r * 0.78,
      c.dy + math.sin(angle) * r * 0.78,
    );
    canvas.drawLine(
      c,
      tip,
      Paint()
        ..color = needleColor.withValues(alpha: appear)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      c,
      2.6 * appear,
      Paint()..color = needleColor,
    );
  }

  @override
  bool shouldRepaint(_MoodGaugePainter old) =>
      old.appear != appear ||
      old.value != value ||
      old.needleColor != needleColor;
}

/// Trade Journal: a BUY entry turns into a SELL entry, while a GitHub-style
/// calendar fills in day by day (green = profit, red = loss). Today's square
/// pops in last, and a total P&L chip appears.
class JournalAnimation extends StatelessWidget {
  const JournalAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 6000),
      builder: (context, t) {
        final appear = phase(t, 0.0, 0.08, Curves.easeOutBack);

        // Calendar fills in from the start.
        final reveal = phase(t, 0.10, 0.52);

        // Entry row: BUY, then it turns into SELL.
        final isSell = t >= 0.34;
        final swap = phase(t, 0.34, 0.40, Curves.easeOutBack);
        final chipScale = isSell ? 0.8 + 0.2 * swap : appear;
        final chipColor = isSell ? ToolPalette.red : ToolPalette.blue;

        // Today's square + total P&L.
        final today = phase(t, 0.58, 0.68, Curves.elasticOut);
        final total = phase(t, 0.68, 0.78, Curves.easeOutBack);
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              children: [
                // Entry row
                Opacity(
                  opacity: appear.clamp(0.0, 1.0),
                  child: SizedBox(
                    height: 16,
                    child: Row(
                      children: [
                        Transform.scale(
                          scale: chipScale,
                          child: Container(
                            width: 24,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                              color: chipColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: chipColor.withValues(alpha: 0.7),
                              ),
                            ),
                            child: Text(
                              isSell ? 'SELL' : 'BUY',
                              style: TextStyle(
                                fontSize: 6,
                                fontWeight: FontWeight.w800,
                                color: chipColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FractionallySizedBox(
                                widthFactor: 0.85,
                                child: Container(
                                  height: 3.5,
                                  decoration: BoxDecoration(
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              FractionallySizedBox(
                                widthFactor: 0.5,
                                child: Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                // GitHub-style calendar
                Expanded(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _JournalGridPainter(
                      reveal: reveal,
                      today: today,
                      empty: scheme.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                // Total P&L
                SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      Icon(
                        Icons.menu_book_rounded,
                        size: 11,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                      const Spacer(),
                      Transform.scale(
                        scale: total,
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: ToolPalette.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '+₹2,450',
                            style: TextStyle(
                              fontSize: 6.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _JournalGridPainter extends CustomPainter {
  _JournalGridPainter({
    required this.reveal,
    required this.today,
    required this.empty,
  });

  final double reveal; // 0..1 how many past days are filled
  final double today; // 0..1 pop of the last square
  final Color empty;

  // 7 columns x 4 rows. 0 = no trade, -1 = loss, 1 = small profit, 2 = big profit.
  // The last cell (index 27) is "today" and pops in after the SELL.
  static const _cols = 7;
  static const _rows = 4;
  static const _values = [
    0, 1, 0, 2, 1, 0, 0, //
    1, -1, 2, 1, 0, 2, 1, //
    0, 2, 1, -1, 2, 2, 1, //
    1, 0, 2, 1, 2, -1, 2, //
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.5;
    final cell = math.min(
      (size.width - gap * (_cols - 1)) / _cols,
      (size.height - gap * (_rows - 1)) / _rows,
    );
    final gridW = cell * _cols + gap * (_cols - 1);
    final gridH = cell * _rows + gap * (_rows - 1);
    final left = (size.width - gridW) / 2;
    final top = (size.height - gridH) / 2;
    final radius = Radius.circular(cell * 0.25);
    final past = (_cols * _rows) - 1; // 27 filled in order

    for (var i = 0; i < _cols * _rows; i++) {
      final col = i % _cols;
      final row = i ~/ _cols;
      final rect = Rect.fromLTWH(
        left + col * (cell + gap),
        top + row * (cell + gap),
        cell,
        cell,
      );

      // Empty slot is always visible.
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, radius), Paint()..color = empty);

      final v = _values[i];
      if (v == 0) continue;

      final isToday = i == past;
      final s = isToday ? today : (reveal * past - i).clamp(0.0, 1.0);
      if (s <= 0) continue;

      final color = v < 0
          ? ToolPalette.red
          : ToolPalette.green.withValues(alpha: v == 1 ? 0.45 : 1.0);

      final scale =
          isToday ? s.clamp(0.0, 1.3) : Curves.easeOutBack.transform(s);
      final r = Rect.fromCenter(
        center: rect.center,
        width: cell * scale,
        height: cell * scale,
      );

      if (isToday) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(1.5), radius),
          Paint()
            ..color =
                ToolPalette.green.withValues(alpha: 0.5 * s.clamp(0.0, 1.0))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, radius), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_JournalGridPainter old) =>
      old.reveal != reveal || old.today != today || old.empty != empty;
}

// ────────────────────────────────────────────────────────────
/// My Alerts: the user drags a HIGH line and a LOW line to their own prices,
/// then the live price line climbs. The moment it crosses the HIGH line a ring
/// pulses, a notification card slides in, the bell rings and a HIGH badge pops.
class MyAlertsAnimation extends StatelessWidget {
  const MyAlertsAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 6000),
      builder: (context, t) {
        // User sets the two levels.
        final setHigh = phase(t, 0.04, 0.22, Curves.easeOutCubic);
        final setLow = phase(t, 0.14, 0.30, Curves.easeOutCubic);

        // Live price line.
        final draw = phase(t, 0.32, 0.64);

        // Notification.
        final note = phase(t, 0.60, 0.70, Curves.easeOutBack);
        final ring = phase(t, 0.66, 0.86);
        final bellAngle = math.sin(ring * math.pi * 6) * 0.45 * (1 - ring);
        final badge = phase(t, 0.74, 0.82, Curves.elasticOut);

        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MyAlertsPainter(
                      setHigh: setHigh,
                      setLow: setLow,
                      draw: draw,
                    ),
                  ),
                ),
                // Notification card
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 20,
                  child: Opacity(
                    opacity: note.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, -14 * (1 - note)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: ToolPalette.amber.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Transform.rotate(
                                angle: bellAngle,
                                child: const Icon(
                                  Icons.notifications_active_rounded,
                                  size: 9,
                                  color: ToolPalette.amber,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FractionallySizedBox(
                                    widthFactor: 0.8,
                                    child: Container(
                                      height: 3.5,
                                      decoration: BoxDecoration(
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.45),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  FractionallySizedBox(
                                    widthFactor: 0.5,
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: badge,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 3, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: ToolPalette.green,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'HIGH',
                                  style: TextStyle(
                                    fontSize: 5.5,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MyAlertsPainter extends CustomPainter {
  _MyAlertsPainter({
    required this.setHigh,
    required this.setLow,
    required this.draw,
  });

  final double setHigh; // 0..1 HIGH line dragged into place
  final double setLow; // 0..1 LOW line dragged into place
  final double draw; // 0..1 price line progress

  void _dashed(Canvas canvas, double y, double w, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 3.0;
    var x = 0.0;
    while (x < w - 8) {
      canvas.drawLine(
          Offset(x, y), Offset(math.min(x + dash, w - 8), y), paint);
      x += dash + gap;
    }
  }

  void _handle(Canvas canvas, Offset c, Color color) {
    canvas.drawCircle(c, 3.6, Paint()..color = color);
    canvas.drawCircle(c, 1.4, Paint()..color = Colors.white);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // The user drags each line from the edge to their chosen price.
    final highY = h * (0.14 + 0.26 * setHigh); // settles at 0.40h
    final lowY = h * (0.98 - 0.16 * setLow); // settles at 0.82h
    final highColor = ToolPalette.green.withValues(alpha: 0.9);
    final lowColor = ToolPalette.red.withValues(alpha: 0.9);

    if (setHigh > 0) {
      _dashed(canvas, highY, w, highColor);
      _handle(canvas, Offset(w - 4, highY), ToolPalette.green);
    }
    if (setLow > 0) {
      _dashed(canvas, lowY, w, lowColor);
      _handle(canvas, Offset(w - 4, lowY), ToolPalette.red);
    }

    // Live price line: wiggles in the middle, then breaks above the HIGH line.
    final finalHighY = h * 0.40;
    final path = Path()
      ..moveTo(0, h * 0.66)
      ..cubicTo(w * 0.12, h * 0.72, w * 0.20, h * 0.54, w * 0.34, h * 0.60)
      ..cubicTo(w * 0.48, h * 0.66, w * 0.54, h * 0.52, w * 0.66, h * 0.46)
      ..cubicTo(w * 0.78, h * 0.40, w * 0.86, h * 0.26, w * 0.96, h * 0.18);

    final metric = path.computeMetrics().first;
    final len = metric.length;

    // Find where the line first crosses the HIGH level.
    double crossFrac = 1;
    for (var i = 0; i <= 100; i++) {
      final p = metric.getTangentForOffset(len * i / 100)!.position;
      if (p.dy <= finalHighY) {
        crossFrac = i / 100;
        break;
      }
    }

    final visible = len * draw;
    if (visible > 0) {
      final color = draw >= crossFrac ? ToolPalette.green : ToolPalette.blue;
      canvas.drawPath(
        metric.extractPath(0, visible),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );

      final tip = metric.getTangentForOffset(visible)!.position;
      if (draw < 1) {
        canvas.drawCircle(tip, 3.2, Paint()..color = color);
        canvas.drawCircle(tip, 1.2, Paint()..color = Colors.white);
      }
    }

    // Pulse ring at the moment of crossing.
    if (draw >= crossFrac) {
      final pulse = ((draw - crossFrac) / 0.12).clamp(0.0, 1.0);
      final hit = metric.getTangentForOffset(len * crossFrac)!.position;
      canvas.drawCircle(
        hit,
        3 + 9 * pulse,
        Paint()
          ..color = ToolPalette.green.withValues(alpha: 0.6 * (1 - pulse))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(_MyAlertsPainter old) =>
      old.setHigh != setHigh || old.setLow != setLow || old.draw != draw;
}
// ────────────────────────────────────────────────────────────
// PASTE AT THE BOTTOM of frag_tools_v3_animations.dart
// (uses the same imports + helpers: LoopingAnimation, phase, ToolPalette)
// Replaces the earlier AiPicksAnimation / NiftyPicksAnimation /
// ScannerPicksAnimation. Delete those first.
// ────────────────────────────────────────────────────────────

/// Scanner Picks: stocks found by scanners appear one by one,
/// and each one gets a tick (it was right) or a cross (it was wrong).
/// The small number on the left is how many scanners picked that stock.
class ScannerPicksAnimation extends StatelessWidget {
  const ScannerPicksAnimation({super.key});

  static const _hits = [true, true, false, true];
  static const _counts = ['1', '2', '3', '4'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 6000),
      builder: (context, t) {
        final fadeOut = 1 - phase(t, 0.94, 1.0);
        final chip = phase(t, 0.80, 0.90, Curves.elasticOut);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  Opacity(
                    opacity: phase(t, 0.04 + 0.08 * i, 0.12 + 0.08 * i)
                        .clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(
                          -10 *
                              (1 - phase(t, 0.04 + 0.08 * i, 0.12 + 0.08 * i)),
                          0),
                      child: SizedBox(
                        height: 13,
                        child: Row(
                          children: [
                            // How many scanners picked it
                            Container(
                              width: 11,
                              height: 11,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: ToolPalette.amber.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                _counts[i],
                                style: const TextStyle(
                                  fontSize: 6,
                                  fontWeight: FontWeight.w800,
                                  color: ToolPalette.amber,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            // Stock name placeholder
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: 0.75 - 0.1 * i,
                                  child: Container(
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            _PicksResultMark(
                              p: phase(t, 0.38 + 0.09 * i, 0.46 + 0.09 * i,
                                  Curves.easeOutBack),
                              ok: _hits[i],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Transform.scale(
                    scale: chip,
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: ToolPalette.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '3 / 4 right',
                        style: TextStyle(
                          fontSize: 6.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────
/// Daily accuracy (used for BOTH Nifty Picks and Stock Picks):
/// one tile per day pops in (green tick = right, red cross = wrong),
/// then an accuracy bar fills and the overall % appears.
/// Only the small label and colour change between the two tools.
class DailyAccuracyAnimation extends StatelessWidget {
  const DailyAccuracyAnimation({
    super.key,
    required this.label,
    required this.color,
  });

  final String label; // e.g. 'NIFTY' or 'AI'
  final Color color;

  static const _hits = [true, true, false, true, true];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LoopingAnimation(
      duration: const Duration(milliseconds: 6000),
      builder: (context, t) {
        final appear = phase(t, 0.0, 0.08, Curves.easeOutBack);
        final bar = phase(t, 0.66, 0.84, Curves.easeOutCubic);
        final pct = phase(t, 0.80, 0.90, Curves.elasticOut);
        final fadeOut = 1 - phase(t, 0.94, 1.0);

        return Opacity(
          opacity: fadeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label chip
                Transform.scale(
                  scale: appear,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 6.5,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // One tile per day
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 5; i++)
                      _DayTile(
                        p: phase(t, 0.14 + 0.10 * i, 0.22 + 0.10 * i,
                            Curves.easeOutBack),
                        ok: _hits[i],
                        empty: scheme.onSurface.withValues(alpha: 0.08),
                      ),
                  ],
                ),
                const Spacer(),
                // Overall accuracy bar + %
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (0.8 * bar).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: ToolPalette.green,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Transform.scale(
                      scale: pct,
                      alignment: Alignment.centerRight,
                      child: const Text(
                        '80%',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: ToolPalette.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.p, required this.ok, required this.empty});

  final double p; // 0..1 pop
  final bool ok;
  final Color empty;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: empty,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (p > 0)
            Transform.scale(
              scale: p,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: ok ? ToolPalette.green : ToolPalette.red,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Icon(
                  ok ? Icons.check_rounded : Icons.close_rounded,
                  size: 9,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PicksResultMark extends StatelessWidget {
  const _PicksResultMark({required this.p, required this.ok});

  final double p; // 0..1 pop
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ok ? ToolPalette.green : ToolPalette.red;

    return SizedBox(
      width: 13,
      height: 13,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.25),
                width: 1.2,
              ),
            ),
          ),
          if (p > 0)
            Transform.scale(
              scale: p,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(
                  ok ? Icons.check_rounded : Icons.close_rounded,
                  size: 9,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
