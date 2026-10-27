import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:optionxi/Helpers/open_url.dart';
import 'package:optionxi/Helpers/browser_lite.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

// ─── API ──────────────────────────────────────────────────────────────────────
String get kApiBase => dotenv.env['AI_SUMMARY_URL']!;

// ─── Helpers ──────────────────────────────────────────────────────────────────
double _num(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
final _n2 = NumberFormat('#,##0.00');

Future<int> _getBuildNumber() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  } catch (_) {
    return 0;
  }
}

String _cleanSymbol(String s) => s
    .replaceAll('NSE:', '')
    .replaceAll('-EQ', '')
    .replaceAll('-BE', '')
    .replaceAll('.NS', '');

// ─── Design tokens (same family as the Nifty page) ────────────────────────────
class _T {
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
      color: color ?? _T.ink(c),
      height: h,
      fontFeatures: figures ? const [FontFeature.tabularFigures()] : null,
    );

// ─── Models ───────────────────────────────────────────────────────────────────
class _ChartPoint {
  final DateTime date;
  final double close;
  const _ChartPoint({required this.date, required this.close});
}

class ScreenerSignal {
  final String name, timeframe, scanDate;
  const ScreenerSignal(
      {required this.name, required this.timeframe, required this.scanDate});
  factory ScreenerSignal.fromJson(Map<String, dynamic> j) => ScreenerSignal(
      name: j['name'] ?? '',
      timeframe: j['timeframe'] ?? '',
      scanDate: j['scan_date'] ?? '');
}

class ScreenerAnalysis {
  final List<ScreenerSignal> bullish, bearish;
  final int bullishCount, bearishCount;
  final String bias, summary;
  final bool strongSignal;
  const ScreenerAnalysis({
    required this.bullish,
    required this.bearish,
    required this.bullishCount,
    required this.bearishCount,
    required this.bias,
    required this.strongSignal,
    required this.summary,
  });
  factory ScreenerAnalysis.fromJson(Map<String, dynamic> j) => ScreenerAnalysis(
        bullish: (j['bullish_signals'] as List? ?? [])
            .map((e) => ScreenerSignal.fromJson(e as Map<String, dynamic>))
            .toList(),
        bearish: (j['bearish_signals'] as List? ?? [])
            .map((e) => ScreenerSignal.fromJson(e as Map<String, dynamic>))
            .toList(),
        bullishCount: (j['bullish_count'] ?? 0) as int,
        bearishCount: (j['bearish_count'] ?? 0) as int,
        bias: j['screener_bias'] ?? 'Neutral',
        strongSignal: j['strong_signal'] ?? false,
        summary: j['signal_summary'] ?? '',
      );
}

class AlertSummary {
  final int triggeredCount, pendingCount;
  final List<String> proximityNotes;
  final String summary;
  const AlertSummary({
    required this.triggeredCount,
    required this.pendingCount,
    required this.proximityNotes,
    required this.summary,
  });
  factory AlertSummary.fromJson(Map<String, dynamic> j) => AlertSummary(
        triggeredCount: (j['triggered_alerts'] as List? ?? []).length,
        pendingCount: (j['pending_alerts'] as List? ?? []).length,
        proximityNotes: List<String>.from(j['proximity_notes'] ?? []),
        summary: j['alert_summary'] ?? '',
      );
}

class FetchCheck {
  final String source, detail;
  final bool found;
  final int count;
  const FetchCheck(
      {required this.source,
      required this.found,
      required this.count,
      required this.detail});
  factory FetchCheck.fromJson(Map<String, dynamic> j) => FetchCheck(
      source: j['source'] ?? '',
      found: j['found'] ?? false,
      count: j['count'] ?? 0,
      detail: j['detail'] ?? '');
}

class PriceLevel {
  final double price;
  final String strength, note;
  const PriceLevel(
      {required this.price, required this.strength, required this.note});
  factory PriceLevel.fromJson(Map<String, dynamic> j) => PriceLevel(
      price: _num(j['price']),
      strength: j['strength'] ?? '',
      note: j['note'] ?? '');
}

class EntryOpportunity {
  final String type, entryZone, rationale, riskReward;
  final double stopLoss, target1, target2;
  const EntryOpportunity({
    required this.type,
    required this.entryZone,
    required this.rationale,
    required this.riskReward,
    required this.stopLoss,
    required this.target1,
    required this.target2,
  });
  factory EntryOpportunity.fromJson(Map<String, dynamic> j) => EntryOpportunity(
        type: j['type'] ?? '',
        entryZone: j['entry_zone'] ?? '',
        rationale: j['rationale'] ?? '',
        riskReward: j['risk_reward'] ?? '',
        stopLoss: _num(j['stop_loss']),
        target1: _num(j['target_1']),
        target2: _num(j['target_2']),
      );
}

class StockAnalysis {
  final String symbol,
      companyName,
      marketSentiment,
      oneLiner,
      volumeAnalysis,
      indicatorSummary,
      timeframe,
      confidence,
      lastUpdated;
  final double currentPrice, dayChangePct;
  final List<PriceLevel> supportLevels, resistanceLevels;
  final List<EntryOpportunity> entries;
  final List<String> keyObservations, riskFactors;
  final bool cached;
  final ScreenerAnalysis screenerAnalysis;
  final AlertSummary alertSummary;
  final List<FetchCheck> fetchChecks;
  final int fetchFound, fetchTotal;

  const StockAnalysis({
    required this.symbol,
    required this.companyName,
    required this.marketSentiment,
    required this.oneLiner,
    required this.currentPrice,
    required this.dayChangePct,
    required this.supportLevels,
    required this.resistanceLevels,
    required this.entries,
    required this.keyObservations,
    required this.riskFactors,
    required this.volumeAnalysis,
    required this.indicatorSummary,
    required this.timeframe,
    required this.confidence,
    required this.lastUpdated,
    required this.cached,
    required this.screenerAnalysis,
    required this.alertSummary,
    required this.fetchChecks,
    required this.fetchFound,
    required this.fetchTotal,
  });

  factory StockAnalysis.fromJson(Map<String, dynamic> r) {
    final d = r['data'] as Map<String, dynamic>;
    final sa = r['screener_analysis'] as Map<String, dynamic>? ?? {};
    final aa = r['alert_analysis'] as Map<String, dynamic>? ?? {};
    final fs = r['fetch_status'] as Map<String, dynamic>? ?? {};
    return StockAnalysis(
      symbol: d['symbol'] ?? '',
      companyName: d['company_name'] ?? '',
      marketSentiment: d['market_sentiment'] ?? '',
      oneLiner: d['one_liner'] ?? '',
      currentPrice: _num(d['current_price']),
      dayChangePct: _num(d['day_change_pct']),
      supportLevels: (d['support_levels'] as List? ?? [])
          .map((e) => PriceLevel.fromJson(e))
          .toList(),
      resistanceLevels: (d['resistance_levels'] as List? ?? [])
          .map((e) => PriceLevel.fromJson(e))
          .toList(),
      entries: (d['entry_opportunities'] as List? ?? [])
          .map((e) => EntryOpportunity.fromJson(e))
          .toList(),
      keyObservations: List<String>.from(d['key_observations'] ?? []),
      riskFactors: List<String>.from(d['risk_factors'] ?? []),
      volumeAnalysis: d['volume_analysis'] ?? '',
      indicatorSummary: d['indicator_summary'] ?? '',
      timeframe: d['timeframe'] ?? '',
      confidence: d['confidence'] ?? '',
      lastUpdated: d['last_updated'] ?? '',
      cached: r['cached'] ?? false,
      screenerAnalysis: ScreenerAnalysis.fromJson(sa),
      alertSummary: AlertSummary.fromJson(aa),
      fetchChecks: (fs['checks'] as List? ?? [])
          .map((e) => FetchCheck.fromJson(e as Map<String, dynamic>))
          .toList(),
      fetchFound: (fs['found_count'] ?? 0) as int,
      fetchTotal: (fs['total'] ?? 0) as int,
    );
  }
}

/// Plain-language mood derived from sentiment + AI confidence.
class _Mood {
  final String headline, lean, sure;
  final Color color;
  final double score; // 0 falling → 1 rising
  const _Mood(this.headline, this.lean, this.sure, this.color, this.score);

  factory _Mood.from(StockAnalysis a) {
    final s = a.marketSentiment.toLowerCase();
    final bull = s.contains('bull');
    final bear = s.contains('bear');
    final c = a.confidence.toLowerCase();
    final strength = c.contains('high')
        ? 1.0
        : (c.contains('med') || c.contains('mod'))
            ? .66
            : c.contains('low')
                ? .33
                : .5;

    double score = .5;
    if (bull) score = .5 + .5 * strength;
    if (bear) score = .5 - .5 * strength;

    String head;
    if (!bull && !bear) {
      head = 'No clear direction';
    } else if (strength >= 1) {
      head = bull ? 'Looks strong for buyers' : 'Looks weak right now';
    } else if (strength >= .6) {
      head = bull ? 'Leaning positive' : 'Leaning negative';
    } else {
      head = bull
          ? 'Slightly positive, not certain'
          : 'Slightly negative, not certain';
    }

    final sure = c.contains('high')
        ? 'The AI is fairly sure'
        : c.contains('low')
            ? 'The AI is not very sure'
            : 'The AI is somewhat sure';
    final lean = bull
        ? 'Leaning up'
        : bear
            ? 'Leaning down'
            : 'No clear direction';
    final color = bull
        ? _T.up
        : bear
            ? _T.down
            : _T.mid;
    return _Mood(head, lean, sure, color, score);
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────
class StockAiAnalysisPage extends StatefulWidget {
  final String symbol;
  const StockAiAnalysisPage({super.key, required this.symbol});
  @override
  State<StockAiAnalysisPage> createState() => _StockAiAnalysisPageState();
}

class _StockAiAnalysisPageState extends State<StockAiAnalysisPage>
    with TickerProviderStateMixin {
  StockAnalysis? _analysis;
  bool _loading = true;
  bool _needsUpdate = false;
  String? _error;
  int _msg = 0;
  bool _deep = false;
  int _planIdx = 0;
  Timer? _ticker;

  List<_ChartPoint> _chartData = [];
  bool _chartLoading = false;

  late final AnimationController _enter;
  late final AnimationController _pulse;

  String _androidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.optionxi.app';
  String _iosStoreUrl = 'https://apps.apple.com/in/app/optionxi/id6447514602';
  String get _storeUrl => Platform.isIOS ? _iosStoreUrl : _androidStoreUrl;

  String get _sym => _cleanSymbol(widget.symbol);

  List<({IconData icon, String text})> get _messages => [
        (icon: Icons.show_chart_rounded, text: 'Reading $_sym price history'),
        (icon: Icons.analytics_rounded, text: 'Checking indicators and volume'),
        (icon: Icons.radar_rounded, text: 'Scanning for chart patterns'),
        (icon: Icons.auto_awesome_rounded, text: 'Writing your summary'),
      ];

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

  // ── Store links (only fetched when an update is needed) ────────────────────
  Future<void> _loadStoreLinks() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(seconds: 120),
      ));
      await rc.activate();
      await rc.fetch();
      final ios = rc.getString('ioslink');
      final android = rc.getString('androidlink');
      if (ios.isNotEmpty) _iosStoreUrl = ios;
      if (android.isNotEmpty) _androidStoreUrl = android;
    } catch (_) {}
  }

  /// Returns true when the app is too old to continue.
  Future<bool> _versionGate() async {
    try {
      final build = await _getBuildNumber();
      final res = await http
          .get(Uri.parse('$kApiBase/app-config'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      final cfg = jsonDecode(res.body) as Map<String, dynamic>;
      final minVer = int.tryParse(cfg['min_version']?.toString() ?? '0') ?? 0;
      final latest =
          int.tryParse(cfg['latest_version']?.toString() ?? '0') ?? 0;
      if (build < minVer) {
        await _loadStoreLinks();
        return true;
      }
      if (build < latest) {
        await _loadStoreLinks();
        if (mounted) _showOptionalUpdate();
      }
    } catch (_) {}
    return false;
  }

  void _showOptionalUpdate() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _T.surface(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.system_update_rounded, color: _T.link, size: 36),
            const SizedBox(height: 14),
            Text('A new version is ready',
                style: _ts(ctx, s: 18, w: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('It has improvements and bug fixes.',
                textAlign: TextAlign.center,
                style: _ts(ctx, s: 13.5, color: _T.sub(ctx))),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => OpenHelper.open_url(_storeUrl),
                style: FilledButton.styleFrom(
                  backgroundColor: _T.link,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Update now',
                    style: _ts(ctx, w: FontWeight.w700, color: Colors.white)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  Text('Not now', style: _ts(ctx, s: 13, color: _T.sub(ctx))),
            ),
          ]),
        ),
      ),
    );
  }

  // ── 30-day chart from Supabase ─────────────────────────────────────────────
  Future<void> _fetchChart() async {
    if (!mounted) return;
    setState(() => _chartLoading = true);
    try {
      String sym = widget.symbol;
      if (sym.startsWith('NSE:')) sym = sym.substring(4);
      if (sym.endsWith('-EQ')) sym = sym.substring(0, sym.length - 3);
      if (sym.endsWith('-BE')) sym = sym.substring(0, sym.length - 3);
      if (!sym.endsWith('.NS')) sym = '$sym.NS';

      final start = DateTime.now().subtract(const Duration(days: 30));
      final response = await Supabase.instance.client
          .from('stock_data')
          .select('Timestamp, Close')
          .eq('Stock Symbol', sym)
          .gte('Timestamp', start.millisecondsSinceEpoch)
          .order('Timestamp', ascending: true);

      final pts = <_ChartPoint>[];
      for (final row in response) {
        try {
          final ts = row['Timestamp'];
          final cl = row['Close'];
          if (ts == null || cl == null) continue;
          pts.add(_ChartPoint(
              date: DateTime.fromMillisecondsSinceEpoch((ts as num).toInt()),
              close: (cl as num).toDouble()));
        } catch (_) {}
      }
      if (mounted) setState(() => _chartData = pts);
    } catch (_) {
      // chart is supplementary
    } finally {
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
        _needsUpdate = false;
        _msg = 0;
        _chartData = [];
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 2200), (_) {
        if (mounted && _msg < _messages.length - 1) setState(() => _msg++);
      });
    }

    // Start the analysis right away; the version check runs alongside it.
    final req = http
        .get(Uri.parse('$kApiBase/analysis/${widget.symbol}'))
        .timeout(const Duration(seconds: 60));
    req.ignore();

    try {
      if (!silent && await _versionGate()) {
        if (mounted) {
          setState(() {
            _needsUpdate = true;
            _loading = false;
          });
        }
        return;
      }

      final res = await req;
      if (!mounted) return;
      if (res.statusCode == 200) {
        final a = StockAnalysis.fromJson(
            jsonDecode(res.body) as Map<String, dynamic>);
        setState(() {
          _analysis = a;
          _loading = false;
          _error = null;
          _planIdx = 0;
        });
        if (!silent) _enter.forward(from: 0);
        _fetchChart();
      } else {
        final b = jsonDecode(res.body) as Map<String, dynamic>;
        if (!silent || _analysis == null) {
          setState(() {
            _error =
                b['detail']?.toString() ?? 'Server error ${res.statusCode}';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent || _analysis == null) {
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
    final dark = _T.dark(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _T.bg(context),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _loading
                ? KeyedSubtree(key: const ValueKey('l'), child: _loader())
                : _needsUpdate
                    ? KeyedSubtree(
                        key: const ValueKey('u'), child: _updateView())
                    : _error != null
                        ? KeyedSubtree(
                            key: const ValueKey('e'), child: _errorView())
                        : _analysis == null
                            ? KeyedSubtree(
                                key: const ValueKey('n'), child: _errorView())
                            : KeyedSubtree(
                                key: const ValueKey('c'), child: _content()),
          ),
        ),
      ),
    );
  }

  // ── Loading ────────────────────────────────────────────────────────────────
  Widget _loader() {
    final msgs = _messages;
    final m = msgs[_msg.clamp(0, msgs.length - 1)];
    return Column(children: [
      _TopBar(title: _sym),
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
                    color: _T.link.withOpacity(.06 + .06 * _pulse.value),
                  ),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: _T.surface(context)),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Icon(m.icon,
                          key: ValueKey(_msg), color: _T.link, size: 26),
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
                  style: _ts(context, s: 13, color: _T.sub(context))),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  msgs.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _msg ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i <= _msg ? _T.link : _T.hair(context),
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

  // ── Update required ────────────────────────────────────────────────────────
  Widget _updateView() => Column(children: [
        _TopBar(title: _sym),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.system_update_rounded,
                    size: 48, color: _T.link),
                const SizedBox(height: 16),
                Text('Please update the app',
                    style: _ts(context, s: 20, w: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('You need the latest version to use AI analysis.',
                    textAlign: TextAlign.center,
                    style: _ts(context, s: 14, color: _T.sub(context))),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () => OpenHelper.open_url(_storeUrl),
                  style: FilledButton.styleFrom(
                    backgroundColor: _T.link,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Update now',
                      style: _ts(context,
                          w: FontWeight.w700, color: Colors.white)),
                ),
              ]),
            ),
          ),
        ),
      ]);

  // ── Error ──────────────────────────────────────────────────────────────────
  Widget _errorView() => Column(children: [
        _TopBar(title: _sym),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_off_rounded, size: 44, color: _T.sub(context)),
                const SizedBox(height: 16),
                Text("Couldn't load the analysis",
                    textAlign: TextAlign.center,
                    style: _ts(context, s: 18, w: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Check your internet connection and try again.',
                    textAlign: TextAlign.center,
                    style: _ts(context, s: 14, color: _T.sub(context))),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: _ts(context, s: 11, color: _T.sub(context))),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('Try again',
                      style: _ts(context,
                          w: FontWeight.w700, color: Colors.white)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _T.link,
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
    final a = _analysis!;
    final mood = _Mood.from(a);

    final items = <Widget>[
      _Hero(analysis: a, mood: mood, symbol: _sym),
      const _SectionTitle('Why it looks this way', 'Tap any card to see more'),
      _PriceFold(
          analysis: a,
          chartData: _chartData,
          chartLoading: _chartLoading,
          symbol: _sym),
      _ScannersFold(sa: a.screenerAnalysis),
      if (a.alertSummary.triggeredCount > 0 || a.alertSummary.pendingCount > 0)
        _AlertsFold(alert: a.alertSummary),
      if (a.indicatorSummary.isNotEmpty || a.volumeAnalysis.isNotEmpty)
        _IndicatorsFold(
            indicators: a.indicatorSummary, volume: a.volumeAnalysis),
      const _SectionTitle('What could you do?', 'Pick a style to see its plan'),
      _PlanSection(
        entries: a.entries,
        selected: _planIdx,
        onSelect: (i) => setState(() => _planIdx = i),
      ),
      _DeepToggle(open: _deep, onTap: () => setState(() => _deep = !_deep)),
      AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child:
            _deep ? _deepSections(a) : const SizedBox(width: double.infinity),
      ),
      _Footer(analysis: a),
    ];

    return Column(children: [
      _TopBar(
        title: a.companyName.isNotEmpty ? a.companyName : _sym,
        subtitle: a.companyName.isNotEmpty ? _sym : null,
        onRefresh: _load,
      ),
      Expanded(
        child: RefreshIndicator(
          color: _T.link,
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

  Widget _deepSections(StockAnalysis a) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(children: [
          _Fold(
            icon: Icons.layers_rounded,
            color: _T.sub(context),
            title: 'Price levels to watch',
            child: _LevelsBlock(
                supports: a.supportLevels, resistances: a.resistanceLevels),
          ),
          if (a.keyObservations.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Fold(
              icon: Icons.lightbulb_outline_rounded,
              color: _T.mid,
              title: 'What the AI noticed',
              child: _BulletList(items: a.keyObservations, color: _T.mid),
            ),
          ],
          if (a.riskFactors.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Fold(
              icon: Icons.warning_amber_rounded,
              color: _T.down,
              title: 'Things that could go wrong',
              child: _BulletList(items: a.riskFactors, color: _T.down),
            ),
          ],
          if (a.fetchTotal > 0) ...[
            const SizedBox(height: 10),
            _Fold(
              icon: Icons.storage_rounded,
              color: a.fetchFound == a.fetchTotal ? _T.up : _T.mid,
              title: 'How complete is the data?',
              answer: '${a.fetchFound} of ${a.fetchTotal} sources worked',
              child: _SourcesBlock(checks: a.fetchChecks),
            ),
          ],
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared building blocks
// ═══════════════════════════════════════════════════════════════════════════════

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
  final String title;
  final String? subtitle;
  final VoidCallback? onRefresh;
  const _TopBar({required this.title, this.subtitle, this.onRefresh});
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
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ts(context, s: 18, w: FontWeight.w800, h: 1.2)),
              if (subtitle != null)
                Text(subtitle!,
                    style: _ts(context, s: 12, color: _T.sub(context))),
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
        color: _T.surface(context),
        shape: CircleBorder(side: BorderSide(color: _T.hair(context))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 16, color: _T.ink(context))),
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
            Text(hint!, style: _ts(context, s: 12.5, color: _T.sub(context))),
        ]),
      );
}

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
      color: _T.surface(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _T.hair(context)),
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
                              ? _ts(context, s: 12.5, color: _T.sub(context))
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
                    color: _T.sub(context)),
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

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _T.alt(context), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 15, color: _T.sub(context)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style:
                      _ts(context, s: 12.5, color: _T.sub(context), h: 1.5))),
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
        const Icon(Icons.auto_awesome_rounded, size: 14, color: _T.link),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: _ts(context, s: 13, color: _T.sub(context), h: 1.55))),
      ]);
}

// ─── Hero ─────────────────────────────────────────────────────────────────────
class _Hero extends StatelessWidget {
  final StockAnalysis analysis;
  final _Mood mood;
  final String symbol;
  const _Hero(
      {required this.analysis, required this.mood, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final up = analysis.dayChangePct >= 0;
    final cc = up ? _T.up : _T.down;
    final fill = Color.alphaBlend(
        mood.color.withOpacity(_T.dark(context) ? .14 : .09),
        _T.surface(context));

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: mood.color.withOpacity(.3)),
      ),
      child: Column(children: [
        Row(children: [
          Text(symbol, style: _ts(context, s: 13, color: _T.sub(context))),
          const Spacer(),
          Text('₹${_n2.format(analysis.currentPrice)}',
              style: _ts(context, s: 15, w: FontWeight.w800, figures: true)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: cc.withOpacity(.14),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
                '${up ? "+" : ""}${analysis.dayChangePct.toStringAsFixed(2)}%',
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
                  value: v, knob: mood.color, ring: _T.surface(context)),
              child: Align(
                alignment: const Alignment(0, .78),
                child: Text(mood.lean,
                    style: _ts(context, s: 13, color: _T.sub(context))),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Falling', style: _ts(context, s: 11.5, color: _T.down)),
            Text('Rising', style: _ts(context, s: 11.5, color: _T.up)),
          ]),
        ),
        const SizedBox(height: 12),
        Text(mood.headline,
            textAlign: TextAlign.center,
            style: _ts(context, s: 24, w: FontWeight.w800, h: 1.2)),
        const SizedBox(height: 4),
        Text(mood.sure, style: _ts(context, s: 12.5, color: _T.sub(context))),
        if (analysis.oneLiner.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(analysis.oneLiner,
              textAlign: TextAlign.center,
              style: _ts(context, s: 13.5, color: _T.sub(context), h: 1.55)),
        ],
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color knob, ring;
  const _GaugePainter(
      {required this.value, required this.knob, required this.ring});

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
            colors: [_T.down, _T.mid, _T.up],
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
class _PriceFold extends StatelessWidget {
  final StockAnalysis analysis;
  final List<_ChartPoint> chartData;
  final bool chartLoading;
  final String symbol;
  const _PriceFold(
      {required this.analysis,
      required this.chartData,
      required this.chartLoading,
      required this.symbol});

  double get _low => chartData.map((p) => p.close).reduce(math.min);
  double get _high => chartData.map((p) => p.close).reduce(math.max);

  @override
  Widget build(BuildContext context) {
    String answer;
    Color color;
    double progress = .5;

    if (chartData.isEmpty) {
      answer = chartLoading
          ? 'Checking the last 30 days…'
          : 'Chart data unavailable';
      color = _T.sub(context);
    } else {
      final span = _high - _low;
      progress = span == 0
          ? .5
          : ((analysis.currentPrice - _low) / span).clamp(0.0, 1.0);
      if (progress < .33) {
        answer = 'Near its 30-day low';
        color = _T.down;
      } else if (progress > .66) {
        answer = 'Near its 30-day high';
        color = _T.up;
      } else {
        answer = 'In the middle of its 30-day range';
        color = _T.mid;
      }
    }

    return _Fold(
      icon: Icons.show_chart_rounded,
      color: color,
      title: 'Where is the price now?',
      answer: answer,
      child: chartData.isEmpty
          ? (chartLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))))
              : const _Note(
                  'We could not load the last 30 days of prices. Pull down to refresh and try again.'))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _RangeBar(
                  low: _low,
                  high: _high,
                  current: analysis.currentPrice,
                  progress: progress,
                  color: color),
              const SizedBox(height: 14),
              _PriceChart(data: chartData, up: analysis.dayChangePct >= 0),
              const SizedBox(height: 12),
              const _Note(
                  'Near the low can mean cheap or can mean weak. Near the high can mean strong or can mean stretched. Use it with the other cards.'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => BrowserLite_V(
                              'https://in.tradingview.com/chart/?symbol=NSE%3A$symbol'))),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text('Open full chart on TradingView',
                      style: _ts(context,
                          s: 13, w: FontWeight.w700, color: _T.link)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _T.link,
                    side: BorderSide(color: _T.link.withOpacity(.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
    );
  }
}

class _RangeBar extends StatelessWidget {
  final double low, high, current, progress;
  final Color color;
  const _RangeBar(
      {required this.low,
      required this.high,
      required this.current,
      required this.progress,
      required this.color});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('30-day low',
                style: _ts(context, s: 11.5, color: _T.sub(context))),
            Text('₹${_n2.format(low)}',
                style: _ts(context,
                    s: 13, w: FontWeight.w800, color: _T.down, figures: true)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('30-day high',
                style: _ts(context, s: 11.5, color: _T.sub(context))),
            Text('₹${_n2.format(high)}',
                style: _ts(context,
                    s: 13, w: FontWeight.w800, color: _T.up, figures: true)),
          ]),
        ]),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (ctx, box) {
          const knob = 16.0;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) {
              final x =
                  (v * box.maxWidth).clamp(knob / 2, box.maxWidth - knob / 2);
              return SizedBox(
                height: knob,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    top: (knob - 8) / 2,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                            colors: [_T.down, _T.mid, _T.up]),
                      ),
                    ),
                  ),
                  Positioned(
                    left: x - knob / 2,
                    child: Container(
                      width: knob,
                      height: knob,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: _T.surface(context), width: 3),
                      ),
                    ),
                  ),
                ]),
              );
            },
          );
        }),
      ]);
}

class _PriceChart extends StatelessWidget {
  final List<_ChartPoint> data;
  final bool up;
  const _PriceChart({required this.data, required this.up});

  @override
  Widget build(BuildContext context) {
    final lc = up ? _T.up : _T.down;
    final dark = _T.dark(context);
    final lbl = _T.sub(context);
    return SizedBox(
      height: 190,
      child: SfCartesianChart(
        plotAreaBorderWidth: 0,
        margin: const EdgeInsets.only(right: 4),
        backgroundColor: Colors.transparent,
        primaryXAxis: DateTimeAxis(
          dateFormat: DateFormat('MMM d'),
          intervalType: DateTimeIntervalType.days,
          interval: 7,
          majorGridLines: const MajorGridLines(width: 0),
          axisLine: const AxisLine(width: 0),
          majorTickLines: const MajorTickLines(size: 0),
          labelStyle: TextStyle(color: lbl, fontSize: 10),
        ),
        primaryYAxis: NumericAxis(
          numberFormat: NumberFormat.compactCurrency(symbol: '₹'),
          majorGridLines: MajorGridLines(
              color: _T.hair(context), width: 1, dashArray: const [3, 3]),
          axisLine: const AxisLine(width: 0),
          majorTickLines: const MajorTickLines(size: 0),
          labelStyle: TextStyle(color: lbl, fontSize: 10),
          opposedPosition: true,
        ),
        series: <CartesianSeries<_ChartPoint, DateTime>>[
          AreaSeries<_ChartPoint, DateTime>(
            dataSource: data,
            xValueMapper: (d, _) => d.date,
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
          builder: (d, point, series, pIdx, sIdx) {
            if (pIdx < 0 || pIdx >= data.length) return const SizedBox.shrink();
            final pt = data[pIdx];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _T.surface(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _T.hair(context)),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DateFormat('MMM d, yyyy').format(pt.date),
                        style: _ts(context, s: 10.5, color: _T.sub(context))),
                    Text('₹${_n2.format(pt.close)}',
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
    );
  }
}

class _ScannersFold extends StatelessWidget {
  final ScreenerAnalysis sa;
  const _ScannersFold({required this.sa});

  @override
  Widget build(BuildContext context) {
    final b = sa.bullishCount, r = sa.bearishCount;
    final total = b + r;
    final color = total == 0
        ? _T.sub(context)
        : b > r
            ? _T.up
            : r > b
                ? _T.down
                : _T.mid;
    final answer = total == 0 ? 'No signals found' : '$b positive, $r negative';

    return _Fold(
      icon: Icons.radar_rounded,
      color: color,
      title: 'What are the chart scanners saying?',
      answer: answer,
      child: total == 0
          ? const _Note(
              'Our scanners look for known chart patterns. None were found for this stock today.')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (sa.summary.isNotEmpty) ...[
                _AiLine(sa.summary),
                const SizedBox(height: 14),
              ],
              if (sa.bullish.isNotEmpty) ...[
                Text('Positive signs',
                    style:
                        _ts(context, s: 13, w: FontWeight.w700, color: _T.up)),
                const SizedBox(height: 8),
                Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: sa.bullish
                        .map((s) => _SignalChip(s: s, color: _T.up))
                        .toList()),
                const SizedBox(height: 14),
              ],
              if (sa.bearish.isNotEmpty) ...[
                Text('Negative signs',
                    style: _ts(context,
                        s: 13, w: FontWeight.w700, color: _T.down)),
                const SizedBox(height: 8),
                Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: sa.bearish
                        .map((s) => _SignalChip(s: s, color: _T.down))
                        .toList()),
                const SizedBox(height: 14),
              ],
              const _Note(
                  'Scanners are automatic checks for chart patterns. More positive than negative is a good sign, but never a guarantee.'),
            ]),
    );
  }
}

class _SignalChip extends StatelessWidget {
  final ScreenerSignal s;
  final Color color;
  const _SignalChip({required this.s, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: color.withOpacity(.1),
            borderRadius: BorderRadius.circular(10)),
        child: Text(s.timeframe.isEmpty ? s.name : '${s.name} (${s.timeframe})',
            style: _ts(context, s: 12, w: FontWeight.w700, color: color)),
      );
}

class _AlertsFold extends StatelessWidget {
  final AlertSummary alert;
  const _AlertsFold({required this.alert});
  @override
  Widget build(BuildContext context) {
    final color = alert.proximityNotes.isNotEmpty ? _T.mid : _T.sub(context);
    return _Fold(
      icon: Icons.notifications_active_rounded,
      color: color,
      title: 'What about your alerts?',
      answer:
          '${alert.triggeredCount} triggered, ${alert.pendingCount} waiting',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (alert.proximityNotes.isNotEmpty)
          _BulletList(items: alert.proximityNotes, color: _T.mid),
        if (alert.summary.isNotEmpty) ...[
          if (alert.proximityNotes.isNotEmpty) const SizedBox(height: 12),
          _AiLine(alert.summary),
        ],
        if (alert.proximityNotes.isEmpty && alert.summary.isEmpty)
          const _Note(
              'Triggered means the price already hit your alert. Waiting means it has not yet.'),
      ]),
    );
  }
}

class _IndicatorsFold extends StatelessWidget {
  final String indicators, volume;
  const _IndicatorsFold({required this.indicators, required this.volume});
  @override
  Widget build(BuildContext context) => _Fold(
        icon: Icons.analytics_rounded,
        color: _T.link,
        title: 'What do indicators and volume say?',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (indicators.isNotEmpty) ...[
            Text('Indicators', style: _ts(context, s: 13, w: FontWeight.w700)),
            Text('Maths-based readings of price momentum and trend',
                style: _ts(context, s: 12, color: _T.sub(context))),
            const SizedBox(height: 6),
            _Para(indicators),
          ],
          if (indicators.isNotEmpty && volume.isNotEmpty)
            const SizedBox(height: 14),
          if (volume.isNotEmpty) ...[
            Text('Volume', style: _ts(context, s: 13, w: FontWeight.w700)),
            Text('How many shares are being traded',
                style: _ts(context, s: 12, color: _T.sub(context))),
            const SizedBox(height: 6),
            _Para(volume),
          ],
        ]),
      );
}

// ─── Plans ────────────────────────────────────────────────────────────────────
String _planName(String type) {
  switch (type.toLowerCase()) {
    case 'conservative':
      return 'Cautious';
    case 'aggressive':
      return 'Bold';
    case 'moderate':
    case 'balanced':
      return 'Balanced';
    default:
      return type.isEmpty ? 'Plan' : type;
  }
}

Color _planColor(String type) {
  switch (type.toLowerCase()) {
    case 'conservative':
      return _T.up;
    case 'aggressive':
      return _T.mid;
    default:
      return _T.link;
  }
}

String _rewardText(String rr) {
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*:\s*(\d+(?:\.\d+)?)').firstMatch(rr);
  if (m != null) {
    final a = double.parse(m.group(1)!);
    final b = double.parse(m.group(2)!);
    if (a > 0) {
      final x = b / a;
      final txt =
          x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
      return 'For every ₹1 you risk, you could gain about ₹$txt';
    }
  }
  return rr.isEmpty ? '' : 'Risk vs reward: $rr';
}

class _PlanSection extends StatelessWidget {
  final List<EntryOpportunity> entries;
  final int selected;
  final ValueChanged<int> onSelect;
  const _PlanSection(
      {required this.entries, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _T.surface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _T.hair(context)),
        ),
        child: Row(children: [
          const Icon(Icons.hourglass_empty_rounded, color: _T.mid, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text('No clear entry right now. Waiting is also a decision.',
                style: _ts(context, s: 14, w: FontWeight.w700)),
          ),
        ]),
      );
    }

    final i = selected.clamp(0, entries.length - 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (entries.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (int k = 0; k < entries.length; k++)
              _PlanChip(
                label: '${_planName(entries[k].type)} plan',
                color: _planColor(entries[k].type),
                active: k == i,
                onTap: () => onSelect(k),
              ),
          ]),
        ),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(.04, 0), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: _PlanCard(key: ValueKey(i), entry: entries[i]),
      ),
    ]);
  }
}

class _PlanChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _PlanChip(
      {required this.label,
      required this.color,
      required this.active,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? color : _T.hair(context)),
          ),
          child: Text(label,
              style: _ts(context,
                  s: 13,
                  w: FontWeight.w700,
                  color: active ? Colors.white : _T.ink(context))),
        ),
      );
}

class _PlanCard extends StatelessWidget {
  final EntryOpportunity entry;
  const _PlanCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = _planColor(entry.type);
    final reward = _rewardText(entry.riskReward);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _T.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_planName(entry.type)} plan',
            style: _ts(context, s: 16, w: FontWeight.w800, color: color)),
        if (entry.entryZone.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Possible entry: ${entry.entryZone}',
              style:
                  _ts(context, s: 13, color: _T.sub(context), figures: true)),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _LevelBox(
                  label: 'Exit if it hits',
                  hint: 'stop-loss',
                  value: '₹${_n2.format(entry.stopLoss)}',
                  color: _T.down)),
          const SizedBox(width: 8),
          Expanded(
              child: _LevelBox(
                  label: 'First goal',
                  hint: 'target 1',
                  value: '₹${_n2.format(entry.target1)}',
                  color: _T.up)),
          const SizedBox(width: 8),
          Expanded(
              child: _LevelBox(
                  label: 'Second goal',
                  hint: 'target 2',
                  value: '₹${_n2.format(entry.target2)}',
                  color: _T.up)),
        ]),
        if (reward.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.balance_rounded, size: 15, color: _T.sub(context)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(reward,
                    style: _ts(context, s: 13, w: FontWeight.w600))),
          ]),
        ],
        if (entry.rationale.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AiLine(entry.rationale),
        ],
        const SizedBox(height: 12),
        const _Note(
            'A stop-loss is the price where you would exit to limit your loss. Goals are prices where you could book profit.'),
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
          Text(label, style: _ts(context, s: 11.5, color: _T.sub(context))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: _ts(context,
                    s: 15, w: FontWeight.w800, color: color, figures: true)),
          ),
          Text(hint, style: _ts(context, s: 10.5, color: _T.sub(context))),
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
              border: Border.all(color: _T.link.withOpacity(.4)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.analytics_outlined, size: 18, color: _T.link),
              const SizedBox(width: 8),
              Text(open ? 'Hide extra details' : 'Show extra details',
                  style:
                      _ts(context, s: 14, w: FontWeight.w700, color: _T.link)),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: open ? .5 : 0,
                duration: const Duration(milliseconds: 250),
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: _T.link),
              ),
            ]),
          ),
        ),
      );
}

class _LevelsBlock extends StatelessWidget {
  final List<PriceLevel> supports, resistances;
  const _LevelsBlock({required this.supports, required this.resistances});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _group(context, 'Support (floors)', 'Price often stops falling here',
            supports, _T.up),
        const SizedBox(height: 16),
        _group(context, 'Resistance (ceilings)',
            'Price often stops rising here', resistances, _T.down),
      ]);

  double _opacity(String s) => s == 'Strong'
      ? 1.0
      : s == 'Moderate'
          ? .6
          : .35;

  Widget _group(BuildContext context, String title, String hint,
          List<PriceLevel> levels, Color color) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: _ts(context, s: 13.5, w: FontWeight.w700)),
        Text(hint, style: _ts(context, s: 12, color: _T.sub(context))),
        const SizedBox(height: 10),
        if (levels.isEmpty)
          Text('None marked',
              style: _ts(context, s: 12.5, color: _T.sub(context)))
        else
          for (final l in levels)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IntrinsicHeight(
                child: Row(children: [
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                        color: color.withOpacity(_opacity(l.strength)),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('₹${_n2.format(l.price)}',
                            style: _ts(context,
                                s: 15, w: FontWeight.w800, figures: true)),
                        Text(l.strength,
                            style: _ts(context, s: 11.5, color: color)),
                      ]),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(l.note,
                          style: _ts(context,
                              s: 12.5, color: _T.sub(context), h: 1.45))),
                ]),
              ),
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

class _SourcesBlock extends StatelessWidget {
  final List<FetchCheck> checks;
  const _SourcesBlock({required this.checks});
  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final c in checks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(
                    c.found ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 15,
                    color: c.found ? _T.up : _T.down),
                const SizedBox(width: 10),
                Expanded(child: Text(c.source, style: _ts(context, s: 12.5))),
                Text(
                    c.found
                        ? (c.count > 0 ? '${c.count} rows' : 'ok')
                        : 'missing',
                    style: _ts(context,
                        s: 11.5, color: c.found ? _T.sub(context) : _T.down)),
              ]),
            ),
        ],
      );
}

// ─── Footer ───────────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  final StockAnalysis analysis;
  const _Footer({required this.analysis});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Column(children: [
          Text(
              'Updated ${analysis.lastUpdated}'
              '${analysis.cached ? " · saved copy" : " · fresh from AI"}'
              '${analysis.timeframe.isNotEmpty ? " · ${analysis.timeframe}" : ""}',
              textAlign: TextAlign.center,
              style: _ts(context, s: 11.5, color: _T.sub(context))),
          const SizedBox(height: 6),
          Text(
              'For learning only. Not financial advice. Please speak to a SEBI-registered advisor before you trade.',
              textAlign: TextAlign.center,
              style: _ts(context, s: 11.5, color: _T.sub(context), h: 1.5)),
        ]),
      );
}
