import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:optionxi/Helpers/browser_lite.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

// ─── API ──────────────────────────────────────────────────────────────────────
String get kApiBase => dotenv.env['AI_NIFTYSUMMARY_URL']!;

// ─── Helpers ──────────────────────────────────────────────────────────────────
double _num(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
final _n0 = NumberFormat('#,##0');
final _n2 = NumberFormat('#,##0.00');
const _kIst = Duration(hours: 5, minutes: 30);
DateTime _toIst(DateTime dt) => dt.toUtc().add(_kIst);

// ─── Design tokens (light + dark) ─────────────────────────────────────────────
class T {
  static const up = Color(0xFF12A66A);
  static const down = Color(0xFFE04B4B);
  static const mid = Color(0xFFE39A1B);
  static const link = Color(0xFF2F6BFF);

  static bool dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color bg(BuildContext c) =>
      dark(c) ? const Color(0xFF0C1210) : const Color(0xFFF2F5F3);
  static Color surface(BuildContext c) =>
      dark(c) ? const Color(0xFF161E1B) : Colors.white;
  static Color alt(BuildContext c) =>
      dark(c) ? const Color(0xFF1E2824) : const Color(0xFFEBF0ED);
  static Color hair(BuildContext c) =>
      dark(c) ? const Color(0xFF2A3631) : const Color(0xFFDFE6E2);
  static Color ink(BuildContext c) =>
      dark(c) ? const Color(0xFFEAF1ED) : const Color(0xFF101815);
  static Color sub(BuildContext c) =>
      dark(c) ? const Color(0xFF93A39B) : const Color(0xFF55625C);
}

TextStyle _ts(BuildContext c,
        {double s = 14,
        FontWeight w = FontWeight.w500,
        Color? color,
        double h = 1.4,
        bool figures = false}) =>
    GoogleFonts.manrope(
      fontSize: s,
      fontWeight: w,
      color: color ?? T.ink(c),
      height: h,
      fontFeatures: figures ? const [FontFeature.tabularFigures()] : null,
    );

// ─── Models ───────────────────────────────────────────────────────────────────
class CandlePoint {
  final DateTime time;
  final double open, high, low, close;
  const CandlePoint({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });
  factory CandlePoint.fromJson(Map<String, dynamic> j) => CandlePoint(
        time: DateTime.parse(j['timestamp'] as String),
        open: _num(j['open']),
        high: _num(j['high']),
        low: _num(j['low']),
        close: _num(j['close']),
      );
}

class NiftySummary {
  final bool cached, marketOpen;
  final String lastUpdated;
  final double niftyLtp, niftyDayChangePct;
  final String marketSentiment, oneLiner, confidence;
  final double probabilityScore;
  final List<double> support, resistance;
  final Map<String, dynamic> tradeIdea;
  final List<String> keyObservations, riskFactors;
  final String atlasInterpretation, vixInterpretation, nifty5minInterpretation;
  final Map<String, dynamic> bollingerAnalysis, atlasAnalysis, chartinkAnalysis;
  final Map<String, dynamic> nifty5minSummary, vixAnalysis, signalVerdict;
  final List<Map<String, dynamic>> liveIndices;
  final List<CandlePoint> candles, vixCandles;

  const NiftySummary({
    required this.cached,
    required this.marketOpen,
    required this.lastUpdated,
    required this.niftyLtp,
    required this.niftyDayChangePct,
    required this.marketSentiment,
    required this.oneLiner,
    required this.confidence,
    required this.probabilityScore,
    required this.support,
    required this.resistance,
    required this.tradeIdea,
    required this.keyObservations,
    required this.riskFactors,
    required this.atlasInterpretation,
    required this.vixInterpretation,
    required this.nifty5minInterpretation,
    required this.bollingerAnalysis,
    required this.atlasAnalysis,
    required this.chartinkAnalysis,
    required this.nifty5minSummary,
    required this.vixAnalysis,
    required this.signalVerdict,
    required this.liveIndices,
    required this.candles,
    required this.vixCandles,
  });

  factory NiftySummary.fromJson(Map<String, dynamic> r) {
    final d = r['data'] as Map<String, dynamic>;
    final kl = (d['key_levels'] as Map<String, dynamic>?) ?? {};
    List<double> lv(dynamic x) =>
        (x as List? ?? []).map((e) => (e as num).toDouble()).toList();
    List<CandlePoint> cp(List raw) => raw
        .map((e) => CandlePoint.fromJson(e as Map<String, dynamic>))
        .toList();
    Map<String, dynamic> m(dynamic x) => (x as Map<String, dynamic>?) ?? {};

    return NiftySummary(
      cached: r['cached'] ?? false,
      marketOpen: r['market_open'] ?? false,
      lastUpdated: d['last_updated'] ?? '',
      niftyLtp: _num(d['nifty_ltp']),
      niftyDayChangePct: _num(d['nifty_day_change_pct']),
      marketSentiment: d['market_sentiment'] ?? 'Neutral',
      oneLiner: d['one_liner'] ?? '',
      confidence: d['confidence'] ?? 'Low',
      probabilityScore: _num(d['probability_score']),
      support: lv(kl['support']),
      resistance: lv(kl['resistance']),
      tradeIdea: m(d['trade_idea']),
      keyObservations: List<String>.from(d['key_observations'] ?? []),
      riskFactors: List<String>.from(d['risk_factors'] ?? []),
      atlasInterpretation: d['atlas_interpretation'] ?? '',
      vixInterpretation: d['vix_interpretation'] ?? '',
      nifty5minInterpretation: d['nifty5min_interpretation'] ?? '',
      bollingerAnalysis: m(r['bollinger_analysis']),
      atlasAnalysis: m(r['atlas_analysis']),
      chartinkAnalysis: m(r['chartink_analysis']),
      nifty5minSummary: m(r['nifty_5min_summary']),
      vixAnalysis: m(r['vix_analysis']),
      signalVerdict: m(r['signal_verdict']),
      liveIndices:
          List<Map<String, dynamic>>.from(r['live_nifty_indices'] ?? []),
      candles: cp(r['nifty_5min_candles'] as List? ?? []),
      vixCandles: cp(r['vix_5min_candles'] as List? ?? []),
    );
  }
}

/// Turns the raw verdict into one plain-language mood.
class Mood {
  final String headline, lean;
  final Color color;
  final double score; // 0 = falling, 1 = rising
  const Mood(this.headline, this.lean, this.color, this.score);

  factory Mood.from(NiftySummary s) {
    final conf = (s.signalVerdict['entry_confidence'] as String? ?? 'Avoid')
        .toLowerCase();
    final bias =
        s.signalVerdict['overall_bias'] as String? ?? s.marketSentiment;
    final strength =
        const {'strong': 1.0, 'moderate': .66, 'weak': .33}[conf] ?? .12;
    double score = .5;
    if (bias == 'Bullish') score = .5 + .5 * strength;
    if (bias == 'Bearish') score = .5 - .5 * strength;

    final lean = bias == 'Bullish'
        ? 'Leaning up'
        : bias == 'Bearish'
            ? 'Leaning down'
            : 'No clear direction';

    String head;
    switch (conf) {
      case 'strong':
        head = bias == 'Bullish'
            ? 'Buyers are in control'
            : bias == 'Bearish'
                ? 'Sellers are in control'
                : 'Strong signals, no direction';
        break;
      case 'moderate':
        head = bias == 'Bullish'
            ? 'A mild upward lean'
            : bias == 'Bearish'
                ? 'A mild downward lean'
                : 'Mixed signals';
        break;
      case 'weak':
        head = 'Not much to go on';
        break;
      default:
        head = 'Best to wait today';
    }

    final calm = conf == 'avoid' || bias == 'Neutral';
    final color = calm
        ? T.mid
        : bias == 'Bullish'
            ? T.up
            : T.down;
    return Mood(head, lean, color, score);
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────
const _kMessages = [
  (icon: Icons.show_chart_rounded, text: 'Checking live prices'),
  (icon: Icons.groups_rounded, text: 'Counting stocks going up and down'),
  (icon: Icons.speed_rounded, text: 'Measuring market nervousness'),
  (icon: Icons.auto_awesome_rounded, text: 'Writing your summary'),
];

class NiftyAiSummaryPage extends StatefulWidget {
  const NiftyAiSummaryPage({super.key});
  @override
  State<NiftyAiSummaryPage> createState() => _NiftyAiSummaryPageState();
}

class _NiftyAiSummaryPageState extends State<NiftyAiSummaryPage>
    with TickerProviderStateMixin {
  NiftySummary? _data;
  bool _loading = true;
  String? _error;
  int _msg = 0;
  bool _deep = false;
  Timer? _ticker;

  late final AnimationController _enter;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _enter.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
        _msg = 0;
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 2200), (_) {
        if (mounted && _msg < _kMessages.length - 1) setState(() => _msg++);
      });
    }
    try {
      final res = await http
          .get(Uri.parse('$kApiBase/nifty-summary'))
          .timeout(const Duration(seconds: 75));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d =
            NiftySummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        setState(() {
          _data = d;
          _loading = false;
          _error = null;
        });
        if (!silent) _enter.forward(from: 0);
      } else {
        final b = jsonDecode(res.body) as Map<String, dynamic>;
        if (!silent || _data == null) {
          setState(() {
            _error =
                b['detail']?.toString() ?? 'Server error ${res.statusCode}';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent || _data == null) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    } finally {
      _ticker?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = T.dark(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: T.bg(context),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _loading
                ? KeyedSubtree(key: const ValueKey('l'), child: _loader())
                : _error != null
                    ? KeyedSubtree(
                        key: const ValueKey('e'), child: _errorView())
                    : KeyedSubtree(key: const ValueKey('c'), child: _content()),
          ),
        ),
      ),
    );
  }

  // ── Loading ────────────────────────────────────────────────────────────────
  Widget _loader() {
    final m = _kMessages[_msg];
    return Column(children: [
      const _TopBar(),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  width: 92 + 16 * _pulse.value,
                  height: 92 + 16 * _pulse.value,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: T.link.withOpacity(.06 + .06 * _pulse.value),
                  ),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: T.surface(context)),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Icon(m.icon,
                          key: ValueKey(_msg), color: T.link, size: 26),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(m.text,
                    key: ValueKey(_msg),
                    textAlign: TextAlign.center,
                    style: _ts(context, s: 18, w: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              Text('Usually takes a few seconds',
                  style: _ts(context, s: 13, color: T.sub(context))),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  _kMessages.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _msg ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i <= _msg ? T.link : T.hair(context),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── Error ──────────────────────────────────────────────────────────────────
  Widget _errorView() => Column(children: [
        const _TopBar(),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_off_rounded, size: 44, color: T.sub(context)),
                const SizedBox(height: 16),
                Text("Couldn't load today's summary",
                    textAlign: TextAlign.center,
                    style: _ts(context, s: 18, w: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Check your internet connection and try again.',
                    textAlign: TextAlign.center,
                    style: _ts(context, s: 14, color: T.sub(context))),
                const SizedBox(height: 14),
                Text(_error ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: _ts(context, s: 11, color: T.sub(context))),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('Try again',
                      style: _ts(context,
                          w: FontWeight.w700, color: Colors.white)),
                  style: FilledButton.styleFrom(
                    backgroundColor: T.link,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]);

  // ── Content ────────────────────────────────────────────────────────────────
  Widget _content() {
    final s = _data!;
    final mood = Mood.from(s);

    final items = <Widget>[
      _MoodHero(summary: s, mood: mood),
      _SectionTitle('Why it looks this way', 'Tap any card to see more'),
      _BreadthFold(summary: s),
      _FearFold(summary: s),
      _ScannersFold(summary: s),
      _SectionTitle('What could you do?', null),
      _PlanCard(idea: s.tradeIdea),
      _DeepToggle(open: _deep, onTap: () => setState(() => _deep = !_deep)),
      AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child:
            _deep ? _deepSections(s) : const SizedBox(width: double.infinity),
      ),
      _Footer(summary: s),
    ];

    return Column(children: [
      _TopBar(
        subtitle: s.marketOpen ? 'Market is open' : 'Market is closed',
        live: s.marketOpen,
        onRefresh: _load,
      ),
      Expanded(
        child: RefreshIndicator(
          color: T.link,
          onRefresh: () => _load(silent: true),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
            itemCount: items.length,
            separatorBuilder: (_, i) =>
                SizedBox(height: items[i + 1] is _SectionTitle ? 22 : 10),
            itemBuilder: (_, i) =>
                _Reveal(anim: _enter, index: i, child: items[i]),
          ),
        ),
      ),
    ]);
  }

  Widget _deepSections(NiftySummary s) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(children: [
          _Fold(
            icon: Icons.candlestick_chart_rounded,
            color: T.link,
            title: "Today's price chart",
            child: _ChartBlock(summary: s),
          ),
          const SizedBox(height: 10),
          _Fold(
            icon: Icons.layers_rounded,
            color: T.sub(context),
            title: 'Price levels to watch',
            child: _LevelsBlock(support: s.support, resistance: s.resistance),
          ),
          if (s.keyObservations.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Fold(
              icon: Icons.lightbulb_outline_rounded,
              color: T.mid,
              title: 'What the AI noticed',
              child: _BulletList(items: s.keyObservations, color: T.mid),
            ),
          ],
          if (s.riskFactors.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Fold(
              icon: Icons.warning_amber_rounded,
              color: T.down,
              title: 'Things that could go wrong',
              child: _BulletList(items: s.riskFactors, color: T.down),
            ),
          ],
          if (s.liveIndices.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Fold(
              icon: Icons.format_list_bulleted_rounded,
              color: T.sub(context),
              title: 'Other indices today',
              child: _IndicesBlock(indices: s.liveIndices),
            ),
          ],
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Building blocks
// ═══════════════════════════════════════════════════════════════════════════════

/// One staggered entrance for the whole page.
class _Reveal extends StatelessWidget {
  final Animation<double> anim;
  final int index;
  final Widget child;
  const _Reveal({required this.anim, required this.index, required this.child});
  @override
  Widget build(BuildContext context) {
    final start = (index * .09).clamp(0.0, .6);
    final a = CurvedAnimation(
        parent: anim,
        curve: Interval(start, start + .4, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position:
            Tween(begin: const Offset(0, .05), end: Offset.zero).animate(a),
        child: child,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String? subtitle;
  final bool live;
  final VoidCallback? onRefresh;
  const _TopBar({this.subtitle, this.live = false, this.onRefresh});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          _RoundBtn(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Market mood',
                  style: _ts(context, s: 18, w: FontWeight.w800, h: 1.2)),
              if (subtitle != null)
                Row(children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: live ? T.up : T.sub(context)),
                  ),
                  Text(subtitle!,
                      style: _ts(context, s: 12, color: T.sub(context))),
                ]),
            ]),
          ),
          if (onRefresh != null)
            _RoundBtn(icon: Icons.refresh_rounded, onTap: onRefresh!),
        ]),
      );
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: T.surface(context),
        shape: CircleBorder(side: BorderSide(color: T.hair(context))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 16, color: T.ink(context))),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? hint;
  const _SectionTitle(this.title, this.hint);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _ts(context, s: 17, w: FontWeight.w800)),
          if (hint != null)
            Text(hint!, style: _ts(context, s: 12.5, color: T.sub(context))),
        ]),
      );
}

/// Expandable card used for every "see more" block.
class _Fold extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? answer;
  final Widget child;
  const _Fold(
      {required this.icon,
      required this.color,
      required this.title,
      required this.child,
      this.answer});
  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final hasAnswer = widget.answer != null;
    return Material(
      color: T.surface(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: T.hair(context)),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: widget.color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(widget.icon, color: widget.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: hasAnswer
                              ? _ts(context, s: 12.5, color: T.sub(context))
                              : _ts(context, s: 15, w: FontWeight.w700)),
                      if (hasAnswer) ...[
                        const SizedBox(height: 2),
                        Text(widget.answer!,
                            style: _ts(context, s: 15.5, w: FontWeight.w800)),
                      ],
                    ]),
              ),
              AnimatedRotation(
                turns: _open ? .5 : 0,
                duration: const Duration(milliseconds: 250),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    color: T.sub(context)),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                  child:
                      Align(alignment: Alignment.topLeft, child: widget.child),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

/// "What this means" helper line.
class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: T.alt(context), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 15, color: T.sub(context)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: _ts(context, s: 12.5, color: T.sub(context), h: 1.5))),
        ]),
      );
}

class _Para extends StatelessWidget {
  final String text;
  const _Para(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: _ts(context, s: 13.5, h: 1.55));
}

class _AiLine extends StatelessWidget {
  final String text;
  const _AiLine(this.text);
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_awesome_rounded, size: 14, color: T.link),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: _ts(context, s: 13, color: T.sub(context), h: 1.55))),
      ]);
}

// ─── Hero ─────────────────────────────────────────────────────────────────────
class _MoodHero extends StatelessWidget {
  final NiftySummary summary;
  final Mood mood;
  const _MoodHero({required this.summary, required this.mood});

  @override
  Widget build(BuildContext context) {
    final up = summary.niftyDayChangePct >= 0;
    final cc = up ? T.up : T.down;
    final fill = Color.alphaBlend(
        mood.color.withOpacity(T.dark(context) ? .14 : .09),
        T.surface(context));

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: mood.color.withOpacity(.3)),
      ),
      child: Column(children: [
        Row(children: [
          Text('Nifty 50', style: _ts(context, s: 13, color: T.sub(context))),
          const Spacer(),
          Text(_n2.format(summary.niftyLtp),
              style: _ts(context, s: 15, w: FontWeight.w800, figures: true)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: cc.withOpacity(.14),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
                '${up ? "+" : ""}${summary.niftyDayChangePct.toStringAsFixed(2)}%',
                style: _ts(context,
                    s: 12, w: FontWeight.w800, color: cc, figures: true)),
          ),
        ]),
        const SizedBox(height: 14),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: .5, end: mood.score),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeOutBack,
          builder: (_, v, __) => SizedBox(
            width: 250,
            height: 132,
            child: CustomPaint(
              painter: _GaugePainter(
                  value: v,
                  knob: mood.color,
                  track: T.hair(context),
                  ring: T.surface(context)),
              child: Align(
                alignment: const Alignment(0, .78),
                child: Text(mood.lean,
                    style: _ts(context, s: 13, color: T.sub(context))),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Falling', style: _ts(context, s: 11.5, color: T.down)),
            Text('Rising', style: _ts(context, s: 11.5, color: T.up)),
          ]),
        ),
        const SizedBox(height: 12),
        Text(mood.headline,
            textAlign: TextAlign.center,
            style: _ts(context, s: 24, w: FontWeight.w800, h: 1.2)),
        if (summary.oneLiner.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(summary.oneLiner,
              textAlign: TextAlign.center,
              style: _ts(context, s: 13.5, color: T.sub(context), h: 1.55)),
        ],
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color knob, track, ring;
  const _GaugePainter(
      {required this.value,
      required this.knob,
      required this.track,
      required this.ring});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final center = Offset(size.width / 2, size.height - 14);
    final radius = size.width / 2 - 18;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
        rect,
        math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = const SweepGradient(
            startAngle: math.pi,
            endAngle: 2 * math.pi,
            colors: [T.down, T.mid, T.up],
          ).createShader(rect));

    final v = value.clamp(0.0, 1.0);
    final a = math.pi + v * math.pi;
    final p = center + Offset(math.cos(a), math.sin(a)) * radius;
    canvas.drawCircle(p, 13, Paint()..color = ring);
    canvas.drawCircle(p, 8, Paint()..color = knob);
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.value != value || o.knob != knob || o.ring != ring;
}

// ─── "Why" cards ──────────────────────────────────────────────────────────────
class _BreadthFold extends StatelessWidget {
  final NiftySummary summary;
  const _BreadthFold({required this.summary});
  @override
  Widget build(BuildContext context) {
    final a = summary.atlasAnalysis;
    final adv = _num(a['advancing']).toInt();
    final dec = _num(a['declining']).toInt();
    final total = adv + dec;
    final ratio = total > 0 ? adv / total : .5;
    final color = total == 0
        ? T.sub(context)
        : ratio > .6
            ? T.up
            : ratio < .4
                ? T.down
                : T.mid;
    final answer = total == 0
        ? 'No data yet'
        : ratio >= .5
            ? 'Yes, $adv of $total are rising'
            : 'No, only $adv of $total are rising';
    final advice = a['action_advice'] as String? ?? '';

    return _Fold(
      icon: Icons.groups_rounded,
      color: color,
      title: 'Are most stocks going up?',
      answer: answer,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$adv rising',
              style: _ts(context, s: 13, w: FontWeight.w700, color: T.up)),
          Text('$dec falling',
              style: _ts(context, s: 13, w: FontWeight.w700, color: T.down)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: T.down.withOpacity(.25),
              valueColor: const AlwaysStoppedAnimation(T.up),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _Note(
            'When most stocks rise together, a move up is more believable. When only a few rise, it can fade quickly.'),
        if (advice.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Para(advice),
        ],
        if (summary.atlasInterpretation.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AiLine(summary.atlasInterpretation),
        ],
      ]),
    );
  }
}

class _FearFold extends StatelessWidget {
  final NiftySummary summary;
  const _FearFold({required this.summary});
  @override
  Widget build(BuildContext context) {
    final v = summary.vixAnalysis;
    final ltp = _num(v['ltp']);
    final level = v['level'] as String? ?? 'Unknown';
    final trend = v['trend'] as String? ?? 'Unknown';
    final chg = _num(v['day_change_pct']);
    final unavailable = v.isEmpty || ltp == 0 || level == 'Unknown';

    String answer;
    Color color;
    switch (level) {
      case 'Extreme':
        answer = 'Very nervous';
        color = T.down;
        break;
      case 'High':
        answer = 'Quite nervous';
        color = T.down;
        break;
      case 'Moderate':
        answer = 'A little nervous';
        color = T.mid;
        break;
      default:
        answer = 'Calm';
        color = T.up;
    }
    if (unavailable) {
      answer = 'No data right now';
      color = T.sub(context);
    }
    final interp = v['interpretation'] as String? ?? '';
    final rising = chg >= 0;

    return _Fold(
      icon: Icons.speed_rounded,
      color: color,
      title: 'How nervous is the market?',
      answer: answer,
      child: unavailable
          ? const _Note(
              'Fear data can be missing when the market is closed. Pull down to refresh later.')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(ltp.toStringAsFixed(2),
                    style: _ts(context,
                        s: 26, w: FontWeight.w800, figures: true, h: 1.1)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                      '${rising ? "+" : ""}${chg.toStringAsFixed(2)}% '
                      '${trend == "Uptrend" ? "· getting more nervous" : trend == "Downtrend" ? "· calming down" : ""}',
                      style: _ts(context,
                          s: 12.5,
                          w: FontWeight.w600,
                          color: rising ? T.down : T.up)),
                ),
              ]),
              if (summary.vixCandles.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 70,
                  child: SfCartesianChart(
                    plotAreaBorderWidth: 0,
                    margin: EdgeInsets.zero,
                    backgroundColor: Colors.transparent,
                    primaryXAxis: DateTimeAxis(isVisible: false),
                    primaryYAxis: NumericAxis(
                      isVisible: false,
                      minimum: summary.vixCandles
                              .map((c) => c.low)
                              .reduce(math.min) *
                          .998,
                      maximum: summary.vixCandles
                              .map((c) => c.high)
                              .reduce(math.max) *
                          1.002,
                    ),
                    series: [
                      LineSeries<CandlePoint, DateTime>(
                        dataSource: summary.vixCandles,
                        xValueMapper: (d, _) => d.time,
                        yValueMapper: (d, _) => d.close,
                        color: color,
                        width: 2,
                        animationDuration: 600,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const _Note(
                  'This is the India VIX. It shows how big a swing traders expect. Higher means bigger, riskier moves in either direction.'),
              if (interp.isNotEmpty) ...[
                const SizedBox(height: 12),
                _AiLine(interp),
              ],
            ]),
    );
  }
}

class _ScannersFold extends StatelessWidget {
  final NiftySummary summary;
  const _ScannersFold({required this.summary});
  @override
  Widget build(BuildContext context) {
    final v = summary.signalVerdict;
    final n = v['sources_actionable'] as int? ?? 0;
    final color = n >= 2
        ? T.up
        : n == 1
            ? T.mid
            : T.sub(context);
    final answer = n == 0
        ? 'None say act yet'
        : n == 3
            ? 'All 3 say act'
            : '$n of 3 say act';

    return _Fold(
      icon: Icons.fact_check_rounded,
      color: color,
      title: 'Do our 3 scanners agree?',
      answer: answer,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CheckRow(
            name: 'Market breadth scanner',
            ok: v['atlas_actionable'] as bool? ?? false,
            advice: summary.atlasAnalysis['action_advice'] as String? ?? ''),
        _CheckRow(
            name: 'Breakout scanner',
            ok: v['bollinger_actionable'] as bool? ?? false,
            advice:
                summary.bollingerAnalysis['action_advice'] as String? ?? ''),
        _CheckRow(
            name: 'Pattern scanner',
            ok: v['chartink_actionable'] as bool? ?? false,
            advice: summary.chartinkAnalysis['action_advice'] as String? ?? '',
            last: true),
        const SizedBox(height: 12),
        const _Note(
            'Each scanner looks at the market in a different way. The more of them agree, the stronger the case.'),
        if ((v['verdict'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          _AiLine(v['verdict'] as String),
        ],
      ]),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String name, advice;
  final bool ok, last;
  const _CheckRow(
      {required this.name,
      required this.ok,
      required this.advice,
      this.last = false});
  @override
  Widget build(BuildContext context) {
    final c = ok ? T.up : T.sub(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(ok ? Icons.check_circle_rounded : Icons.schedule_rounded,
              size: 18, color: c),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(name, style: _ts(context, s: 13.5, w: FontWeight.w700)),
              const SizedBox(width: 8),
              Text(ok ? 'Says act' : 'Waiting',
                  style: _ts(context, s: 12, w: FontWeight.w700, color: c)),
            ]),
            if (advice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(advice,
                    style:
                        _ts(context, s: 12.5, color: T.sub(context), h: 1.45)),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Plan ─────────────────────────────────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> idea;
  const _PlanCard({required this.idea});

  @override
  Widget build(BuildContext context) {
    final dir = (idea['direction'] as String? ?? 'Wait').toLowerCase();
    final isWait = dir != 'long' && dir != 'short';
    final rationale = idea['rationale'] as String? ?? '';
    final entry = idea['entry_zone'] as String? ?? '';
    final color = dir == 'long'
        ? T.up
        : dir == 'short'
            ? T.down
            : T.mid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: T.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: isWait
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.hourglass_empty_rounded, color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('No clear trade right now',
                      style: _ts(context, s: 16, w: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 6),
              Text('Waiting is also a decision. Good setups come and go.',
                  style: _ts(context, s: 13, color: T.sub(context))),
              if (rationale.isNotEmpty) ...[
                const SizedBox(height: 12),
                _AiLine(rationale),
              ],
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  dir == 'long'
                      ? 'Buying looks favourable'
                      : 'A fall looks likely (a "short" trade)',
                  style: _ts(context, s: 16, w: FontWeight.w800, color: color)),
              if (entry.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Possible entry: $entry',
                    style: _ts(context,
                        s: 13, color: T.sub(context), figures: true)),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: _LevelBox(
                        label: 'Exit if it hits',
                        hint: 'stop-loss',
                        value: _n0.format(_num(idea['stop_loss'])),
                        color: T.down)),
                const SizedBox(width: 8),
                Expanded(
                    child: _LevelBox(
                        label: 'First goal',
                        hint: 'target 1',
                        value: _n0.format(_num(idea['target_1'])),
                        color: T.up)),
                const SizedBox(width: 8),
                Expanded(
                    child: _LevelBox(
                        label: 'Second goal',
                        hint: 'target 2',
                        value: _n0.format(_num(idea['target_2'])),
                        color: T.up)),
              ]),
              if (rationale.isNotEmpty) ...[
                const SizedBox(height: 14),
                _AiLine(rationale),
              ],
            ]),
    );
  }
}

class _LevelBox extends StatelessWidget {
  final String label, hint, value;
  final Color color;
  const _LevelBox(
      {required this.label,
      required this.hint,
      required this.value,
      required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _ts(context, s: 11.5, color: T.sub(context))),
          const SizedBox(height: 2),
          Text(value,
              style: _ts(context,
                  s: 16, w: FontWeight.w800, color: color, figures: true)),
          Text(hint, style: _ts(context, s: 10.5, color: T.sub(context))),
        ]),
      );
}

// ─── Deep dive ────────────────────────────────────────────────────────────────
class _DeepToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onTap;
  const _DeepToggle({required this.open, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: T.link.withOpacity(.4)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.analytics_outlined, size: 18, color: T.link),
              const SizedBox(width: 8),
              Text(open ? 'Hide charts and numbers' : 'Show charts and numbers',
                  style:
                      _ts(context, s: 14, w: FontWeight.w700, color: T.link)),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: open ? .5 : 0,
                duration: const Duration(milliseconds: 250),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: T.link),
              ),
            ]),
          ),
        ),
      );
}

class _ChartBlock extends StatelessWidget {
  final NiftySummary summary;
  const _ChartBlock({required this.summary});
  @override
  Widget build(BuildContext context) {
    final candles = summary.candles;
    final up = summary.niftyDayChangePct >= 0;
    final lc = up ? T.up : T.down;
    final s5 = summary.nifty5minSummary;
    final dark = T.dark(context);
    final grid = T.hair(context);
    final lbl = T.sub(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (s5.isNotEmpty)
        Row(children: [
          _Mini(
              label: "Day's low",
              value: _n0.format(_num(s5['day_low'])),
              color: T.down),
          const SizedBox(width: 20),
          _Mini(
              label: "Day's high",
              value: _n0.format(_num(s5['day_high'])),
              color: T.up),
        ]),
      const SizedBox(height: 8),
      if (candles.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text('No chart data yet. It appears once the market opens.',
              style: _ts(context, s: 13, color: T.sub(context))),
        )
      else
        SizedBox(
          height: 190,
          child: SfCartesianChart(
            plotAreaBorderWidth: 0,
            margin: const EdgeInsets.only(right: 4),
            backgroundColor: Colors.transparent,
            primaryXAxis: DateTimeAxis(
              dateFormat: DateFormat('h a'),
              intervalType: DateTimeIntervalType.hours,
              interval: 1,
              majorGridLines: const MajorGridLines(width: 0),
              axisLine: const AxisLine(width: 0),
              majorTickLines: const MajorTickLines(size: 0),
              labelStyle: TextStyle(color: lbl, fontSize: 10),
            ),
            primaryYAxis: NumericAxis(
              numberFormat: NumberFormat('#,##0'),
              majorGridLines: MajorGridLines(
                  color: grid, width: 1, dashArray: const [3, 3]),
              axisLine: const AxisLine(width: 0),
              majorTickLines: const MajorTickLines(size: 0),
              labelStyle: TextStyle(color: lbl, fontSize: 10),
              opposedPosition: true,
            ),
            series: [
              AreaSeries<CandlePoint, DateTime>(
                dataSource: candles,
                xValueMapper: (d, _) => _toIst(d.time),
                yValueMapper: (d, _) => d.close,
                borderColor: lc,
                borderWidth: 2,
                animationDuration: 700,
                gradient: LinearGradient(
                  colors: [lc.withOpacity(dark ? .25 : .18), lc.withOpacity(0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ],
            tooltipBehavior: TooltipBehavior(
              enable: true,
              builder: (data, point, series, pIdx, sIdx) {
                if (pIdx < 0 || pIdx >= candles.length) {
                  return const SizedBox.shrink();
                }
                final c = candles[pIdx];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: T.surface(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: T.hair(context)),
                  ),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('h:mm a').format(_toIst(c.time)),
                            style:
                                _ts(context, s: 10.5, color: T.sub(context))),
                        Text(_n2.format(c.close),
                            style: _ts(context,
                                s: 13,
                                w: FontWeight.w800,
                                color: lc,
                                figures: true)),
                      ]),
                );
              },
            ),
          ),
        ),
      if (summary.nifty5minInterpretation.isNotEmpty) ...[
        const SizedBox(height: 8),
        _AiLine(summary.nifty5minInterpretation),
      ],
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => BrowserLite_V(
                      'https://in.tradingview.com/chart/?symbol=NSE%3ANIFTY'))),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text('Open full chart on TradingView',
              style: _ts(context, s: 13, w: FontWeight.w700, color: T.link)),
          style: OutlinedButton.styleFrom(
            foregroundColor: T.link,
            side: BorderSide(color: T.link.withOpacity(.4)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ]);
  }
}

class _Mini extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Mini({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: _ts(context, s: 11.5, color: T.sub(context))),
        Text(value,
            style: _ts(context,
                s: 15, w: FontWeight.w800, color: color, figures: true)),
      ]);
}

class _LevelsBlock extends StatelessWidget {
  final List<double> support, resistance;
  const _LevelsBlock({required this.support, required this.resistance});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _chips(context, 'Support (floors)', 'Price often stops falling here',
            support, T.up),
        const SizedBox(height: 14),
        _chips(context, 'Resistance (ceilings)',
            'Price often stops rising here', resistance, T.down),
      ]);

  Widget _chips(BuildContext context, String title, String hint,
          List<double> levels, Color color) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: _ts(context, s: 13.5, w: FontWeight.w700)),
        Text(hint, style: _ts(context, s: 12, color: T.sub(context))),
        const SizedBox(height: 8),
        if (levels.isEmpty)
          Text('None marked',
              style: _ts(context, s: 12.5, color: T.sub(context)))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: levels
                .take(6)
                .map((l) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_n0.format(l),
                          style: _ts(context,
                              s: 13,
                              w: FontWeight.w800,
                              color: color,
                              figures: true)),
                    ))
                .toList(),
          ),
      ]);
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  final Color color;
  const _BulletList({required this.items, required this.color});
  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < items.length - 1 ? 10 : 0),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 7, right: 10),
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                Expanded(child: _Para(items[i])),
              ]),
            ),
        ],
      );
}

class _IndicesBlock extends StatelessWidget {
  final List<Map<String, dynamic>> indices;
  const _IndicesBlock({required this.indices});
  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (int i = 0; i < indices.length; i++) ...[
            _row(context, indices[i]),
            if (i < indices.length - 1)
              Divider(height: 14, color: T.hair(context)),
          ],
        ],
      );

  Widget _row(BuildContext context, Map<String, dynamic> r) {
    final pct = _num(r['pcnt']);
    final sym = (r['symbol'] ?? '').toString();
    final isVix = sym.toUpperCase().contains('VIX');
    final up = pct >= 0;
    // For the fear index, rising is bad news, so colours flip.
    final c = isVix ? (up ? T.down : T.up) : (up ? T.up : T.down);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(sym, style: _ts(context, s: 13.5, w: FontWeight.w700)),
          if (isVix)
            Text('Fear index',
                style: _ts(context, s: 11, color: T.sub(context))),
        ]),
      ),
      Text(_n2.format(_num(r['ltp'])),
          style: _ts(context, s: 13, figures: true)),
      const SizedBox(width: 10),
      Container(
        width: 66,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
            color: c.withOpacity(.12), borderRadius: BorderRadius.circular(8)),
        child: Text('${up ? "+" : ""}${pct.toStringAsFixed(2)}%',
            style: _ts(context,
                s: 11.5, w: FontWeight.w800, color: c, figures: true)),
      ),
    ]);
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  final NiftySummary summary;
  const _Footer({required this.summary});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Column(children: [
          Text(
              'Updated ${summary.lastUpdated}'
              '${summary.cached ? " · saved copy" : " · fresh from AI"}',
              textAlign: TextAlign.center,
              style: _ts(context, s: 11.5, color: T.sub(context))),
          const SizedBox(height: 6),
          Text(
              'For learning only. Not financial advice. Please speak to a SEBI-registered advisor before you trade.',
              textAlign: TextAlign.center,
              style: _ts(context, s: 11.5, color: T.sub(context), h: 1.5)),
        ]),
      );
}
