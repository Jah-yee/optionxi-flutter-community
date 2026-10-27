import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Fixed-height promo card. Follows Theme brightness (light / dark).
/// Layout: header text -> demo container (non-interactive) -> CTA block.
///
/// const VirtualTradingCard()
/// VirtualTradingCard(onTap: () => Get.to(() => const PracticeTradingPage()))
class VirtualTradingCard extends StatefulWidget {
  const VirtualTradingCard({
    super.key,
    this.onTap,
    this.height = 420,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final VoidCallback? onTap;
  final double height;
  final EdgeInsets margin;

  @override
  State<VirtualTradingCard> createState() => _VirtualTradingCardState();
}

/// Palette. Flat surfaces, one brand blue, green/red only for market meaning.
class _C {
  const _C({
    required this.dark,
    required this.card,
    required this.border,
    required this.shadow,
    required this.stage,
    required this.stageBorder,
    required this.text,
    required this.sub,
    required this.track,
    required this.accent,
    required this.up,
    required this.down,
    required this.amber,
  });

  final bool dark;
  final Color card, border, shadow, stage, stageBorder;
  final Color text, sub, track;
  final Color accent, up, down, amber;

  static const light = _C(
    dark: false,
    card: Color(0xFFFFFFFF),
    border: Color(0xFFE6E9EF),
    shadow: Color(0x14101828),
    stage: Color(0xFFF4F6FA),
    stageBorder: Color(0xFFE9ECF2),
    text: Color(0xFF0F172A),
    sub: Color(0xFF64748B),
    track: Color(0xFFD9DEE7),
    accent: Color(0xFF2F6BFF),
    up: Color(0xFF0E9F6E),
    down: Color(0xFFE5484D),
    amber: Color(0xFFB45309),
  );

  static const darkTheme = _C(
    dark: true,
    card: Color(0xFF17191E),
    border: Color(0xFF262A32),
    shadow: Color(0x66000000),
    stage: Color(0xFF1F2229),
    stageBorder: Color(0xFF2A2E37),
    text: Color(0xFFF3F4F6),
    sub: Color(0xFF9AA3B2),
    track: Color(0xFF343842),
    accent: Color(0xFF4C82FF),
    up: Color(0xFF2DD4A0),
    down: Color(0xFFFF6B6B),
    amber: Color(0xFFFBBF24),
  );

  static _C of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? darkTheme : light;
}

class _VirtualTradingCardState extends State<VirtualTradingCard>
    with SingleTickerProviderStateMixin {
  // seconds per phase: trade, pnl, options, rank
  static const _dur = [4.4, 3.0, 3.2, 3.4];
  static const _total = 14.0;

  static const _captions = [
    'Buy with your virtual cash',
    'Watch your P&L move live',
    'Practice with the option chain',
    'Beat others. Climb the leaderboard',
  ];

  static const _spent = 17096; // 10 x 1709.60
  static const _cashAfterBuy = 300000 - _spent;

  late final AnimationController _tl;
  _C c = _C.light;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _tl = AnimationController(
        vsync: this, duration: Duration(milliseconds: (_total * 1000).round()))
      ..repeat();
  }

  @override
  void dispose() {
    _tl.dispose();
    super.dispose();
  }

  void _go() {
    HapticFeedback.lightImpact();
    (widget.onTap ?? () => Get.toNamed('/virtual-trading'))();
  }

  // ---------- helpers ----------
  static double _p(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  static (int, double) _phaseOf(double s) {
    var acc = 0.0;
    for (var i = 0; i < _dur.length; i++) {
      if (s < acc + _dur[i]) return (i, (s - acc) / _dur[i]);
      acc += _dur[i];
    }
    return (_dur.length - 1, 1.0);
  }

  static String _grp(int v) {
    final s = v.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }

  static String _signed(int v) => '${v >= 0 ? '+' : '−'}₹${_grp(v.abs())}';

  static String _fmt2(double v) {
    final cents = (v * 100).round();
    return '${_grp(cents ~/ 100)}.${(cents % 100).toString().padLeft(2, '0')}';
  }

  static double _cash(int ph, double lt) {
    if (ph == 0) {
      return 300000 - _spent * Curves.easeOut.transform(_p(lt, .72, .9));
    }
    return _cashAfterBuy.toDouble();
  }

  (String?, Color) _chipFor(int ph, double lt) {
    switch (ph) {
      case 0:
        return (lt > .72 ? '−₹${_grp(_spent)} spent' : null, c.amber);
      case 1:
        return (lt > .2 ? '+₹1,240 P&L' : null, c.up);
      case 2:
        return ('+₹1,240 P&L', c.up);
      default:
        return (lt > .55 ? 'Rank #3 ▲1' : 'Rank #4', c.accent);
    }
  }

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    c = _C.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: _go,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(
                  color: c.shadow, blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: AnimatedBuilder(
            animation: _tl,
            builder: (_, __) {
              final s = _tl.value * _total;
              final (ph, lt) = _phaseOf(s);
              final (chipText, chipColor) = _chipFor(ph, lt);
              return Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(s),
                  _demo(ph, lt, chipText, chipColor),
                  _cta(s),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------- 1. header: plain text ----------
  Widget _header(double s) {
    final p = (math.sin(s * 2 * math.pi / 2.5) + 1) / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: c.up.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.up,
                      boxShadow: [
                        BoxShadow(
                            color: c.up.withOpacity(0.55 * p),
                            blurRadius: 5 + 4 * p,
                            spreadRadius: 1 + 2 * p),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('PRACTICE MODE',
                      style: TextStyle(
                          color: c.up,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8)),
                ],
              ),
            ),
            const Spacer(),
            Text('Educational • No real money',
                style: TextStyle(
                    color: c.sub, fontSize: 10.5, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 10),
        Text('Practice trading, risk-free',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.text,
                fontSize: 19,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
        const SizedBox(height: 2),
        Text('Free ₹3,00,000 virtual cash, every day',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.sub,
                fontSize: 12.5,
                height: 1.2,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ---------- 2. demo container: non-interactive ----------
  Widget _demo(int ph, double lt, String? chip, Color chipColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.stage,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.stageBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hero(_cash(ph, lt), chip, chipColor),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (w, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position:
                        Tween(begin: const Offset(0, 0.08), end: Offset.zero)
                            .animate(a),
                    child: w,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(ph),
                  child: SizedBox.expand(child: _stageBody(ph, lt)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _caption(ph, lt),
        ],
      ),
    );
  }

  Widget _hero(double cash, String? chip, Color chipColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Virtual cash',
                  style: TextStyle(
                      color: c.sub,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500)),
              Text('₹${_grp(cash.round())}',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 30,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (w, a) => FadeTransition(
              opacity: a, child: ScaleTransition(scale: a, child: w)),
          child: chip == null
              ? const SizedBox(key: ValueKey('none'), height: 26)
              : Container(
                  key: ValueKey(chip),
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: chipColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(chip,
                      style: TextStyle(
                          color: chipColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800)),
                ),
        ),
      ],
    );
  }

  Widget _stageBody(int ph, double lt) {
    switch (ph) {
      case 0:
        return _tradeStage(lt);
      case 1:
        return _pnlStage(lt);
      case 2:
        return _optionStage(lt);
      default:
        return _rankStage(lt);
    }
  }

  // 0: buy. No buttons: flat tag, plain qty, tinted order strip.
  Widget _tradeStage(double lt) {
    final qty = lt < .18 ? 1 : (lt < .28 ? 3 : (lt < .38 ? 6 : 10));
    final placed = lt > .72;
    final rp = _p(lt, .62, .78);
    final flash = (rp > 0 && rp < 1) ? math.sin(math.pi * rp) : 0.0;
    final stripOpacity = placed ? 0.2 : 0.1 + 0.25 * flash;

    return Column(children: [
      SizedBox(
        height: 22,
        child: Row(children: [
          Text('ADANIPORTS',
              style: TextStyle(
                  color: c.text, fontSize: 14, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('₹1,709.60',
              style: TextStyle(
                  color: c.text, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
                color: c.down.withOpacity(0.14),
                borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.center,
            child: Text('▼ 2.31%',
                style: TextStyle(
                    color: c.down, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 24,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: c.up.withOpacity(0.14),
                borderRadius: BorderRadius.circular(6)),
            child: Text('BUY',
                style: TextStyle(
                    color: c.up, fontSize: 10.5, fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          Text('Qty  ', style: TextStyle(color: c.sub, fontSize: 11.5)),
          Text('$qty',
              style: TextStyle(
                  color: c.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
      const SizedBox(height: 10),
      Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.up.withOpacity(stripOpacity),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(placed ? '✓ Order placed · Bought 10' : 'Order · BUY $qty',
            style: TextStyle(
                color: c.up,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3)),
      ),
    ]);
  }

  // 1: P&L moves
  Widget _pnlStage(double lt) {
    final e = Curves.easeOut.transform(_p(lt, .05, .8));
    final pl = (1240 * e).round();
    final price = 1709.60 + 124 * e;
    return Column(children: [
      SizedBox(
        height: 20,
        child: Row(children: [
          Text('ADANIPORTS · 10 qty',
              style: TextStyle(
                  color: c.sub, fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('₹${_fmt2(price)}',
              style: TextStyle(
                  color: c.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
      const SizedBox(height: 4),
      SizedBox(
        height: 50,
        width: double.infinity,
        child: CustomPaint(
          painter: _SparkPainter(
            e,
            line: c.up,
            entry: c.sub.withOpacity(0.5),
            fill: c.up.withOpacity(0.12),
            dot: c.stage,
          ),
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(
        height: 22,
        child: Row(children: [
          Text('Unrealised P&L', style: TextStyle(color: c.sub, fontSize: 11)),
          const Spacer(),
          Text(_signed(pl),
              style: TextStyle(
                  color: c.up,
                  fontSize: 18,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    ]);
  }

  // 2: option chain
  Widget _optionStage(double lt) {
    const strikes = ['24,800', '24,850', '24,900'];
    const calls = [.35, .6, .95];
    const puts = [.9, .65, .3];
    const callTxt = ['4.1L', '7.0L', '11L'];
    const putTxt = ['10L', '7.6L', '3.5L'];
    final pulse = (math.sin(lt * 2 * math.pi * 3) + 1) / 2;

    Widget head(String t, Alignment a) => Expanded(
          child: Align(
            alignment: a,
            child: Text(t,
                style: TextStyle(
                    color: c.sub,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
          ),
        );

    return Column(children: [
      SizedBox(
        height: 14,
        child: Row(children: [
          head('CALLS · OI', Alignment.centerLeft),
          const SizedBox(width: 64),
          head('PUTS · OI', Alignment.centerRight),
        ]),
      ),
      for (var i = 0; i < 3; i++) ...[
        const SizedBox(height: 3),
        Builder(builder: (_) {
          final g =
              Curves.easeOut.transform(_p(lt, .05 + .12 * i, .5 + .12 * i));
          final atm = i == 1;
          return Container(
            height: 24,
            decoration: BoxDecoration(
              color: atm ? c.accent.withOpacity(0.08 + 0.07 * pulse) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Expanded(
                child: Stack(children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: calls[i] * g,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                            color: c.down.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Opacity(
                        opacity: g,
                        child: Text(callTxt[i],
                            style: TextStyle(
                                color: c.sub,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ]),
              ),
              SizedBox(
                width: 64,
                child: Center(
                  child: Text(strikes[i],
                      style: TextStyle(
                          color: c.text,
                          fontSize: 11.5,
                          fontWeight: atm ? FontWeight.w800 : FontWeight.w600)),
                ),
              ),
              Expanded(
                child: Stack(children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: puts[i] * g,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                            color: c.up.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Opacity(
                        opacity: g,
                        child: Text(putTxt[i],
                            style: TextStyle(
                                color: c.sub,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          );
        }),
      ],
    ]);
  }

  // 3: leaderboard
  Widget _rankStage(double lt) {
    final s = Curves.easeInOutCubic.transform(_p(lt, .45, .75));
    const stride = 25.0;

    Widget row(int order, double pos, int rank, String name, String pct,
        {bool you = false}) {
      final a = _p(lt, .06 * order, .2 + .06 * order);
      final medal = rank == 1
          ? const Color(0xFFF5B301)
          : rank == 2
              ? const Color(0xFF9CA3AF)
              : rank == 3
                  ? const Color(0xFFC2793B)
                  : c.track;
      final onMedal = rank <= 3 ? Colors.white : c.sub;
      return Positioned(
        top: pos * stride,
        left: 0,
        right: 0,
        height: 21,
        child: Opacity(
          opacity: a,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: you ? c.accent : c.card,
              borderRadius: BorderRadius.circular(8),
              boxShadow: you
                  ? [
                      BoxShadow(
                          color: c.accent.withOpacity(0.4 * s), blurRadius: 10)
                    ]
                  : null,
            ),
            child: Row(children: [
              Container(
                width: 15,
                height: 15,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: medal),
                child: Text('$rank',
                    style: TextStyle(
                        color: onMedal,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Text(name,
                  style: TextStyle(
                      color: you ? Colors.white : c.text,
                      fontSize: 11.5,
                      fontWeight: you ? FontWeight.w800 : FontWeight.w600)),
              const Spacer(),
              if (you && s > .9)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('▲ 1',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800)),
                ),
              Text(pct,
                  style: TextStyle(
                      color: you ? Colors.white : c.up,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
    }

    return Stack(children: [
      row(0, 0, 1, 'Arjun K', '+8.4%'),
      row(1, 1, 2, 'Meera S', '+6.9%'),
      row(2, 2 + s, s > .5 ? 4 : 3, 'Rahul P', '+5.2%'),
      row(3, 3 - s, s > .5 ? 3 : 4, 'You', s > .5 ? '+5.8%' : '+4.6%',
          you: true),
    ]);
  }

  // ---------- caption + step indicator (not tappable) ----------
  Widget _caption(int ph, double lt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 18,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (w, a) => FadeTransition(opacity: a, child: w),
            layoutBuilder: (cur, prev) => Stack(
              alignment: Alignment.centerLeft,
              children: [...prev, if (cur != null) cur],
            ),
            child: Text(_captions[ph],
                key: ValueKey(ph),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.sub, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < _dur.length; i++) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(children: [
                  Container(height: 3, color: c.track),
                  FractionallySizedBox(
                    widthFactor: i < ph ? 1 : (i == ph ? lt : 0),
                    child: Container(height: 3, color: c.sub),
                  ),
                ]),
              ),
            ),
            if (i < _dur.length - 1) const SizedBox(width: 4),
          ],
        ]),
      ],
    );
  }

  // ---------- 3. CTA: only solid brand block + only real button ----------
  Widget _cta(double s) {
    final glow = (math.sin(s * 2 * math.pi / 2.0) + 1) / 2;
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: c.accent.withOpacity(0.18 + 0.14 * glow),
              blurRadius: 10 + 6 * glow,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Want to try it yourself?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 11.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600)),
              const Text('Start practicing, it’s free',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Transform.scale(
          scale: 1 + 0.03 * glow,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Try now',
                    style: TextStyle(
                        color: c.dark ? const Color(0xFF1F4FD6) : c.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Transform.translate(
                  offset: Offset(2.5 * math.sin(s * 2 * math.pi / 1.4), 0),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 18,
                      color: c.dark ? const Color(0xFF1F4FD6) : c.accent),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

/// Rising price line with dashed entry level. p = 0..1 draw progress.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.p,
      {required this.line,
      required this.entry,
      required this.fill,
      required this.dot});
  final double p;
  final Color line, entry, fill, dot;

  static const _pts = [0.72, 0.64, 0.68, 0.52, 0.56, 0.40, 0.44, 0.24, 0.14];

  @override
  void paint(Canvas canvas, Size size) {
    final offs = [
      for (var i = 0; i < _pts.length; i++)
        Offset(size.width * i / (_pts.length - 1), size.height * _pts[i])
    ];

    final entryPaint = Paint()
      ..color = entry
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(
          Offset(x, offs.first.dy), Offset(x + 4, offs.first.dy), entryPaint);
    }

    if (p <= 0) return;
    final path = Path()..moveTo(offs.first.dx, offs.first.dy);
    for (final o in offs.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    final m = path.computeMetrics().first;
    final part = m.extractPath(0, m.length * p);
    final tip = m.getTangentForOffset(m.length * p)!.position;

    final area = Path.from(part)
      ..lineTo(tip.dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);

    canvas.drawPath(
        part,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(tip, 6, Paint()..color = line.withOpacity(0.25));
    canvas.drawCircle(tip, 3.6, Paint()..color = line);
    canvas.drawCircle(tip, 1.6, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.p != p || old.line != line || old.fill != fill;
}
