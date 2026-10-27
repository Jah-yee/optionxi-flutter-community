// ─────────────────────────────────────────────────────────────────────────
// Strategy Builder — animated "Backtest" banner + index picker sheet.
//
// Usage (unchanged):  const StrategyBuilderBanner()
//
// The banner plays a looping mini-story on its own:
//   1. Chart draws in → a BUY tag pops onto the chart (you place a trade)
//   2. A scrubber slides along past data (you "move the chart position")
//   3. P&L counter ticks live, green/red fill shows gain/loss, SELL tag lands
//
// Message conveyed: "Pick a trade, slide through the past, see what you
// WOULD have made" — real history, not probability.
//
// Still requires StrategyBuilderPage({this.initialIndex}) as before.
// No assets / packages — everything is drawn with CustomPainter.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:optionxi/StrategyBuilder/strategy_builder.dart';

// ── Theme-aware colors ──────────────────────────────────────────────────
const _green = Color(0xFF22C55E);
const _red = Color(0xFFEF4444);
const _blue = Color(0xFF3B82F6);

/// Demo price path (0..1). Dips after entry (red P&L) then rallies (green).
const _kPrice = <double>[
  0.50,
  0.48,
  0.52,
  0.47,
  0.44,
  0.46,
  0.42,
  0.40,
  0.43,
  0.41,
  0.45,
  0.43,
  0.38,
  0.35,
  0.33,
  0.37,
  0.34,
  0.40,
  0.46,
  0.52,
  0.50,
  0.57,
  0.62,
  0.60,
  0.68,
  0.72,
  0.70,
  0.78,
  0.82,
  0.80,
  0.86,
];

double _priceAt(double x) {
  final pos = x.clamp(0.0, 1.0) * (_kPrice.length - 1);
  final i = pos.floor().clamp(0, _kPrice.length - 2);
  final f = pos - i;
  return _kPrice[i] + (_kPrice[i + 1] - _kPrice[i]) * f;
}

String _inr(int v) {
  final neg = v < 0;
  var s = v.abs().toString();
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    final rest = s.substring(0, s.length - 3);
    final b = StringBuffer();
    for (var i = 0; i < rest.length; i++) {
      if (i > 0 && (rest.length - i) % 2 == 0) b.write(',');
      b.write(rest[i]);
    }
    s = '${b.toString()},$last3';
  }
  return '${v == 0 ? '' : (neg ? '-' : '+')}₹$s';
}

/* ════════════════════════════════════════════════════════════════════════
   BANNER
   ════════════════════════════════════════════════════════════════════════ */

class StrategyBuilderBanner extends StatefulWidget {
  final double height;
  const StrategyBuilderBanner({super.key, this.height = 220});

  @override
  State<StrategyBuilderBanner> createState() => _StrategyBuilderBannerState();
}

class _StrategyBuilderBannerState extends State<StrategyBuilderBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _pressed = false;

  static const double _entryX = 0.28;
  static const double _exitX = 0.92;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 9))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _IndexPickerSheet(),
    );
  }

  double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF475569);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: _openPicker,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: widget.height,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF0B1220), const Color(0xFF1B1446)]
                  : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (isDark ? const Color(0xFF1B1446) : const Color(0xFF94A3B8))
                        .withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                final draw = Curves.easeOut.transform(_seg(t, 0.0, 0.18));
                final entryPop =
                    Curves.elasticOut.transform(_seg(t, 0.20, 0.32));
                final scrubP = Curves.easeInOut.transform(_seg(t, 0.34, 0.76));
                final showScrub = t >= 0.32;
                final exitPop =
                    Curves.elasticOut.transform(_seg(t, 0.78, 0.90));
                final fade = t > 0.94 ? 1 - (t - 0.94) / 0.06 : 1.0;

                final sx = _entryX + (_exitX - _entryX) * scrubP;
                final pnl = showScrub
                    ? ((_priceAt(sx) - _priceAt(_entryX)) * 12000).round()
                    : 0;
                final pnlColor = pnl > 0
                    ? _green
                    : pnl < 0
                        ? _red
                        : subTextColor;
                final step = t < 0.32 ? 0 : (t < 0.78 ? 1 : 2);

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Opacity(
                    opacity: fade.clamp(0.0, 1.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.10)
                                      : Colors.black.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _green.withOpacity(0.5 +
                                            0.5 *
                                                math.sin(t * 2 * math.pi * 9)),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'BACKTESTING',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: subTextColor,
                                            fontSize: 9.5,
                                            letterSpacing: 0.8,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text('P&L  ',
                                style: TextStyle(
                                    color: subTextColor, fontSize: 11)),
                            Text(
                              pnl == 0 ? '₹0' : _inr(pnl),
                              style: TextStyle(
                                  color: pnlColor,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Replay the past. See your P&L.',
                          style: TextStyle(
                              color: textColor,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800),
                        ),
                        Expanded(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _ReplayChartPainter(
                              draw: draw,
                              entryPop: entryPop,
                              exitPop: exitPop,
                              scrubP: scrubP,
                              showScrub: showScrub,
                              entryX: _entryX,
                              exitX: _exitX,
                              isDark: isDark,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _StepChip(
                                n: 1,
                                label: 'Buy / Sell',
                                active: step == 0,
                                done: step > 0,
                                isDark: isDark),
                            const SizedBox(width: 6),
                            _StepChip(
                                n: 2,
                                label: 'Slide time',
                                active: step == 1,
                                done: step > 1,
                                isDark: isDark),
                            const SizedBox(width: 6),
                            _StepChip(
                                n: 3,
                                label: 'See P&L',
                                active: step == 2,
                                done: false,
                                isDark: isDark),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final int n;
  final String label;
  final bool active;
  final bool done;
  final bool isDark;
  const _StepChip({
    required this.n,
    required this.label,
    required this.active,
    required this.done,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final inactiveColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    final chipBg = isDark
        ? Colors.white.withOpacity(active ? 0.18 : 0.06)
        : Colors.black.withOpacity(active ? 0.08 : 0.04);
    final chipBorder = active
        ? (isDark ? Colors.white54 : const Color(0xFF94A3B8))
        : Colors.transparent;

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: chipBorder, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            done
                ? const Icon(Icons.check_circle, size: 12, color: _green)
                : Text('$n',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: active ? activeColor : inactiveColor)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: active ? activeColor : inactiveColor)),
            ),
          ],
        ),
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Replay chart painter
   ════════════════════════════════════════════════════════════════════════ */

class _ReplayChartPainter extends CustomPainter {
  final double draw, entryPop, exitPop, scrubP, entryX, exitX;
  final bool showScrub;
  final bool isDark;

  _ReplayChartPainter({
    required this.draw,
    required this.entryPop,
    required this.exitPop,
    required this.scrubP,
    required this.showScrub,
    required this.entryX,
    required this.exitX,
    required this.isDark,
  });

  void _tag(
      Canvas c, String text, Offset anchor, Color bg, double scale, Size size) {
    if (scale <= 0) return;
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(
              color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 14, h = tp.height + 7;
    final cx = anchor.dx.clamp(w / 2 + 2, size.width - w / 2 - 2).toDouble();
    c.save();
    c.translate(cx, anchor.dy);
    c.scale(scale.clamp(0.0, 1.25));
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          Radius.circular(h / 2)),
      Paint()..color = bg,
    );
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const top = 22.0, bot = 6.0;
    final h = size.height - top - bot;
    Offset pt(double x) => Offset(x * size.width, top + (1 - _priceAt(x)) * h);

    final gridColor = isDark
        ? Colors.white.withOpacity(0.05)
        : Colors.black.withOpacity(0.06);
    final lineColor =
        isDark ? Colors.white.withOpacity(0.55) : const Color(0xFF334155);
    final dashColor =
        isDark ? Colors.white.withOpacity(0.35) : const Color(0xFF94A3B8);
    final scrubLineColor = isDark
        ? Colors.white.withOpacity(0.25)
        : Colors.black.withOpacity(0.15);

    // faint grid
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = top + h * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final ep = pt(entryX);
    final sx = entryX + (exitX - entryX) * scrubP;
    final pnl = _priceAt(sx) - _priceAt(entryX);
    final cur = pnl >= 0 ? _green : _red;

    // entry baseline (dashed)
    if (entryPop > 0) {
      final dash = Paint()
        ..color = dashColor
        ..strokeWidth = 1;
      for (double x = ep.dx; x < size.width; x += 8) {
        canvas.drawLine(
            Offset(x, ep.dy), Offset(math.min(x + 4, size.width), ep.dy), dash);
      }
    }

    // P&L fill between baseline and line (green above, red below)
    if (showScrub && scrubP > 0) {
      final poly = Path()..moveTo(ep.dx, ep.dy);
      const steps = 48;
      for (var k = 0; k <= steps; k++) {
        final x = entryX + (sx - entryX) * k / steps;
        final p = pt(x);
        poly.lineTo(p.dx, p.dy);
      }
      poly.lineTo(sx * size.width, ep.dy);
      poly.close();

      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, size.width, ep.dy));
      canvas.drawPath(poly, Paint()..color = _green.withOpacity(0.30));
      canvas.restore();
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, ep.dy, size.width, size.height));
      canvas.drawPath(poly, Paint()..color = _red.withOpacity(0.30));
      canvas.restore();
    }

    // price line (draw-on)
    const n = 120;
    final lim = (draw * n).floor();
    final line = Path();
    for (var k = 0; k <= lim; k++) {
      final p = pt(k / n);
      k == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // highlighted traveled segment
    if (showScrub && scrubP > 0) {
      final seg = Path();
      const steps = 48;
      for (var k = 0; k <= steps; k++) {
        final x = entryX + (sx - entryX) * k / steps;
        final p = pt(x);
        k == 0 ? seg.moveTo(p.dx, p.dy) : seg.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        seg,
        Paint()
          ..color = cur
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // entry marker + BUY tag
    if (entryPop > 0) {
      canvas.drawCircle(
          ep, 4.5 * entryPop.clamp(0.0, 1.2), Paint()..color = Colors.white);
      canvas.drawCircle(
          ep,
          7.5 * entryPop.clamp(0.0, 1.2),
          Paint()
            ..color = _blue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      _tag(canvas, 'BUY 24500 CE', Offset(ep.dx, ep.dy - 18), _blue, entryPop,
          size);
    }

    // scrubber
    if (showScrub) {
      final sp = pt(sx);
      canvas.drawLine(
        Offset(sp.dx, 8),
        Offset(sp.dx, size.height),
        Paint()
          ..color = scrubLineColor
          ..strokeWidth = 1,
      );
      canvas.drawCircle(sp, 10, Paint()..color = cur.withOpacity(0.28));
      canvas.drawCircle(sp, 5, Paint()..color = cur);
      canvas.drawCircle(sp, 2, Paint()..color = Colors.white);
    }

    // exit tag
    if (exitPop > 0) {
      final xp = pt(exitX);
      _tag(canvas, 'SELL', Offset(xp.dx, xp.dy - 18), cur, exitPop, size);
    }
  }

  @override
  bool shouldRepaint(covariant _ReplayChartPainter old) => true;
}

/* ════════════════════════════════════════════════════════════════════════
   INDEX PICKER SHEET
   ════════════════════════════════════════════════════════════════════════ */

class _IndexPickerSheet extends StatefulWidget {
  const _IndexPickerSheet();

  @override
  State<_IndexPickerSheet> createState() => _IndexPickerSheetState();
}

class _IndexPickerSheetState extends State<_IndexPickerSheet>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _loop;

  Animation<double> _iv(double a, double b) => CurvedAnimation(
      parent: _entry, curve: Interval(a, b, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..forward();
    _loop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
  }

  @override
  void dispose() {
    _entry.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _go(String index) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, __, ___) => StrategyBuilderPage(initialIndex: index),
      transitionsBuilder: (_, anim, __, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    ));
  }

  Widget _stagger(Animation<double> a, Widget child) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position:
              Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.black.withOpacity(0.08);

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          _stagger(
            _iv(0.0, 0.4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Backtest an index',
                    style: TextStyle(
                        color: titleColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Pick one to start. You can switch inside the builder.',
                    style: TextStyle(color: subColor, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _stagger(_iv(0.12, 0.5), const _HowItWorksRow()),
          const SizedBox(height: 18),
          _stagger(
            _iv(0.25, 0.65),
            _IndexCard(
              label: 'NIFTY',
              subtitle: 'Broad market · 50 stocks',
              color: _blue,
              data: const [0.2, 0.28, 0.24, 0.4, 0.35, 0.5, 0.46, 0.62, 0.7],
              entry: _entry,
              loop: _loop,
              onTap: () => _go('NIFTY'),
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 12),
          _stagger(
            _iv(0.38, 0.78),
            _IndexCard(
              label: 'BANKNIFTY',
              subtitle: 'Banking sector · bigger swings',
              color: const Color(0xFF14B8A6),
              data: const [0.5, 0.36, 0.44, 0.25, 0.4, 0.3, 0.55, 0.48, 0.8],
              entry: _entry,
              loop: _loop,
              onTap: () => _go('BANKNIFTY'),
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 16),
          _stagger(
            _iv(0.55, 1.0),
            Row(
              children: [
                Icon(Icons.history_rounded, size: 14, color: subColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      'Uses real historical prices — what actually happened, not predictions.',
                      style: TextStyle(color: subColor, fontSize: 11.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksRow extends StatelessWidget {
  const _HowItWorksRow();

  Widget _item(IconData icon, String label, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: c.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: c),
              const SizedBox(height: 5),
              Text(label,
                  style: TextStyle(
                      color: c, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _arrow(bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(Icons.chevron_right_rounded,
            size: 16, color: isDark ? Colors.white24 : Colors.black26),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        _item(Icons.swap_vert_rounded, 'Buy / Sell', _blue),
        _arrow(isDark),
        _item(Icons.swipe_rounded, 'Slide time', const Color(0xFFA78BFA)),
        _arrow(isDark),
        _item(Icons.paid_rounded, 'See P&L', _green),
      ],
    );
  }
}

class _IndexCard extends StatefulWidget {
  final String label, subtitle;
  final Color color;
  final List<double> data;
  final Animation<double> entry, loop;
  final VoidCallback onTap;
  final bool isDark;

  const _IndexCard({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.data,
    required this.entry,
    required this.loop,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_IndexCard> createState() => _IndexCardState();
}

class _IndexCardState extends State<_IndexCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = widget.isDark ? Colors.white60 : const Color(0xFF64748B);

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [c.withOpacity(0.20), c.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: c.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(widget.subtitle,
                        style: TextStyle(color: subColor, fontSize: 11.5)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Start backtest',
                            style: TextStyle(
                                color: c,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        AnimatedBuilder(
                          animation: widget.loop,
                          builder: (_, __) => Transform.translate(
                            offset: Offset(
                                3 * math.sin(widget.loop.value * 2 * math.pi),
                                0),
                            child: Icon(Icons.arrow_forward_rounded,
                                size: 15, color: c),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 110,
                height: 56,
                child: AnimatedBuilder(
                  animation: Listenable.merge([widget.entry, widget.loop]),
                  builder: (_, __) => CustomPaint(
                    painter: _SparkPainter(
                      data: widget.data,
                      color: c,
                      progress: Curves.easeOut.transform(
                          ((widget.entry.value - 0.3) / 0.7).clamp(0.0, 1.0)),
                      pulse: widget.loop.value,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double progress, pulse;
  _SparkPainter({
    required this.data,
    required this.color,
    required this.progress,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final w = size.width - pad * 2, h = size.height - pad * 2;
    double val(double x) {
      final pos = x * (data.length - 1);
      final i = pos.floor().clamp(0, data.length - 2);
      return data[i] + (data[i + 1] - data[i]) * (pos - i);
    }

    Offset pt(double x) => Offset(pad + x * w, pad + (1 - val(x)) * h);

    const n = 60;
    final lim = (progress * n).floor();
    if (lim < 1) return;

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var k = 1; k <= lim; k++) {
      final p = pt(k / n);
      line.lineTo(p.dx, p.dy);
    }
    final tip = pt(lim / n);

    final fill = Path.from(line)
      ..lineTo(tip.dx, size.height)
      ..lineTo(pad, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.35), color.withOpacity(0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(tip, 4 + 6 * pulse,
        Paint()..color = color.withOpacity(0.4 * (1 - pulse)));
    canvas.drawCircle(tip, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}
