// breakout_signals_page.dart
//
// Redesign notes
// ───────────────────────────────────────────────────────────────────────
// • Merges the old "BollingerBreakoutsPage" (a plain list) with the chart
//   view from "MarketSentimentChartPage" into ONE screen that shows a
//   NIFTY / BANK NIFTY candlestick chart with every breakout plotted
//   directly on the price, plus a plain-English list underneath.
// • "Entries" (whichmode == 'checkfirst') are drawn as big, bold, labelled
//   triangles. Regular breakouts are small diamonds/squares. Tapping any
//   marker — or any card in the list — opens a bottom sheet that explains
//   the signal in plain language, no jargon.
// • SCHEMA (confirmed from real data): `bollinger_breakouts` has
//   (id, description, sentiment, time, whichmode, created_at) — no `symbol`
//   column. Its `description` is a market-BREADTH count ("No of stocks
//   breaking upper bollingerband is: 32"), not a per-index price level, so
//   it isn't tied to NIFTY vs BANK NIFTY specifically. This file therefore
//   fetches breakouts once per day (not filtered by symbol) and overlays
//   the same feed on whichever chart you're viewing — it's a market-wide
//   signal either way. `nifty_ohlcv` DOES have a `symbol` column
//   ('NIFTY' | 'BANKNIFTY'), which is used for the price chart itself.
//
// Anti-flicker notes
// ───────────────────────────────────────────────────────────────────────
// • All chart animations are disabled (animationDuration: 0) — replaying
//   the entry animation on every rebuild is what caused the "blink".
// • Chart behaviors (trackball/tooltip) are hoisted to final fields so they
//   aren't reconstructed on every build.
// • The chart lives in its own `_PriceChart` widget wrapped in a
//   RepaintBoundary, so live data inserts don't force a full re-layout.
// • Live inserts from the realtime subscription are debounced (~400 ms) so
//   a burst of inserts coalesces into a single setState.
//
// Marker-visibility notes
// ───────────────────────────────────────────────────────────────────────
// • Marker outlines are themed: white on dark backgrounds (near-black page),
//   near-black on light backgrounds (near-white page). A hard-coded white
//   outline is invisible on the light theme — that's why the markers "only
//   worked in dark mode". Red/green fills stay exactly as they were.
//
// Dependencies:
//   supabase_flutter, intl, flutter_animate, syncfusion_flutter_charts, timeago

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;

// ═══════════════════════════════════════════════════════════════════════
// Design tokens
// ═══════════════════════════════════════════════════════════════════════
class BX {
  static const bull = Color(0xFF00C896);
  static const bear = Color(0xFFFF4D6A);
  static const accent = Color(0xFF5B7FFF);
  static const neutral = Color(0xFF8896AE);

  static const darkBg = Color(0xFF0D0F14);
  static const darkSurface = Color(0xFF161920);
  static const darkCard = Color(0xFF1C2029);
  static const darkBorder = Color(0xFF272B36);
  static const darkTextS = Color(0xFF8B93A7);

  static const lightBg = Color(0xFFF4F6FA);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE4E8F0);
  static const lightTextS = Color(0xFF8896AE);

  static const rSM = 10.0, rMD = 14.0, rLG = 18.0;
}

extension BXContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get bg => isDark ? BX.darkBg : BX.lightBg;
  Color get surface => isDark ? BX.darkCard : BX.lightCard;
  Color get border => isDark ? BX.darkBorder : BX.lightBorder;
  Color get textP => isDark ? Colors.white : const Color(0xFF0D0F14);
  Color get textS => isDark ? BX.darkTextS : BX.lightTextS;
}

const List<String> kSymbols = ['NIFTY', 'BANKNIFTY'];
String symbolLabel(String s) => s == 'NIFTY' ? 'Nifty 50' : 'Bank Nifty';

// ═══════════════════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════════════════
class OhlcvBar {
  final DateTime ts;
  final double open, high, low, close;
  OhlcvBar(
      {required this.ts,
      required this.open,
      required this.high,
      required this.low,
      required this.close});

  factory OhlcvBar.fromJson(Map<String, dynamic> j) => OhlcvBar(
        ts: DateTime.parse(j['ts']).toLocal(),
        open: (j['open'] as num).toDouble(),
        high: (j['high'] as num).toDouble(),
        low: (j['low'] as num).toDouble(),
        close: (j['close'] as num).toDouble(),
      );
}

/// A single Bollinger Band breakout. NOTE: the real table has no `symbol`
/// column — `description` is a market-breadth count of how many individual
/// stocks broke their band, e.g. "No of stocks breaking upper bollingerband
/// is: 32". It's a market-wide reading, so the same signal is shown on
/// whichever chart (NIFTY or Bank Nifty) you happen to be looking at.
class BreakoutSignal {
  final int id;
  final DateTime ts;
  final bool isBull; // sentiment == 'bullish'
  final bool isEntry; // whichmode == 'checkfirst' (first breakout of a move)
  final int? stockCount; // the count pulled out of the raw description

  BreakoutSignal({
    required this.id,
    required this.ts,
    required this.isBull,
    required this.isEntry,
    required this.stockCount,
  });

  factory BreakoutSignal.fromJson(Map<String, dynamic> j) {
    final desc = (j['description'] ?? '') as String;
    final match = RegExp(r':\s*([\d,]+)').firstMatch(desc);
    final count = match != null
        ? int.tryParse(match.group(1)!.replaceAll(',', ''))
        : null;
    return BreakoutSignal(
      id: j['id'] as int,
      ts: DateTime.parse(j['created_at'] as String).toLocal(),
      isBull: j['sentiment'] == 'bullish',
      isEntry: j['whichmode'] == 'checkfirst',
      stockCount: count,
    );
  }

  // ── Plain-English translations (no "bollinger", "whichmode", etc.) ────

  /// Short label used on chips / badges.
  String get shortLabel =>
      isBull ? 'More stocks pushing up' : 'More stocks pushing down';

  /// One-line summary for list cards. `symbol` is the chart currently open —
  /// this is a market-wide reading, not specific to that index.
  String headline(String symbol) {
    final n = stockCount != null ? '$stockCount stocks' : 'A batch of stocks';
    return isBull
        ? '$n broke above their usual range — market leaning bullish'
        : '$n broke below their usual range — market leaning bearish';
  }

  /// Longer explanation for the detail sheet.
  String story(String symbol) {
    final time = DateFormat('h:mm a').format(ts);
    final n = stockCount != null ? '$stockCount stocks' : 'a batch of stocks';
    final b = StringBuffer(
        'At $time, $n moved outside the price range they\'d normally trade in. ');
    b.write(isBull
        ? 'More stocks broke ABOVE their band than below it, which usually means buyers are in control across the market right now — good context while you\'re watching ${symbolLabel(symbol)}. '
        : 'More stocks broke BELOW their band than above it, which usually means sellers are in control across the market right now — good context while you\'re watching ${symbolLabel(symbol)}. ');
    if (isEntry) {
      b.write(
          'This is the FIRST reading of its kind after the trend flipped direction, so it\'s flagged as an entry — the moment a brand-new move may be starting, which is when traders pay the closest attention.');
    } else {
      b.write(
          'The trend was already leaning this way, so this is a continuation rather than a fresh start.');
    }
    return b.toString();
  }
}

class _MarkerPoint {
  final DateTime ts;
  final double price;
  final BreakoutSignal signal;
  _MarkerPoint({required this.ts, required this.price, required this.signal});
}

/// Immutable bundle of everything the chart needs to render. Passing this
/// into `_PriceChart` (a separate widget) lets Flutter's element diffing
/// keep the underlying Syncfusion chart state stable across list rebuilds.
class _ChartData {
  final List<OhlcvBar> bars;
  final List<_MarkerPoint> entryUp, entryDown, plainUp, plainDown;
  const _ChartData({
    required this.bars,
    required this.entryUp,
    required this.entryDown,
    required this.plainUp,
    required this.plainDown,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════
class BreakoutService {
  static final _db = Supabase.instance.client;

  /// Start/end of the given *calendar* day in the device's local timezone,
  /// converted to real UTC instants. Using full ISO-8601 UTC timestamps
  /// (instead of naive "yyyy-MM-dd" strings) avoids day-boundary bugs when
  /// the device timezone isn't UTC (e.g. IST is UTC+5:30, so midnight IST
  /// is 18:30 UTC the previous day — a plain date string gets that wrong).
  static (String, String) _dayBoundsUtc(DateTime date) {
    final startLocal = DateTime(date.year, date.month, date.day);
    final endLocal = startLocal.add(const Duration(days: 1));
    return (
      startLocal.toUtc().toIso8601String(),
      endLocal.toUtc().toIso8601String()
    );
  }

  static Future<List<OhlcvBar>> fetchOhlcv(DateTime date, String symbol) async {
    final (start, end) = _dayBoundsUtc(date);
    final rows = await _db
        .from('nifty_ohlcv')
        .select('ts,open,high,low,close')
        .eq('symbol', symbol)
        .gte('ts', start)
        .lt('ts', end)
        .order('ts');
    return (rows as List)
        .map((e) => OhlcvBar.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `bollinger_breakouts` has no `symbol` column — it's a market-wide
  /// breadth reading, not per-index — so this is fetched once per day and
  /// reused for whichever chart (NIFTY / Bank Nifty) is currently open.
  static Future<List<BreakoutSignal>> fetchBreakouts(DateTime date) async {
    final (start, end) = _dayBoundsUtc(date);
    final rows = await _db
        .from('bollinger_breakouts')
        .select()
        .gte('created_at', start)
        .lt('created_at', end)
        .order('created_at');
    return (rows as List)
        .map((e) => BreakoutSignal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Stream<BreakoutSignal> subscribe() {
    final controller = StreamController<BreakoutSignal>.broadcast();
    final channel = _db.channel('breakouts_feed');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'bollinger_breakouts',
      callback: (payload) {
        if (payload.newRecord.isNotEmpty) {
          try {
            controller.add(BreakoutSignal.fromJson(
                Map<String, dynamic>.from(payload.newRecord)));
          } catch (_) {}
        }
      },
    );
    channel.subscribe();
    controller.onCancel = () => channel.unsubscribe();
    return controller.stream;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page
// ═══════════════════════════════════════════════════════════════════════
class BreakoutSignalsPage extends StatefulWidget {
  const BreakoutSignalsPage({super.key});
  @override
  State<BreakoutSignalsPage> createState() => _BreakoutSignalsPageState();
}

class _BreakoutSignalsPageState extends State<BreakoutSignalsPage> {
  String _symbol = kSymbols.first;
  DateTime _date = _todayMarket();
  List<OhlcvBar> _bars = [];
  List<BreakoutSignal> _signals = [];
  bool _loading = true;
  String? _error;
  bool _entriesOnly = false;
  int _req = 0;
  StreamSubscription? _sub;

  // ── Live-insert debounce ────────────────────────────────────────────
  final List<BreakoutSignal> _pendingSignals = [];
  Timer? _liveDebounce;

  static DateTime _todayMarket() {
    final n = DateTime.now();
    if (n.hour < 9 || (n.hour == 9 && n.minute < 15)) {
      return DateTime(n.year, n.month, n.day - 1);
    }
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _fetch();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _liveDebounce?.cancel();
    super.dispose();
  }

  void _listen() {
    _sub?.cancel();
    if (!_isToday(_date)) return;
    _sub = BreakoutService.subscribe().listen((s) {
      if (!mounted) return;
      // Coalesce bursts of inserts into one setState.
      _pendingSignals.add(s);
      _liveDebounce?.cancel();
      _liveDebounce = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() {
          _signals = [..._signals, ..._pendingSignals];
          _pendingSignals.clear();
        });
      });
    });
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  Future<void> _fetch() async {
    final req = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        BreakoutService.fetchOhlcv(_date, _symbol),
        BreakoutService.fetchBreakouts(_date),
      ]);
      if (!mounted || req != _req) return;
      setState(() {
        _bars = results[0] as List<OhlcvBar>;
        _signals = results[1] as List<BreakoutSignal>;
        _loading = false;
      });
      _listen();
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _error =
            'Could not load this day. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  void _switchSymbol(String s) {
    if (s == _symbol) return;
    setState(() => _symbol = s);
    _fetch();
  }

  void _shiftDate(int delta) {
    final n = _date.add(Duration(days: delta));
    if (n.isAfter(DateTime.now())) return;
    setState(() => _date = DateTime(n.year, n.month, n.day));
    _fetch();
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme:
                Theme.of(ctx).colorScheme.copyWith(primary: BX.accent)),
        child: child!,
      ),
    );
    if (p != null && mounted) {
      setState(() => _date = DateTime(p.year, p.month, p.day));
      _fetch();
    }
  }

  String get _dateLabel {
    final diff = DateTime.now().difference(_date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('d MMM yyyy').format(_date);
  }

  List<BreakoutSignal> get _filtered =>
      _entriesOnly ? _signals.where((s) => s.isEntry).toList() : _signals;

  int get _upCount => _signals.where((s) => s.isBull).length;
  int get _downCount => _signals.length - _upCount;
  int get _entryCount => _signals.where((s) => s.isEntry).length;

  OhlcvBar? _nearestBar(DateTime ts) {
    if (_bars.isEmpty) return null;
    OhlcvBar? best;
    var bd = const Duration(days: 999);
    for (final b in _bars) {
      final d = b.ts.difference(ts).abs();
      if (d < bd) {
        bd = d;
        best = b;
      }
    }
    return best;
  }

  /// Build the immutable chart payload once per build of the parent.
  /// The expensive index-mapping happens here, not inside the chart widget,
  /// and the result is passed down so `_PriceChart` can stay stateless.
  _ChartData _buildChartData() {
    final entryUp = <_MarkerPoint>[], entryDown = <_MarkerPoint>[];
    final plainUp = <_MarkerPoint>[], plainDown = <_MarkerPoint>[];

    for (final s in _filtered) {
      final bar = _nearestBar(s.ts);
      if (bar == null) continue;
      final range = (bar.high - bar.low).abs();
      final off =
          range > 0 ? range * (s.isEntry ? 0.18 : 0.07) : bar.close * 0.0007;
      if (s.isBull) {
        final p = _MarkerPoint(ts: bar.ts, price: bar.high + off, signal: s);
        (s.isEntry ? entryUp : plainUp).add(p);
      } else {
        final p = _MarkerPoint(ts: bar.ts, price: bar.low - off, signal: s);
        (s.isEntry ? entryDown : plainDown).add(p);
      }
    }

    return _ChartData(
      bars: _bars,
      entryUp: entryUp,
      entryDown: entryDown,
      plainUp: plainUp,
      plainDown: plainDown,
    );
  }

  void _openDetail(BreakoutSignal s) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _DetailSheet(signal: s, symbol: _symbol),
      );

  void _openInfo() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _WhatIsABreakoutSheet(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: RefreshIndicator(
                color: BX.accent,
                onRefresh: _fetch,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: BX.accent))
                    : _error != null
                        ? _errorView()
                        : _bars.isEmpty
                            ? _emptyPriceView()
                            : _content(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────
  Widget _header() {
    final canPop = Navigator.of(context).canPop();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: context.bg,
        border: Border(bottom: BorderSide(color: context.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (canPop) ...[
                _iconBtn(Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_isToday(_date)) ...[
                          const _LiveDot(),
                          const SizedBox(width: 6),
                          const Text('LIVE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: BX.bull)),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    Text('Breakout Signals',
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: context.textP)),
                    Text('When price broke out of its usual range',
                        style: TextStyle(fontSize: 11.5, color: context.textS)),
                  ],
                ),
              ),
              _iconBtn(Icons.help_outline_rounded, onTap: _openInfo),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Symbol switch
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(BX.rMD),
                  border: Border.all(color: context.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in kSymbols)
                      GestureDetector(
                        onTap: () => _switchSymbol(s),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                s == _symbol ? BX.accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(BX.rSM),
                          ),
                          child: Text(symbolLabel(s),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: s == _symbol
                                      ? Colors.white
                                      : context.textS)),
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              // Date switch
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(BX.rMD),
                  border: Border.all(color: context.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _navBtn(Icons.chevron_left_rounded, () => _shiftDate(-1)),
                    GestureDetector(
                      onTap: _pickDate,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 13, color: context.textS),
                            const SizedBox(width: 6),
                            Text(_dateLabel,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: context.textP)),
                          ],
                        ),
                      ),
                    ),
                    _navBtn(
                      Icons.chevron_right_rounded,
                      _date.isBefore(
                              DateTime.now().subtract(const Duration(days: 0)))
                          ? () => _shiftDate(1)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, {required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(BX.rSM),
            border: Border.all(color: context.border),
          ),
          child: Icon(icon, size: 17, color: context.textS),
        ),
      );

  Widget _navBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 34,
          height: 38,
          child: Icon(icon,
              size: 20,
              color: onTap != null
                  ? context.textP
                  : context.textS.withOpacity(0.35)),
        ),
      );

  // ── States ──────────────────────────────────────────────────────────
  Widget _errorView() => ListView(children: [
        _messageBlock(
          icon: Icons.wifi_off_rounded,
          color: BX.bear,
          title: 'Connection error',
          body: _error!,
          actionLabel: 'Try again',
          onAction: _fetch,
        ),
      ]);

  Widget _emptyPriceView() => ListView(children: [
        _messageBlock(
          icon: Icons.event_busy_rounded,
          color: BX.neutral,
          title: 'No prices for $_dateLabel',
          body: 'The market may have been closed that day. Try another date.',
          actionLabel: 'Go to previous day',
          onAction: () => _shiftDate(-1),
        ),
      ]);

  Widget _messageBlock({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.textP)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textS, height: 1.4)),
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                      color: BX.accent,
                      borderRadius: BorderRadius.circular(40)),
                  child: Text(actionLabel,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      );

  // ── Main content ────────────────────────────────────────────────────
  Widget _content() {
    final list = _filtered.reversed.toList();
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _summaryCard()),
        SliverToBoxAdapter(child: _chartCard()),
        SliverToBoxAdapter(child: _filterRow()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Row(
              children: [
                Text('Breakouts (${list.length})',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.textP)),
                const Spacer(),
                Text('Newest first',
                    style: TextStyle(fontSize: 11.5, color: context.textS)),
              ],
            ),
          ),
        ),
        if (list.isEmpty)
          SliverToBoxAdapter(
            child: _messageBlock(
              icon: Icons.filter_alt_off_rounded,
              color: BX.neutral,
              title: 'No breakouts match',
              body:
                  'Turn off "Entries only" to see every breakout for the day.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _SignalCard(
                  signal: list[i],
                  symbol: _symbol,
                  index: i,
                  onTap: () => _openDetail(list[i]),
                ),
                childCount: list.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _summaryCard() {
    final first = _bars.first, last = _bars.last;
    final change = last.close - first.open;
    final pct = first.open == 0 ? 0.0 : change / first.open * 100;
    final isUp = change >= 0;
    final col = isUp ? BX.bull : BX.bear;
    final nf = NumberFormat('#,##0.00');

    String sentence;
    if (_signals.isEmpty) {
      sentence =
          'No breakouts were flagged for ${symbolLabel(_symbol)} on $_dateLabel.';
    } else {
      final lean = _upCount > _downCount
          ? 'Most breakouts today pushed the price up'
          : (_downCount > _upCount
              ? 'Most breakouts today pushed the price down'
              : 'Breakouts were evenly split');
      sentence =
          '$lean. Out of ${_signals.length} breakouts, $_entryCount marked the start of a brand-new move (an "entry").';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(symbolLabel(_symbol),
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: context.textS)),
                    const SizedBox(height: 2),
                    Text(nf.format(last.close),
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: context.textP)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: col.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(BX.rSM)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        isUp
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 14,
                        color: col),
                    const SizedBox(width: 4),
                    Text(
                        '${change.abs().toStringAsFixed(1)} (${pct.abs().toStringAsFixed(2)}%)',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: col)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: context.border),
          const SizedBox(height: 14),
          Text(sentence,
              style:
                  TextStyle(fontSize: 13, height: 1.45, color: context.textP)),
        ],
      ),
    );
  }

  Widget _filterRow() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(
          children: [
            _pill(
              label: 'All breakouts',
              count: _signals.length,
              color: BX.accent,
              active: !_entriesOnly,
              onTap: () => setState(() => _entriesOnly = false),
            ),
            const SizedBox(width: 8),
            _pill(
              label: 'Entries only',
              count: _entryCount,
              color: BX.accent,
              icon: Icons.bolt_rounded,
              active: _entriesOnly,
              onTap: () => setState(() => _entriesOnly = true),
            ),
          ],
        ),
      );

  Widget _pill({
    required String label,
    required int count,
    required Color color,
    required bool active,
    required VoidCallback onTap,
    IconData? icon,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.13) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? color.withOpacity(0.5) : context.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: active ? color : context.textS),
                const SizedBox(width: 5)
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? color : context.textP)),
              const SizedBox(width: 6),
              Text('$count',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? color : context.textS)),
            ],
          ),
        ),
      );

  // ── Chart card ──────────────────────────────────────────────────────
  //
  // `_PriceChart` is its own StatelessWidget wrapped in a RepaintBoundary,
  // so when a live breakout arrives and the parent rebuilds, the Syncfusion
  // chart's render tree is preserved. Combined with `animationDuration: 0`
  // on all series, the chart never re-runs its entry animation — that's
  // the "blink" fix.
  Widget _chartCard() {
    final data = _buildChartData();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text('Price chart',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.textP)),
                const Spacer(),
                Text('Tap a marker for details',
                    style: TextStyle(fontSize: 11, color: context.textS)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _Legend('▲', BX.bull, 'Entry — new move up'),
                _Legend('▼', BX.bear, 'Entry — new move down'),
                _Legend('◆', BX.bull, 'Breakout up'),
                _Legend('■', BX.bear, 'Breakout down'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 340,
            child: RepaintBoundary(
              child: _PriceChart(
                data: data,
                onMarkerTap: _openDetail,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(BX.rLG),
        border: Border.all(color: context.border),
        boxShadow: context.isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
      );
}

// ═══════════════════════════════════════════════════════════════════════
// Chart widget — kept separate so its element tree stays stable across
// parent rebuilds. All animations disabled. Behaviors are `final` fields
// so they aren't reconstructed on every frame. Marker outline is themed
// so red / green markers read clearly on both light and dark backgrounds.
// ═══════════════════════════════════════════════════════════════════════
class _PriceChart extends StatelessWidget {
  final _ChartData data;
  final void Function(BreakoutSignal) onMarkerTap;

  const _PriceChart({required this.data, required this.onMarkerTap});

  // Hoisted behaviors — constructed once per widget instance, not per build.
  static final TrackballBehavior _trackball = TrackballBehavior(
    enable: true,
    activationMode: ActivationMode.singleTap,
    tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
  );
  static final TooltipBehavior _tooltip = TooltipBehavior(enable: false);

  ScatterSeries<_MarkerPoint, DateTime> _markerSeries(
    List<_MarkerPoint> pts, {
    required Color fillColor,
    required Color borderColor,
    required DataMarkerType shape,
    required double size,
    required String name,
  }) =>
      ScatterSeries<_MarkerPoint, DateTime>(
        dataSource: pts,
        xValueMapper: (p, _) => p.ts,
        yValueMapper: (p, _) => p.price,
        pointColorMapper: (_, __) => fillColor,
        markerSettings: MarkerSettings(
          isVisible: true,
          height: size,
          width: size,
          shape: shape,
          borderWidth: 1.5,
          borderColor: borderColor, // ← themed, not hard-coded white
        ),
        animationDuration: 0, // ← no re-animation on rebuild
        name: name,
        enableTooltip: false,
        onPointTap: (args) {
          final i = args.pointIndex;
          if (i != null && i < pts.length) onMarkerTap(pts[i].signal);
        },
      );

  @override
  Widget build(BuildContext context) {
    final grid = context.textS.withOpacity(0.18);
    final label = context.textS;

    // Marker outline that reads on both themes:
    //   dark theme  → white outline on the near-black chart
    //   light theme → near-black outline on the near-white chart
    // The red / green fills (BX.bear / BX.bull) are unchanged in both modes.
    final markerBorder =
        context.isDark ? Colors.white : const Color(0xFF0D0F14);

    return SfCartesianChart(
      backgroundColor: Colors.transparent,
      plotAreaBorderWidth: 0,
      trackballBehavior: _trackball,
      legend: const Legend(isVisible: false),
      tooltipBehavior: _tooltip,
      primaryXAxis: DateTimeAxis(
        intervalType: DateTimeIntervalType.minutes,
        interval: 60,
        dateFormat: DateFormat('h:mm a'),
        axisLine: AxisLine(width: 0.5, color: grid),
        majorGridLines: MajorGridLines(width: 0.3, color: grid),
        minorGridLines: const MinorGridLines(width: 0),
        labelStyle: TextStyle(fontSize: 10, color: label),
        edgeLabelPlacement: EdgeLabelPlacement.shift,
      ),
      primaryYAxis: NumericAxis(
        numberFormat: NumberFormat('#,###'),
        axisLine: const AxisLine(width: 0),
        majorGridLines: MajorGridLines(width: 0.3, color: grid),
        labelStyle: TextStyle(fontSize: 10, color: label),
        opposedPosition: true,
      ),
      series: <CartesianSeries>[
        CandleSeries<OhlcvBar, DateTime>(
          dataSource: data.bars,
          xValueMapper: (b, _) => b.ts,
          openValueMapper: (b, _) => b.open,
          highValueMapper: (b, _) => b.high,
          lowValueMapper: (b, _) => b.low,
          closeValueMapper: (b, _) => b.close,
          bullColor: BX.bull,
          bearColor: BX.bear,
          enableSolidCandles: true,
          animationDuration: 0, // ← no re-animation on rebuild
          name: 'Price',
        ),
        if (data.plainUp.isNotEmpty)
          _markerSeries(data.plainUp,
              fillColor: BX.bull,
              borderColor: markerBorder,
              shape: DataMarkerType.diamond,
              size: 9,
              name: 'Breakout up'),
        if (data.plainDown.isNotEmpty)
          _markerSeries(data.plainDown,
              fillColor: BX.bear,
              borderColor: markerBorder,
              shape: DataMarkerType.rectangle,
              size: 8,
              name: 'Breakout down'),
        if (data.entryUp.isNotEmpty)
          _markerSeries(data.entryUp,
              fillColor: BX.bull,
              borderColor: markerBorder,
              shape: DataMarkerType.triangle,
              size: 17,
              name: 'Entry up'),
        if (data.entryDown.isNotEmpty)
          _markerSeries(data.entryDown,
              fillColor: BX.bear,
              borderColor: markerBorder,
              shape: DataMarkerType.invertedTriangle,
              size: 17,
              name: 'Entry down'),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Small pieces
// ═══════════════════════════════════════════════════════════════════════
class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.25, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: Container(
            width: 8,
            height: 8,
            decoration:
                const BoxDecoration(shape: BoxShape.circle, color: BX.bull)),
      );
}

class _Legend extends StatelessWidget {
  final String glyph, text;
  final Color color;
  const _Legend(this.glyph, this.color, this.text);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(glyph, style: TextStyle(fontSize: 11, color: color)),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: context.textS)),
        ],
      );
}

class _SignalCard extends StatelessWidget {
  final BreakoutSignal signal;
  final String symbol;
  final int index;
  final VoidCallback onTap;
  const _SignalCard(
      {required this.signal,
      required this.symbol,
      required this.index,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = signal.isBull ? BX.bull : BX.bear;
    final surface =
        signal.isBull ? BX.bull.withOpacity(0.08) : BX.bear.withOpacity(0.08);

    return Animate(
      effects: [
        FadeEffect(
            delay: Duration(milliseconds: index * 50),
            duration: 300.ms,
            curve: Curves.easeOut),
        SlideEffect(
            delay: Duration(milliseconds: index * 50),
            duration: 300.ms,
            begin: const Offset(0, 0.05),
            end: Offset.zero,
            curve: Curves.easeOut),
      ],
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                    width: 4,
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(16)))),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      signal.isBull
                                          ? Icons.trending_up_rounded
                                          : Icons.trending_down_rounded,
                                      size: 13,
                                      color: color),
                                  const SizedBox(width: 4),
                                  Text(signal.shortLabel.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.8,
                                          color: color)),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (signal.isEntry)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: BX.accent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20)),
                                child: const Text('ENTRY',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.8,
                                        color: BX.accent)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(signal.headline(symbol),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                                color: context.textP)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                size: 11, color: context.textS),
                            const SizedBox(width: 4),
                            Text(DateFormat('MMM d, h:mm a').format(signal.ts),
                                style: TextStyle(
                                    fontSize: 11, color: context.textS)),
                            const Spacer(),
                            Text(timeago.format(signal.ts),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: context.textS)),
                          ],
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Detail sheet — the plain-English story for one breakout
// ═══════════════════════════════════════════════════════════════════════
class _DetailSheet extends StatelessWidget {
  final BreakoutSignal signal;
  final String symbol;
  const _DetailSheet({required this.signal, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final color = signal.isBull ? BX.bull : BX.bear;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: color, width: 3)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: context.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.12), shape: BoxShape.circle),
                    child: Icon(
                        signal.isBull
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: color,
                        size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            signal.isBull
                                ? 'Broke out upward'
                                : 'Broke out downward',
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: context.textP)),
                        Text(
                            '${symbolLabel(symbol)} · ${DateFormat('h:mm a, d MMM').format(signal.ts)}',
                            style:
                                TextStyle(fontSize: 12, color: context.textS)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (signal.isEntry)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: BX.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: BX.accent),
                      SizedBox(width: 6),
                      Text('ENTRY — start of a new move',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BX.accent)),
                    ],
                  ),
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(BX.rMD)),
                child: Text(signal.story(symbol),
                    style: TextStyle(
                        fontSize: 13.5, height: 1.5, color: context.textP)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// "What is a breakout?" explainer sheet
// ═══════════════════════════════════════════════════════════════════════
class _WhatIsABreakoutSheet extends StatelessWidget {
  const _WhatIsABreakoutSheet();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, Color color, String title, String body) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.textP)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.4, color: context.textS)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: context.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text('What\'s a breakout?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: context.textP)),
              const SizedBox(height: 4),
              Text('In plain English, no jargon.',
                  style: TextStyle(fontSize: 12.5, color: context.textS)),
              const SizedBox(height: 18),
              row(Icons.trending_up_rounded, BX.bull, 'Breakout up',
                  'The price moved higher than the range it had been trading in recently. Buyers are pushing harder than usual.'),
              row(Icons.trending_down_rounded, BX.bear, 'Breakout down',
                  'The price dropped lower than its recent range. Sellers are pushing harder than usual.'),
              row(Icons.bolt_rounded, BX.accent, 'Entry',
                  'The FIRST breakout after the trend flips direction. It often marks the moment a brand-new move begins, so it\'s the one worth watching most closely.'),
              row(
                  Icons.change_history_rounded,
                  BX.neutral,
                  'The markers on the chart',
                  'Small diamond/square = a regular breakout. Big triangle = an entry. Tap any marker to see the full explanation for that moment.'),
            ],
          ),
        ),
      ),
    );
  }
}
