// ─────────────────────────────────────────────────────────────────────────
// Backtesting home banner (redesign)
//
// One looping, self-playing story inside the card:
//   1. 5-minute candles draw in
//   2. a condition is added (20 SMA crosses 20 EMA)
//   3. a scanner sweeps the chart and pins every time it fired
//      (bullish or bearish)
//   4. for each pin, the NEXT 3 candles (3 x 5 min = 15 min) are checked
//      and stamped Right or Wrong
//   5. a hit-rate summary, then a Pro push-notification preview for
//      live alerts on Nifty and Bank Nifty
//
// The crossovers, outcomes and hit-rate are computed from the demo candles
// by the same rules the copy describes, they are not hard-coded.
//
// Usage (all params optional, so the old call still works):
//   BacktestingHomeSection(
//     isPro: user.isPro,
//     onAlertsTap: () => Navigator.push(...AlertsPage),   // Pro users
//     onUpgradeTap: () => Navigator.push(...PaywallPage), // free users
//   )
// ─────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:optionxi/Main_Pages/IndicatorBacktest/algo_marketplace.dart';
import 'package:optionxi/Main_Pages/IndicatorBacktest/indicator-backtest.dart';

// ─────────────────────────────────────────────
// PALETTE
// ─────────────────────────────────────────────
class _P {
  const _P(this.dark);
  final bool dark;

  static const accent = Color(0xFF5B7FFF);
  static const up = Color(0xFF12B886);
  static const upDeep = Color(0xFF0A8F63);
  static const down = Color(0xFFF0506E);
  static const warn = Color(0xFFE5603A);
  static const proInk = Color(0xFF3A2400);

  Color get cardA => dark ? const Color(0xFF171B3A) : const Color(0xFFEEF1FF);
  Color get cardB => dark ? const Color(0xFF0F1226) : const Color(0xFFFAFBFF);
  Color get panel => dark ? const Color(0xFF0A0D1F) : Colors.white;
  Color get border => dark ? const Color(0xFF272C55) : const Color(0xFFDDE2F7);
  Color get grid =>
      dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFEDEFFA);
  Color get text => dark ? const Color(0xFFF1F2FF) : const Color(0xFF14162B);
  Color get sub => dark ? const Color(0xFFA0A6D0) : const Color(0xFF646A8E);
  Color get chip =>
      dark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF2F4FF);
  Color get fastLine =>
      dark ? const Color(0xFF7C99FF) : const Color(0xFF3556F0);
  Color get slowLine =>
      dark ? const Color(0xFFFFB020) : const Color(0xFFD98200);
}

// ─────────────────────────────────────────────
// DEMO DATA + REAL SIGNAL LOGIC
// 20 SMA vs 20 EMA on 5-minute candles starting 09:15.
// Right/Wrong = is the close 3 candles later on the correct side of the
// close of the signal candle.
// ─────────────────────────────────────────────
class _Candle {
  const _Candle(this.o, this.h, this.l, this.c);
  final double o, h, l, c;
}

class _Signal {
  const _Signal(this.index, this.bullish, this.right);
  final int index;
  final bool bullish;
  final bool right;

  String get time {
    final m = 9 * 60 + 15 + 5 * index;
    final hh = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _Seg {
  const _Seg(this.fromIdx, this.toIdx, this.startW, this.endW, this.fast);
  final double fromIdx, toIdx, startW, endW;
  final bool fast;
}

class _Timeline {
  const _Timeline(this.segs, this.total);
  final List<_Seg> segs;
  final double total;
}

class _Demo {
  _Demo._();

  static const List<double> closes = [
    100, 99.2, 98.4, 98.9, 97.8, 97.0, 96.4, 96.9, 96.1, 95.6, //
    95.2, 95.9, 96.8, 97.9, 98.8, 99.9, 101.0, 101.6, 101.2, 102.1,
    102.8, 103.4, 102.9, 102.0, 101.2, 101.9, 102.6, 102.1, 101.4, 100.8,
    100.2, 100.9, 101.8, 102.6, 103.4, 104.1, 104.6, 105.2,
  ];
  static const List<double> _wicks = [0.35, 0.2, 0.45, 0.25, 0.3, 0.15];

  static int get n => closes.length;

  static final List<_Candle> candles = _buildCandles();
  static final List<double> fast = _ema(closes, 20); // 20 EMA
  static final List<double?> slow = _sma(closes, 20); // 20 SMA
  static final List<_Signal> signals = _findSignals();
  static final double minP = candles.map((c) => c.l).reduce(math.min);
  static final double maxP = candles.map((c) => c.h).reduce(math.max);
  static final _Timeline _timeline = _buildTimeline();

  static List<_Candle> _buildCandles() {
    final out = <_Candle>[];
    for (var i = 0; i < closes.length; i++) {
      final c = closes[i];
      final o = i == 0 ? c + 0.3 : closes[i - 1];
      final w1 = _wicks[i % _wicks.length];
      final w2 = _wicks[(i + 3) % _wicks.length];
      out.add(_Candle(o, math.max(o, c) + w1, math.min(o, c) - w2, c));
    }
    return out;
  }

  static List<double> _ema(List<double> x, int p) {
    final k = 2 / (p + 1);
    final out = <double>[x.first];
    for (var i = 1; i < x.length; i++) {
      out.add(x[i] * k + out.last * (1 - k));
    }
    return out;
  }

  static List<double?> _sma(List<double> x, int p) {
    final out = <double?>[];
    for (var i = 0; i < x.length; i++) {
      if (i < p - 1) {
        out.add(null);
      } else {
        var s = 0.0;
        for (var j = i - p + 1; j <= i; j++) {
          s += x[j];
        }
        out.add(s / p);
      }
    }
    return out;
  }

  static List<_Signal> _findSignals() {
    final out = <_Signal>[];
    for (var i = 1; i < closes.length; i++) {
      final s = slow[i];
      final sp = slow[i - 1];
      if (s == null || sp == null) continue;
      final up = fast[i - 1] <= sp && fast[i] > s;
      final down = fast[i - 1] >= sp && fast[i] < s;
      if (!up && !down) continue;
      if (i + 3 >= closes.length) continue; // needs 3 candles after it
      final right = up ? closes[i + 3] > closes[i] : closes[i + 3] < closes[i];
      out.add(_Signal(i, up, right));
    }
    return out;
  }

  // Scanner choreography: sprint between signals, slow down for the 3-candle
  // check after each one.
  static _Timeline _buildTimeline() {
    final segs = <_Seg>[];
    var w = 0.0;
    var idx = 0.0;
    void add(double to, double cost, bool fast) {
      final d = (to - idx).abs();
      if (d <= 0) return;
      segs.add(_Seg(idx, to, w, w + d * cost, fast));
      w += d * cost;
      idx = to;
    }

    for (final s in signals) {
      add(s.index.toDouble(), 1.0, true);
      add(s.index + 3.7, 3.2, false);
    }
    add((closes.length - 1).toDouble(), 1.0, true);
    return _Timeline(segs, w);
  }

  static const double scanStart = 0.24;
  static const double scanEnd = 0.80;

  /// Fractional candle index of the scanner at timeline position [t] (0..1).
  static double scanIdx(double t) {
    if (t <= scanStart) return -1;
    final u = ((t - scanStart) / (scanEnd - scanStart)).clamp(0.0, 1.0) *
        _timeline.total;
    for (final s in _timeline.segs) {
      if (u <= s.endW) {
        final local = (u - s.startW) / (s.endW - s.startW);
        final e = s.fast ? Curves.easeInOut.transform(local) : local;
        return s.fromIdx + (s.toIdx - s.fromIdx) * e;
      }
    }
    return (closes.length - 1).toDouble();
  }
}

// ─────────────────────────────────────────────
// STATUS LINE (the one sentence under the chart)
// ─────────────────────────────────────────────
class _Status {
  const _Status(this.key, this.icon, this.color, this.text);
  final int key;
  final IconData icon;
  final Color color;
  final String text;
}

_Status _statusFor(double t) {
  if (t < 0.12) {
    return const _Status(0, Icons.show_chart_rounded, _P.accent,
        'Loading recent 5-minute candles');
  }
  if (t < _Demo.scanStart) {
    return const _Status(1, Icons.tune_rounded, _P.accent,
        'Condition added: 20 SMA crosses 20 EMA');
  }
  if (t < _Demo.scanEnd) {
    final idx = _Demo.scanIdx(t);
    _Signal? cur;
    var ci = -1;
    for (var k = 0; k < _Demo.signals.length; k++) {
      if (idx >= _Demo.signals[k].index) {
        cur = _Demo.signals[k];
        ci = k;
      }
    }
    if (cur == null) {
      return const _Status(2, Icons.radar_rounded, _P.accent,
          'Scanning past candles for every time it happened');
    }
    final dir = cur.bullish ? 'Bullish' : 'Bearish';
    if (idx < cur.index + 3) {
      return _Status(
        10 + ci * 2,
        cur.bullish ? Icons.north_east_rounded : Icons.south_east_rounded,
        cur.bullish ? _P.up : _P.down,
        '$dir signal at ${cur.time}. Checking the next 3 candles (15 min)',
      );
    }
    final rose = cur.bullish == cur.right;
    return _Status(
      11 + ci * 2,
      cur.right ? Icons.check_circle_rounded : Icons.cancel_rounded,
      cur.right ? _P.up : _P.warn,
      '${cur.time} ${dir.toLowerCase()} signal was '
      '${cur.right ? 'right' : 'wrong'}: price ${rose ? 'rose' : 'fell'} '
      'over the next 15 min',
    );
  }
  final total = _Demo.signals.length;
  final hits = _Demo.signals.where((s) => s.right).length;
  final pct = total == 0 ? 0 : (hits * 100 / total).round();
  return _Status(90, Icons.insights_rounded, _P.accent,
      'In this sample, $hits of $total signals were right ($pct%)');
}

// ─────────────────────────────────────────────
// MAIN SECTION WIDGET
// ─────────────────────────────────────────────
class BacktestingHomeSection extends StatefulWidget {
  const BacktestingHomeSection({
    super.key,
    this.isPro = false,
    this.onTap,
    this.onAlertsTap,
    this.onUpgradeTap,
  });

  /// Pro users can create live alerts; everyone else sees the Pro lock.
  final bool isPro;

  /// Overrides the default "open algo picker" tap on the card.
  final VoidCallback? onTap;

  /// Pro: open your alert-creation screen.
  final VoidCallback? onAlertsTap;

  /// Free: open your paywall.
  final VoidCallback? onUpgradeTap;

  @override
  State<BacktestingHomeSection> createState() => _BacktestingHomeSectionState();
}

class _BacktestingHomeSectionState extends State<BacktestingHomeSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18));
  late final ValueNotifier<_Status> _status;
  final ValueNotifier<bool> _notif = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _status = ValueNotifier(_statusFor(0));
    _c.addListener(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      // Static final frame: everything drawn, results and summary visible.
      _c.stop();
      _c.value = 0.83;
    } else if (!_c.isAnimating) {
      _c.value = 0;
      _c.repeat();
    }
  }

  void _tick() {
    final t = _c.value;
    final s = _statusFor(t);
    if (s.key != _status.value.key) _status.value = s;
    final showNotif = t >= 0.855 && t < 0.965;
    if (showNotif != _notif.value) _notif.value = showNotif;
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    _status.dispose();
    _notif.dispose();
    super.dispose();
  }

  void _openPicker() => _openAlgoPicker(
        context,
        isPro: widget.isPro,
        onAlertsTap: widget.onAlertsTap,
        onUpgradeTap: widget.onUpgradeTap,
      );

  void _onCardTap() {
    HapticFeedback.selectionClick();
    (widget.onTap ?? _openPicker)();
  }

  void _onAlertTap() {
    HapticFeedback.selectionClick();
    final cb = widget.isPro ? widget.onAlertsTap : widget.onUpgradeTap;
    (cb ?? widget.onTap ?? _openPicker)();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = _P(dark);
    const radius = BorderRadius.all(Radius.circular(24));

    return Material(
      color: Colors.transparent,
      child: Ink(
        // decoration: BoxDecoration(
        //   borderRadius: radius,
        //   border: Border.all(color: p.border),
        //   gradient: LinearGradient(
        //     colors: [p.cardA, p.cardB],
        //     begin: Alignment.topLeft,
        //     end: Alignment.bottomRight,
        //   ),
        //   boxShadow: dark
        //       ? null
        //       : [
        //           BoxShadow(
        //             color: _P.accent.withValues(alpha: 0.10),
        //             blurRadius: 24,
        //             offset: const Offset(0, 10),
        //           ),
        //         ],
        // ),
        child: InkWell(
          borderRadius: radius,
          onTap: _onCardTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(p),
                const SizedBox(height: 14),
                _panel(p),
                const SizedBox(height: 10),
                _alertStrip(p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Headline ────────────────────────────────
  Widget _header(_P p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Would your idea have worked?',
                style: TextStyle(
                  fontSize: 19,
                  height: 1.15,
                  letterSpacing: -0.4,
                  fontWeight: FontWeight.w800,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Backtest a condition on past candles. See each signal and '
                'whether the next 15 minutes proved it right.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.35, color: p.sub),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _P.accent,
          ),
          child: const Icon(Icons.arrow_forward_rounded,
              color: Colors.white, size: 20),
        ),
      ],
    );
  }

  // ── Chart panel ─────────────────────────────
  Widget _panel(_P p) {
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.border),
        ),
        child: AnimatedBuilder(
          animation: _c,
          // Fade the whole panel out at the end so the loop restarts cleanly.
          builder: (_, child) {
            final t = _c.value;
            final f = t > 0.965 ? 1 - (t - 0.965) / 0.035 : 1.0;
            return Opacity(opacity: f.clamp(0.0, 1.0), child: child);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _conditionRow(p)),
                  const SizedBox(width: 8),
                  // _pill(p, '5 min'),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 172,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _ChartPainter(anim: _c, p: p),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _statusLine(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(_P p, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: p.chip,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: p.sub),
        ),
      );

  Widget _conditionRow(_P p) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        Widget pop(int k, Widget child) {
          final v = Curves.easeOutBack.transform(
              ((_c.value - 0.02 - 0.035 * k) / 0.05).clamp(0.0, 1.0));
          return Opacity(
            opacity: v.clamp(0.0, 1.0).toDouble(),
            child: Transform.scale(scale: 0.85 + 0.15 * v, child: child),
          );
        }

        return Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            pop(
              0,
              Text('When',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: p.sub)),
            ),
            pop(1, _token(p, '20 SMA', dot: p.fastLine)),
            pop(2, _token(p, 'crosses')),
            pop(3, _token(p, '20 EMA', dot: p.slowLine)),
          ],
        );
      },
    );
  }

  Widget _token(_P p, String label, {Color? dot}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: p.chip,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: p.text),
            ),
          ],
        ),
      );

  Widget _statusLine(_P p) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: ValueListenableBuilder<_Status>(
        valueListenable: _status,
        builder: (_, s, __) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
                      .animate(anim),
              child: child,
            ),
          ),
          child: Row(
            key: ValueKey(s.key),
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.color.withValues(alpha: 0.16),
                ),
                child: Icon(s.icon, size: 15, color: s.color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  s.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Alert strip (Pro) ───────────────────────
  double _bellAngle(double t) {
    if (t < 0.855 || t > 0.93) return 0;
    final u = (t - 0.855) / 0.075;
    return math.sin(u * math.pi * 7) * 0.38 * (1 - u);
  }

  Widget _alertStrip(_P p) {
    const r = BorderRadius.all(Radius.circular(16));
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: p.dark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: r,
          border: Border.all(color: p.border),
        ),
        child: InkWell(
          borderRadius: r,
          onTap: _onAlertTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, child) => Transform.rotate(
                    angle: _bellAngle(_c.value),
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _P.accent.withValues(alpha: 0.15),
                    ),
                    child: const Icon(Icons.notifications_active_rounded,
                        size: 20, color: _P.accent),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _notif,
                      builder: (_, on, __) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            ...previous,
                            if (current != null) current,
                          ],
                        ),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                                    begin: const Offset(0, 0.4),
                                    end: Offset.zero)
                                .animate(anim),
                            child: child,
                          ),
                        ),
                        child: on
                            ? _stripText(
                                p,
                                key: const ValueKey('notif'),
                                title: 'Nifty: bullish signal',
                                body: '20 SMA crossed above 20 EMA, just now',
                              )
                            : _stripText(
                                p,
                                key: const ValueKey('idle'),
                                title: 'Get alerted when it happens',
                                body:
                                    'Live on Nifty and Bank Nifty, 5-min candles',
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ProPill(isPro: widget.isPro),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stripText(_P p,
      {required Key key, required String title, required String body}) {
    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: p.text),
        ),
        const SizedBox(height: 2),
        Text(
          body,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: p.sub),
        ),
      ],
    );
  }
}

class _ProPill extends StatelessWidget {
  const _ProPill({required this.isPro});
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    if (isPro) {
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
        decoration: BoxDecoration(
          color: _P.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Set up',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _P.accent)),
            Icon(Icons.chevron_right_rounded, size: 16, color: _P.accent),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
            colors: [Color(0xFFFFD36E), Color(0xFFFF9F1C)]),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 11, color: _P.proInk),
          SizedBox(width: 4),
          Text('Pro',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: _P.proInk)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CHART PAINTER, driven directly by the controller
// ─────────────────────────────────────────────
class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.anim, required this.p}) : super(repaint: anim);

  final Animation<double> anim;
  final _P p;

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    final n = _Demo.n;

    const top = 30.0; // room above the chart for Right/Wrong chips
    final bottom = size.height - 20.0; // room below for 1-2-3 badges
    final yTop = top + 8;
    final yBot = bottom - 8;
    final span = _Demo.maxP - _Demo.minP;
    double yOf(double v) => yBot - (v - _Demo.minP) / span * (yBot - yTop);
    final slot = size.width / n;
    double xOf(num i) => slot * (i + 0.5);

    // grid
    final gridPaint = Paint()
      ..color = p.grid
      ..strokeWidth = 1;
    for (var k = 0; k < 4; k++) {
      final y = top + (bottom - top) * k / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // candles grow out of their open price, left to right
    final reveal =
        Curves.easeOutCubic.transform((t / 0.16).clamp(0.0, 1.0)) * n;
    final bodyW = math.min(slot * 0.56, 6.0);
    final wick = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final body = Paint();
    for (var i = 0; i < n; i++) {
      final a = (reveal - i).clamp(0.0, 1.0);
      if (a <= 0) break;
      final c = _Demo.candles[i];
      final col = c.c >= c.o ? _P.up : _P.down;
      final base = yOf(c.o);
      double y(double v) => base + (yOf(v) - base) * a;
      final x = xOf(i);
      wick.color = col.withValues(alpha: 0.85 * a);
      canvas.drawLine(Offset(x, y(c.h)), Offset(x, y(c.l)), wick);
      final bt = math.min(y(c.o), y(c.c));
      final bb = math.max(y(c.o), y(c.c));
      body.color = col.withValues(alpha: a);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
              x - bodyW / 2, bt, x + bodyW / 2, math.max(bb, bt + 1.5)),
          const Radius.circular(1.2),
        ),
        body,
      );
    }

    // indicator lines draw themselves
    final lineP = ((t - 0.14) / 0.12).clamp(0.0, 1.0);
    if (lineP > 0) {
      final end = Curves.easeInOut.transform(lineP) * (n - 1);
      _drawSeries(
        canvas,
        _Demo.slow,
        end,
        xOf,
        yOf,
        Paint()
          ..color = p.slowLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      _drawSeries(
        canvas,
        _Demo.fast,
        end,
        xOf,
        yOf,
        Paint()
          ..color = p.fastLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final idx = _Demo.scanIdx(t);
    if (idx < 0) return;

    // signals: bracket, pin, 1-2-3 badges, Right/Wrong chip
    for (final s in _Demo.signals) {
      if (idx < s.index) continue;
      _drawSignal(canvas, size, s, idx, slot, top, bottom, xOf, yOf);
    }

    // scanner line + soft trail
    final fadeIn = ((t - _Demo.scanStart) / 0.02).clamp(0.0, 1.0);
    final fadeOut = 1 - ((t - (_Demo.scanEnd - 0.02)) / 0.02).clamp(0.0, 1.0);
    final sa = math.min(fadeIn, fadeOut);
    if (sa > 0) {
      final sx = xOf(idx);
      final trail = Rect.fromLTRB(sx - 36, top, sx, bottom);
      canvas.drawRect(
        trail,
        Paint()
          ..shader = LinearGradient(
            colors: [
              _P.accent.withValues(alpha: 0),
              _P.accent.withValues(alpha: 0.20 * sa),
            ],
          ).createShader(trail),
      );
      canvas.drawLine(
        Offset(sx, top),
        Offset(sx, bottom),
        Paint()
          ..color = _P.accent.withValues(alpha: sa)
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(
          Offset(sx, top), 3, Paint()..color = _P.accent.withValues(alpha: sa));
    }
  }

  void _drawSignal(
    Canvas canvas,
    Size size,
    _Signal s,
    double idx,
    double slot,
    double top,
    double bottom,
    double Function(num) xOf,
    double Function(double) yOf,
  ) {
    final sx = xOf(s.index);
    final dirColor = s.bullish ? _P.up : _P.down;

    // 3-candle check window (the next 15 minutes)
    final x0 = slot * (s.index + 1);
    final frac = ((idx - s.index) / 3).clamp(0.0, 1.0);
    final x1 = x0 + slot * 3 * frac;
    if (x1 > x0) {
      canvas.drawRect(
        Rect.fromLTRB(x0, top, x1, bottom),
        Paint()..color = _P.accent.withValues(alpha: 0.10),
      );
      final edge = Paint()
        ..color = _P.accent.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x0, top), Offset(x0, bottom), edge);
      if (frac >= 1) {
        canvas.drawLine(Offset(x1, top), Offset(x1, bottom), edge);
      }
    }

    // pin
    final pop =
        Curves.easeOutBack.transform(((idx - s.index) / 0.5).clamp(0.0, 1.0));
    final c = _Demo.candles[s.index];
    final anchorY = s.bullish ? yOf(c.l) + 2 : yOf(c.h) - 2;
    final pinY = s.bullish ? yOf(c.l) + 17 : yOf(c.h) - 17;

    final rp = ((idx - s.index) / 1.4).clamp(0.0, 1.0);
    if (rp < 1) {
      canvas.drawCircle(
        Offset(sx, pinY),
        9 + 16 * rp,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = dirColor.withValues(alpha: 0.5 * (1 - rp)),
      );
    }
    canvas.drawLine(
      Offset(sx, anchorY),
      Offset(sx, pinY),
      Paint()
        ..color = dirColor.withValues(alpha: 0.6 * pop.clamp(0.0, 1.0))
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(Offset(sx, pinY), 9 * pop, Paint()..color = dirColor);
    // bullish points up, bearish points down
    final arrowUp = Path()
      ..moveTo(sx, pinY - 3.8 * pop)
      ..lineTo(sx - 3.6 * pop, pinY + 2.8 * pop)
      ..lineTo(sx + 3.6 * pop, pinY + 2.8 * pop)
      ..close();
    final arrowDown = Path()
      ..moveTo(sx, pinY + 3.8 * pop)
      ..lineTo(sx - 3.6 * pop, pinY - 2.8 * pop)
      ..lineTo(sx + 3.6 * pop, pinY - 2.8 * pop)
      ..close();
    canvas.drawPath(
        s.bullish ? arrowUp : arrowDown, Paint()..color = Colors.white);

    // where the lines actually crossed
    final cy = yOf(_Demo.fast[s.index]);
    canvas.drawCircle(Offset(sx, cy), 3.6 * pop, Paint()..color = p.panel);
    canvas.drawCircle(
      Offset(sx, cy),
      3.6 * pop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = p.fastLine,
    );

    // 1 - 2 - 3 badges under each checked candle
    for (var k = 1; k <= 3; k++) {
      final q = Curves.easeOutBack
          .transform(((idx - (s.index + k) + 0.5) / 0.5).clamp(0.0, 1.0));
      if (q <= 0) continue;
      final center = Offset(xOf(s.index + k), bottom + 10);
      canvas.drawCircle(center, 7 * q, Paint()..color = _P.accent);
      if (q > 0.6) {
        _drawText(canvas, '$k', center, 9 * q, Colors.white, FontWeight.w800);
      }
    }

    // verdict chip once the 3rd candle closes
    final vq = ((idx - (s.index + 3)) / 0.6).clamp(0.0, 1.0);
    if (vq > 0) {
      final e = Curves.easeOutBack.transform(vq);
      const w = 66.0;
      const h = 22.0;
      final cx = (x0 + slot * 1.5).clamp(w / 2 + 4, size.width - w / 2 - 4);
      final col = s.right ? _P.upDeep : _P.warn;
      canvas.save();
      canvas.translate(cx, 14);
      canvas.scale(e);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          const Radius.circular(11),
        ),
        Paint()..color = col,
      );
      final g = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      const gx = -w / 2 + 14;
      if (s.right) {
        canvas.drawPath(
          Path()
            ..moveTo(gx - 3.6, 0.4)
            ..lineTo(gx - 1, 3)
            ..lineTo(gx + 3.8, -2.8),
          g,
        );
      } else {
        canvas.drawLine(const Offset(gx - 3, -3), const Offset(gx + 3, 3), g);
        canvas.drawLine(const Offset(gx - 3, 3), const Offset(gx + 3, -3), g);
      }
      _drawText(canvas, s.right ? 'Right' : 'Wrong', const Offset(9, 0), 11,
          Colors.white, FontWeight.w800);
      canvas.restore();
    }
  }

  void _drawSeries(
    Canvas canvas,
    List<double?> v,
    double end,
    double Function(num) xOf,
    double Function(double) yOf,
    Paint paint,
  ) {
    final path = Path();
    var started = false;
    final last = end.floor();
    for (var i = 0; i <= last && i < v.length; i++) {
      final val = v[i];
      if (val == null) continue;
      final pt = Offset(xOf(i), yOf(val));
      if (!started) {
        path.moveTo(pt.dx, pt.dy);
        started = true;
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    final frac = end - last;
    if (started && frac > 0 && last + 1 < v.length) {
      final a = v[last];
      final b = v[last + 1];
      if (a != null && b != null) {
        final val = a + (b - a) * frac;
        path.lineTo(xOf(last + frac), yOf(val));
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawText(Canvas c, String s, Offset center, double size, Color color,
      FontWeight w) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style:
            TextStyle(fontSize: size, fontWeight: w, color: color, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.p.dark != p.dark;
}

// ─────────────────────────────────────────────
// ALGO PICKER SHEET
// ─────────────────────────────────────────────
void _openAlgoPicker(
  BuildContext context, {
  bool isPro = false,
  VoidCallback? onAlertsTap,
  VoidCallback? onUpgradeTap,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AlgoPickerSheet(
      isPro: isPro,
      onAlertsTap: onAlertsTap,
      onUpgradeTap: onUpgradeTap,
    ),
  );
}

class _AlgoPickerSheet extends StatelessWidget {
  const _AlgoPickerSheet({
    required this.isPro,
    this.onAlertsTap,
    this.onUpgradeTap,
  });

  final bool isPro;
  final VoidCallback? onAlertsTap;
  final VoidCallback? onUpgradeTap;

  void _go(BuildContext context, WidgetBuilder builder) {
    // Grab the navigator first: `context` is unsafe once the sheet is popped.
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: builder));
  }

  void _browseAlgos(BuildContext context) {
    final apiBaseUrl = dotenv.env['BACKTEST_API_BASE_URL']!;
    _go(
      context,
      (_) => CommunityAlgosBrowsePage(
        api: BacktestApiService(baseUrl: apiBaseUrl),
      ),
    );
  }

  void _myAlgos(BuildContext context) {
    _go(context, (_) => SavedBacktestsPage());
  }

  void _alerts(BuildContext context) {
    final cb = isPro ? onAlertsTap : onUpgradeTap;
    Navigator.of(context).pop();
    cb?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final hasAlertAction = (isPro ? onAlertsTap : onUpgradeTap) != null;

    return Material(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Start a backtest',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pick a ready-made algo or build your own condition.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            _Reveal(
              index: 0,
              child: _AlgoOptionCard(
                label: 'Algo marketplace',
                subtitle: 'Test strategies shared by the community',
                icon: Icons.travel_explore_rounded,
                color: const Color(0xFF2563EB),
                onTap: () => _browseAlgos(context),
              ),
            ),
            const SizedBox(height: 12),
            _Reveal(
              index: 1,
              child: _AlgoOptionCard(
                label: 'My algos',
                subtitle: 'Open saved strategies or build a new one',
                icon: Icons.auto_awesome_rounded,
                color: const Color(0xFF0D9488),
                onTap: () => _myAlgos(context),
              ),
            ),
            if (hasAlertAction) ...[
              const SizedBox(height: 12),
              _Reveal(
                index: 2,
                child: _AlgoOptionCard(
                  label: 'Live alerts',
                  subtitle: 'Get notified when a condition fires on '
                      'Nifty or Bank Nifty',
                  icon: Icons.notifications_active_rounded,
                  color: const Color(0xFFD98200),
                  tag: _ProPill(isPro: isPro),
                  onTap: () => _alerts(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small entrance for the sheet rows. It answers the tap that opened the
/// sheet, so it only plays once.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + index * 80),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: c),
      ),
      child: child,
    );
  }
}

class _AlgoOptionCard extends StatefulWidget {
  const _AlgoOptionCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.tag,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Widget? tag;

  @override
  State<_AlgoOptionCard> createState() => _AlgoOptionCardState();
}

class _AlgoOptionCardState extends State<_AlgoOptionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = widget.color;

    final cardColor = Color.alphaBlend(
      color.withValues(alpha: 0.07),
      scheme.surfaceContainerHigh,
    );

    return Semantics(
      button: true,
      label: '${widget.label}. ${widget.subtitle}',
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onHighlightChanged: (v) => setState(() => _pressed = v),
            splashColor: color.withValues(alpha: 0.12),
            highlightColor: color.withValues(alpha: 0.06),
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.22)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(color, Colors.white, 0.18)!,
                          color,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.label,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            if (widget.tag != null) ...[
                              const SizedBox(width: 8),
                              widget.tag!,
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.12),
                    ),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 18, color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
