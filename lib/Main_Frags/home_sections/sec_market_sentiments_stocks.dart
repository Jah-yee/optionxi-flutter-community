import 'dart:async';
import 'package:flutter/material.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// CONFIG
// ============================================================================
const String _kPicksTable = 'web_portfolio';
const String _kAccuracyTable = 'web_daily_accuracy';
const String _kCandlesTable = 'stock_candles_5m';
const int _kAccuracyDays = 14;
const int _kPicksLimit = 600;
const int _kGreenThreshold = 60;

const String _kStockLogoBaseUrl =
    'https://s3.optionxi.com/optionxi-stockimages/stockimages';
// String get _kStockLogoBaseUrl {
//   try {
//     final url = dotenv.env['S3_STOCKIMAGE_URL'] ?? '';
//     return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
//   } catch (_) {
//     return '';
//   }
// }

String _routeForStock(String symbol) => '/stocks/$symbol';

// Route for the full accuracy / backtest page.
const String _kRouteAccuracy = '/backtest/ai-picks';

// ============================================================================
// PALETTE
// ============================================================================
class _P {
  final Color bg,
      card,
      border,
      title,
      sub,
      muted,
      gold,
      indigo,
      bull,
      bear,
      amber,
      empty;
  const _P(this.bg, this.card, this.border, this.title, this.sub, this.muted,
      this.gold, this.indigo, this.bull, this.bear, this.amber, this.empty);

  factory _P.of(BuildContext c) {
    final dark = Theme.of(c).brightness == Brightness.dark;
    return dark
        ? const _P(
            Color(0xFF0E1016),
            Color(0xFF171A24),
            Color(0x33F5C451),
            Color(0xFFF5F6FA),
            Color(0xFFAEB4C2),
            Color(0xFF7B8194),
            Color(0xFFF5C451),
            Color(0xFF818CF8),
            Color(0xFF34D399),
            Color(0xFFF25F6B),
            Color(0xFFFBBF24),
            Color(0x14FFFFFF))
        : const _P(
            Color(0xFFF6F3EC),
            Color(0xFFFFFFFF),
            Color(0x33C7962C),
            Color(0xFF1B1D24),
            Color(0xFF565B6B),
            Color(0xFF8A8FA0),
            Color(0xFFB8862F),
            Color(0xFF6366F1),
            Color(0xFF12A375),
            Color(0xFFD8404C),
            Color(0xFFE0A100),
            Color(0x0F1B1D24));
  }
}

// ============================================================================
// MODELS + HELPERS
// ============================================================================
DateTime _ist(DateTime d) =>
    d.toUtc().add(const Duration(hours: 5, minutes: 30));
String _key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime _parseDay(String s) => DateTime.parse('${s}T00:00:00');
String _time(DateTime d) => DateFormat('h:mm a').format(_ist(d));
String _clean(String raw) =>
    raw.replaceAll(RegExp(r'^(NSE|BSE):'), '').replaceAll('-EQ', '');

class _Pick {
  final String symbol, pickDate, sentiment, status;
  final DateTime entryTime, evalTime;
  final double entryPrice, evalPrice, pnl;
  _Pick(Map<String, dynamic> m)
      : symbol = m['symbol'] as String,
        pickDate = m['pick_date'] as String,
        sentiment = (m['sentiment'] as String? ?? 'BULLISH').toUpperCase(),
        status = m['status'] as String? ?? 'pending',
        entryTime = DateTime.parse(m['entry_time'] as String),
        evalTime = DateTime.parse(m['eval_time'] as String),
        entryPrice = (m['entry_price'] as num).toDouble(),
        evalPrice = (m['eval_price'] as num).toDouble(),
        pnl = (m['pnl_pcnt'] as num?)?.toDouble() ?? 0;

  String get clean => _clean(symbol);
  bool get bullish => sentiment == 'BULLISH';
  bool get pending => status == 'pending';
  bool get isWin => status == 'win';
  bool get isLoss => status == 'loss';
  String get ticker {
    final ex = symbol.split(':').first;
    return '${clean}${ex == 'BSE' ? '.BO' : '.NS'}';
  }
}

class _Day {
  final String date;
  final int total, wins, losses;
  final double? acc;
  final bool hasPending;
  _Day(Map<String, dynamic> m)
      : date = m['pick_date'] as String,
        total = (m['total_picks'] as num?)?.toInt() ?? 0,
        wins = (m['wins'] as num?)?.toInt() ?? 0,
        losses = (m['losses'] as num?)?.toInt() ?? 0,
        acc = (m['accuracy_pct'] as num?)?.toDouble(),
        hasPending = m['has_pending'] == true;
}

class _Candle {
  final DateTime t;
  final double o, h, l, c;
  _Candle(Map<String, dynamic> m)
      : t = DateTime.parse(m['candle_time'] as String),
        o = (m['open'] as num).toDouble(),
        h = (m['high'] as num).toDouble(),
        l = (m['low'] as num).toDouble(),
        c = (m['close'] as num).toDouble();
}

// ============================================================================
// PAGE
// ============================================================================
class AiPicksPortfolioSection extends StatefulWidget {
  const AiPicksPortfolioSection({super.key});
  @override
  State<AiPicksPortfolioSection> createState() =>
      _AiPicksPortfolioSectionState();
}

class _AiPicksPortfolioSectionState extends State<AiPicksPortfolioSection> {
  static const double _gap = 6;
  static const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  List<_Pick> _picks = [];
  List<_Day> _days = [];
  bool _loading = true, _error = false;
  String? _selected;
  Timer? _timer;
  bool _showAll = false;
  static const int _collapsedCount = 5;

  @override
  void initState() {
    super.initState();
    _load();
    _timer =
        Timer.periodic(const Duration(minutes: 2), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final db = Supabase.instance.client;
      final res = await Future.wait([
        db
            .from(_kPicksTable)
            .select()
            .order('pick_date', ascending: false)
            .order('entry_time', ascending: false)
            .limit(_kPicksLimit),
        db
            .from(_kAccuracyTable)
            .select()
            .order('pick_date', ascending: false)
            .limit(_kAccuracyDays),
      ]);
      final picks = (res[0] as List)
          .map((e) => _Pick(e as Map<String, dynamic>))
          .toList();
      final days = (res[1] as List)
          .map((e) => _Day(e as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
      if (!mounted) return;
      setState(() {
        _picks = picks;
        _days = days;
        _error = false;
        _loading = false;
        _selected ??= days.reversed.firstWhereOrNull((d) => d.total > 0)?.date;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  List<_Pick> get _dayPicks =>
      _picks.where((p) => p.pickDate == _selected).toList();
  _Day? get _dayMeta => _days.firstWhereOrNull((d) => d.date == _selected);

  // ---- calendar -----------------------------------------------------------
  List<List<DateTime>> _weeks() {
    if (_days.isEmpty) return [];
    var start = _parseDay(_days.first.date);
    start = start.subtract(Duration(days: start.weekday % 7));
    var end = _parseDay(_days.last.date);
    end = end.add(Duration(days: 6 - (end.weekday % 7)));
    final weeks = <List<DateTime>>[];
    var cur = start;
    while (!cur.isAfter(end)) {
      weeks.add(List.generate(7, (i) => cur.add(Duration(days: i))));
      cur = cur.add(const Duration(days: 7));
    }
    return weeks;
  }

  Color _cellColor(_P p, _Day? d) {
    if (d == null || d.total == 0) return p.empty;
    if (d.acc == null) return p.amber.withOpacity(0.55);
    if (d.acc! >= _kGreenThreshold) {
      return p.bull.withOpacity(0.45 +
          0.55 * ((d.acc! - _kGreenThreshold) / (100 - _kGreenThreshold)));
    }
    return p.bear.withOpacity(
        0.45 + 0.55 * ((_kGreenThreshold - d.acc!) / _kGreenThreshold));
  }

  Widget _heatmap(_P p) {
    final weeks = _weeks();
    final byDate = {for (final d in _days) d.date: d};
    final today = _key(_ist(DateTime.now()));
    final lastDate = _days.isEmpty ? null : _days.last.date;

    Widget pad(Widget child) => Expanded(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
              child: child),
        );

    return Column(children: [
      Row(children: [
        for (final w in _weekdays)
          pad(Center(
            child: Text(w.toUpperCase(),
                style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: p.muted)),
          )),
      ]),
      const SizedBox(height: 8),
      for (final week in weeks)
        Padding(
          padding: const EdgeInsets.only(bottom: _gap),
          child: Row(children: [
            for (final date in week)
              pad(AspectRatio(
                aspectRatio: 1,
                child:
                    _cellWidget(p, date, byDate[_key(date)], today, lastDate),
              )),
          ]),
        ),
    ]);
  }

  Widget _cellWidget(
      _P p, DateTime date, _Day? d, String today, String? lastDate) {
    final k = _key(date);
    final outOfRange = lastDate != null && k.compareTo(lastDate) > 0;
    final clickable = d != null && d.total > 0;
    final sel = _selected == k;
    final colored = clickable && !outOfRange;
    final textColor = colored ? Colors.white : p.muted;

    return GestureDetector(
      onTap: clickable
          ? () => setState(() {
                _selected = k;
                _showAll = false;
              })
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: outOfRange ? Colors.transparent : _cellColor(p, d),
          borderRadius: BorderRadius.circular(10),
          border: sel
              ? Border.all(color: p.title, width: 2)
              : (k == today ? Border.all(color: p.gold, width: 1.4) : null),
        ),
        child: Stack(children: [
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${date.day}',
                    style: TextStyle(
                        fontSize: 9.5,
                        color: textColor.withOpacity(colored ? 0.75 : 0.6))),
                const SizedBox(height: 1),
                Text(
                  !clickable
                      ? '·'
                      : (d!.acc == null ? '—' : '${d.acc!.round()}%'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: textColor),
                ),
              ]),
            ),
          ),
          if (d?.hasPending ?? false)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration:
                    BoxDecoration(color: p.amber, shape: BoxShape.circle),
                child: const Icon(Icons.local_fire_department_rounded,
                    size: 9, color: Colors.black87),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _legend(_P p) {
    Widget item(Widget leading, String label) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          leading,
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 10, color: p.muted)),
        ]);
    Widget box(Color c) => Container(
        width: 11,
        height: 11,
        decoration:
            BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)));

    return Wrap(spacing: 14, runSpacing: 6, children: [
      item(box(p.bull), '60%+ right'),
      item(box(p.bear), 'More wrong'),
      item(box(p.empty), 'Weekend / holiday'),
      item(Icon(Icons.local_fire_department_rounded, size: 12, color: p.amber),
          'Result pending'),
    ]);
  }

  Widget _stats(_P p) {
    final scored = _days.where((d) => d.acc != null).toList();
    final avg = scored.isEmpty
        ? 0
        : (scored.fold<double>(0, (s, d) => s + d.acc!) / scored.length)
            .round();
    final green = scored.where((d) => d.acc! >= _kGreenThreshold).length;
    Widget tile(String v, String l, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: p.empty, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(v,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: c)),
              const SizedBox(height: 2),
              Text(l.toUpperCase(),
                  style: TextStyle(
                      fontSize: 9.5, letterSpacing: 0.6, color: p.muted)),
            ]),
          ),
        );
    return Row(children: [
      tile('$avg%', 'Avg accuracy', p.title),
      const SizedBox(width: 8),
      tile('$green', 'Green days', p.bull),
      const SizedBox(width: 8),
      tile('${scored.length - green}', 'Red days', p.bear),
    ]);
  }

  // ---- build --------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final p = _P.of(context);
    Widget body;
    if (_loading) {
      body = SizedBox(
          height: 220,
          child: Center(
              child: CircularProgressIndicator(color: p.gold, strokeWidth: 2)));
    } else if (_error) {
      body = SizedBox(
        height: 120,
        child: Center(
          child: TextButton.icon(
            onPressed: _load,
            icon: Icon(Icons.refresh_rounded, color: p.gold, size: 16),
            label: Text("Couldn't load picks. Retry",
                style: TextStyle(color: p.gold)),
          ),
        ),
      );
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        _stats(p),
        const SizedBox(height: 14),
        _accuracyGraph(p), // <-- accuracy graph ABOVE calendar
        const SizedBox(height: 16),
        _heatmap(p),
        const SizedBox(height: 8),
        _legend(p),
        const SizedBox(height: 14),
        _dayPanel(p),
      ]);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 8))
        ],
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Small eyebrow label ----
            Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: p.indigo, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('AI PICKS PORTFOLIO',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: p.muted)),
            ]),
            const SizedBox(height: 10),

            // ---- Heading + subtitle + WhatsApp CTA ----
            // ---- Heading + WhatsApp CTA ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'See trending stocks, and why.',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: p.title,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _WhatsAppButton(
                  p: p,
                  onTap: _openSubscriptionPage,
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ---- Subtitle: full width ----
            SizedBox(
              width: double.infinity,
              child: Text(
                'Our AI scans the market every day and shows you what it picked — and how those picks played out.',
                style: TextStyle(fontSize: 12.5, color: p.sub, height: 1.4),
              ),
            ),

            const SizedBox(height: 12),

            body,
          ]),
    );
  }

  // ==========================================================================
  // ACCURACY GRAPH (mini bar chart + CTA button) — sits above the calendar.
  // No scorecard numbers, just the visual and the "view full accuracy" link.
  // ==========================================================================
  Widget _accuracyGraph(_P p) {
    final scored = _days.where((d) => d.acc != null).toList();
    if (scored.isEmpty) return const SizedBox.shrink();

    // Overall accuracy across the window (used only to tint the header dot).
    final totalWins = scored.fold<int>(0, (s, d) => s + d.wins);
    final totalLosses = scored.fold<int>(0, (s, d) => s + d.losses);
    final totalScored = totalWins + totalLosses;
    final overallAcc = totalScored == 0 ? 0.0 : (totalWins / totalScored) * 100;
    final headerColor = overallAcc >= _kGreenThreshold ? p.bull : p.bear;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.empty,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header: title on left, tiny overall % chip on right ----
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: headerColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                'DAILY ACCURACY',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: p.muted,
                ),
              ),
              const Spacer(),
              Text(
                '${overallAcc.round()}% overall',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: headerColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ---- Bars ----
          SizedBox(
            height: 52,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < scored.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(child: _MiniBar(p: p, day: scored[i])),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),

          // ---- Axis labels ----
          Row(
            children: [
              Text(scored.first.date.substring(5),
                  style: TextStyle(fontSize: 9, color: p.muted)),
              const Spacer(),
              Text('Today', style: TextStyle(fontSize: 9, color: p.muted)),
            ],
          ),
          const SizedBox(height: 12),

          // ---- "View full accuracy" button ----
          SizedBox(
            width: double.infinity,
            height: 40,
            child: Material(
              color: p.indigo.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _openAccuracyPage,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.indigo.withOpacity(0.35)),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.insights_rounded, size: 15, color: p.indigo),
                      const SizedBox(width: 6),
                      Text(
                        'View full accuracy',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: p.indigo,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 14, color: p.indigo),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayPanel(_P p) {
    final picks = _dayPicks;
    final meta = _dayMeta;
    final label = _selected == null
        ? '—'
        : DateFormat('EEEE, d MMM').format(_parseDay(_selected!));
    final shown = _showAll ? picks : picks.take(_collapsedCount).toList();
    final hidden = picks.length - shown.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: p.empty,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: p.title)),
                      const SizedBox(height: 2),
                      Text(
                          '${picks.length} stock${picks.length == 1 ? '' : 's'} flagged · tap one for the chart',
                          style: TextStyle(fontSize: 11, color: p.muted)),
                    ]),
              ),
              if (meta?.acc != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (meta!.acc! >= _kGreenThreshold ? p.bull : p.bear)
                        .withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${meta.acc!.round()}%',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color:
                              meta.acc! >= _kGreenThreshold ? p.bull : p.bear)),
                ),
            ]),
            const SizedBox(height: 4),
            if (picks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                    child: Text('No picks for this day',
                        style: TextStyle(color: p.muted, fontSize: 12.5))),
              )
            else
              for (int i = 0; i < shown.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.border),
                _PickRow(
                    p: p, pick: shown[i], onTap: () => _openChart(shown[i])),
              ],
            if (picks.length > _collapsedCount)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll ? 'Show less' : 'Show $hidden more',
                      style: TextStyle(
                          color: p.gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5)),
                ),
              ),
            const SizedBox(height: 4),
            Text(
                'AI-picked stocks are for informational purposes only, not investment advice.',
                style: TextStyle(fontSize: 10, color: p.muted)),
          ]),
    );
  }

  void _openChart(_Pick pick) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChartSheet(p: _P.of(context), pick: pick),
    );
  }

  /// Opens the full AI-picks accuracy / backtest page.
  void _openAccuracyPage() {
    final scored = _days.where((d) => d.acc != null).toList();
    final avgAccuracy = scored.isEmpty
        ? 0.0
        : scored.fold<double>(0, (s, d) => s + d.acc!) / scored.length;

    Get.toNamed(
      _kRouteAccuracy,
      arguments: {
        'source': 'ai_picks_portfolio',
        'days': _kAccuracyDays,
        'avgAccuracy': avgAccuracy,
      },
    );
  }

  /// Opens the subscription page (WhatsApp alerts signup).
  /// Adjust the route / page to match your app's navigation setup.
  void _openSubscriptionPage() {
    // ---- Option A: named route via GetX ----
    Get.toNamed('/subscription-razorpay',
        arguments: {'source': 'ai_picks_whatsapp'});

    // ---- Option B: direct page push ----
    // Get.to(() => const SubscriptionPage());

    // ---- Option C: open an external URL ----
    // final uri = Uri.parse('https://optionxi.com/subscription?src=ai_picks');
    // launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

// ============================================================================
// MINI BAR (daily accuracy bar for the graph above the calendar)
// ============================================================================
class _MiniBar extends StatelessWidget {
  final _P p;
  final _Day day;
  const _MiniBar({required this.p, required this.day});

  @override
  Widget build(BuildContext context) {
    final acc = day.acc ?? 0;
    final isGreen = acc >= _kGreenThreshold;
    final color = isGreen ? p.bull : p.bear;
    final heightFactor = (acc / 100).clamp(0.1, 1.0);

    return Tooltip(
      message: '${day.date}\n${acc.round()}% · ${day.wins}W / ${day.losses}L',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    height: constraints.maxHeight * heightFactor,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${acc.round()}',
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PICK ROW
// ============================================================================
class _PickRow extends StatelessWidget {
  final _P p;
  final _Pick pick;
  final VoidCallback onTap;
  const _PickRow({required this.p, required this.pick, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final up = pick.pnl >= 0;
    final gainColor = up ? p.bull : p.bear;
    final bullish = pick.bullish;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          // ---- stock logo (with fallback icon) ----
          _StockLogo(
            symbol: pick.clean,
            bullish: bullish,
            p: p,
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pick.clean,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: p.title)),
              const SizedBox(height: 2),
              Text('${bullish ? 'Long' : 'Short'} · ${_time(pick.entryTime)}',
                  style: TextStyle(fontSize: 11, color: p.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${up ? '+' : ''}${pick.pnl.toStringAsFixed(2)}%',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: gainColor)),
            const SizedBox(height: 3),
            _StatusBadge(pick: pick, p: p),
          ]),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
        ]),
      ),
    );
  }
}

// ============================================================================
// STOCK LOGO WIDGET  (image with fallback to trending icon)
// ============================================================================
class _StockLogo extends StatelessWidget {
  final String symbol;
  final bool bullish;
  final _P p;
  const _StockLogo({
    required this.symbol,
    required this.bullish,
    required this.p,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = bullish ? p.bull : p.bear;
    final fallback = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        bullish ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        size: 18,
        color: iconColor,
      ),
    );

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: p.empty,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          '$_kStockLogoBaseUrl/$symbol.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return fallback;
          },
        ),
      ),
    );
  }
}

// ============================================================================
// STATUS BADGE — tick / cross / live (with icon + label like Next.js)
// ============================================================================
class _StatusBadge extends StatelessWidget {
  final _Pick pick;
  final _P p;
  const _StatusBadge({required this.pick, required this.p});

  @override
  Widget build(BuildContext context) {
    if (pick.pending) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.schedule_rounded, size: 11, color: p.amber),
        const SizedBox(width: 3),
        Text('Live',
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: p.amber)),
      ]);
    }

    final isWin = pick.isWin;
    final color = isWin ? p.bull : p.bear;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isWin ? Icons.check_rounded : Icons.close_rounded,
          size: 11,
          color: color,
        ),
      ),
      const SizedBox(width: 4),
      Text(isWin ? 'Right' : 'Wrong',
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

// ============================================================================
// WHATSAPP CTA — opens the subscription page
// ============================================================================
class _WhatsAppButton extends StatelessWidget {
  final _P p;
  final VoidCallback onTap;
  const _WhatsAppButton({required this.p, required this.onTap});

  static const _waGreen = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _waGreen.withOpacity(0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _waGreen.withOpacity(0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // WhatsApp glyph (drawn with a CustomPainter so no extra assets)
            SizedBox(
              width: 16,
              height: 16,
              child: CustomPaint(painter: _WhatsAppPainter(color: _waGreen)),
            ),
            const SizedBox(width: 6),
            const Text(
              'Get alerts',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _waGreen,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _WhatsAppPainter extends CustomPainter {
  final Color color;
  _WhatsAppPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Outer speech bubble circle
    final path = Path()
      ..addOval(
          Rect.fromCircle(center: Offset(12 * s, 12 * s), radius: 10.5 * s));
    canvas.drawPath(path, paint);

    // Inner phone glyph in white (cut-out feel)
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round;
    final inner = Path()
      ..moveTo(9.2 * s, 8.4 * s)
      ..quadraticBezierTo(9.0 * s, 12.0 * s, 14.5 * s, 15.4 * s)
      ..lineTo(15.8 * s, 14.2 * s)
      ..quadraticBezierTo(16.1 * s, 13.9 * s, 15.8 * s, 13.6 * s)
      ..lineTo(14.6 * s, 12.6 * s)
      ..quadraticBezierTo(14.3 * s, 12.4 * s, 14.0 * s, 12.6 * s)
      ..lineTo(13.0 * s, 13.4 * s)
      ..quadraticBezierTo(11.6 * s, 12.4 * s, 11.0 * s, 10.9 * s)
      ..lineTo(11.9 * s, 10.1 * s)
      ..quadraticBezierTo(12.1 * s, 9.8 * s, 11.9 * s, 9.5 * s)
      ..lineTo(10.9 * s, 8.3 * s)
      ..quadraticBezierTo(10.6 * s, 8.0 * s, 10.3 * s, 8.2 * s)
      ..close();
    canvas.drawPath(inner, white);
  }

  @override
  bool shouldRepaint(covariant _WhatsAppPainter old) => old.color != color;
}

// ============================================================================
// CHART SHEET
// ============================================================================
class _ChartSheet extends StatefulWidget {
  final _P p;
  final _Pick pick;
  const _ChartSheet({required this.p, required this.pick});
  @override
  State<_ChartSheet> createState() => _ChartSheetState();
}

class _ChartSheetState extends State<_ChartSheet> {
  List<_Candle> _candles = [];
  bool _loading = true, _error = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final rows = await Supabase.instance.client
          .from(_kCandlesTable)
          .select('candle_time,open,high,low,close,volume')
          .eq('ticker', widget.pick.ticker)
          .eq('trading_day', widget.pick.pickDate)
          .order('candle_time', ascending: true);
      if (!mounted) return;
      setState(() {
        _candles = (rows as List)
            .map((e) => _Candle(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p, pick = widget.pick;
    final profit = pick.pnl >= 0;
    final c = profit ? p.bull : p.bear;

    Widget stat(String l, String v, [Color? col]) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: p.empty, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(l,
                  style: TextStyle(
                      fontSize: 9.5, color: p.muted, letterSpacing: 0.5)),
              const SizedBox(height: 3),
              Text(v,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: col ?? p.title)),
            ]),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: p.border, borderRadius: BorderRadius.circular(2))),
            ),
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          DateFormat('EEEE, d MMM')
                              .format(_parseDay(pick.pickDate))
                              .toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1,
                              color: p.muted,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Text(pick.clean,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: p.title)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: (pick.bullish ? p.bull : p.bear)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(pick.bullish ? 'LONG' : 'SHORT',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: pick.bullish ? p.bull : p.bear)),
                        ),
                      ]),
                    ]),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: p.muted)),
            ]),
            const SizedBox(height: 12),
            Container(
              height: 230,
              width: double.infinity,
              decoration: BoxDecoration(
                  color: p.empty.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.border)),
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: p.gold, strokeWidth: 2))
                  : (_error || _candles.isEmpty)
                      ? Center(
                          child: Text(
                              _error
                                  ? "Couldn't load candles"
                                  : 'No candle data for this day yet',
                              style: TextStyle(fontSize: 12, color: p.muted)))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: CustomPaint(
                              painter:
                                  _CandlePainter(_candles, pick, p, profit)),
                        ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              stat('ENTRY · ${_time(pick.entryTime)}',
                  '₹${pick.entryPrice.toStringAsFixed(2)}'),
              const SizedBox(width: 8),
              stat('EXIT · ${_time(pick.evalTime)}',
                  '₹${pick.evalPrice.toStringAsFixed(2)}'),
              const SizedBox(width: 8),
              stat("IF FOLLOWED",
                  '${profit ? '+' : ''}${pick.pnl.toStringAsFixed(2)}%', c),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.gold,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Get.toNamed(_routeForStock(pick.symbol),
                      arguments: {'date': pick.pickDate});
                },
                icon: const Icon(Icons.north_east_rounded, size: 16),
                label: const Text('View full details',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                  'For education only — shows how the pick played out, not a recommendation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: p.muted)),
            ),
          ]),
    );
  }
}

class _CandlePainter extends CustomPainter {
  final List<_Candle> candles;
  final _Pick pick;
  final _P p;
  final bool profit;
  _CandlePainter(this.candles, this.pick, this.p, this.profit);

  static const double padL = 40, padR = 10, padT = 14, padB = 22;

  void _text(Canvas c, String s, Offset o,
      {Color? color, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s, style: TextStyle(fontSize: 9, color: color ?? p.muted)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center ? Offset(o.dx - tp.width / 2, o.dy) : o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tMin = candles.first.t.millisecondsSinceEpoch.toDouble();
    final tMax = candles.last.t.millisecondsSinceEpoch.toDouble();
    final tSpan = (tMax - tMin).clamp(1, double.infinity);
    var lo = candles.map((e) => e.l).reduce((a, b) => a < b ? a : b);
    var hi = candles.map((e) => e.h).reduce((a, b) => a > b ? a : b);
    lo = lo < pick.entryPrice ? lo : pick.entryPrice;
    hi = hi > pick.entryPrice ? hi : pick.entryPrice;
    final pad = (hi - lo) * 0.08;
    lo -= pad == 0 ? 1 : pad;
    hi += pad == 0 ? 1 : pad;

    final w = size.width - padL - padR, h = size.height - padT - padB;
    double x(num t) => padL + ((t - tMin) / tSpan) * w;
    double y(double v) => padT + h - ((v - lo) / (hi - lo)) * h;

    // grid
    final grid = Paint()
      ..color = p.border
      ..strokeWidth = 0.6;
    for (final v in [hi, (hi + lo) / 2, lo]) {
      canvas.drawLine(
          Offset(padL, y(v)), Offset(size.width - padR, y(v)), grid);
      _text(canvas, v.toStringAsFixed(1), Offset(3, y(v) - 5));
    }

    final entryX = x(pick.entryTime.millisecondsSinceEpoch);
    final evalX = x(pick.evalTime.millisecondsSinceEpoch);
    final l = entryX < evalX ? entryX : evalX,
        r = entryX < evalX ? evalX : entryX;
    canvas.drawRect(Rect.fromLTRB(l, padT, r, padT + h),
        Paint()..color = (profit ? p.bull : p.bear).withOpacity(0.10));

    // candles
    final bw = ((w / candles.length) * 0.6).clamp(2.0, 9.0);
    for (final k in candles) {
      final cx = x(k.t.millisecondsSinceEpoch);
      final col = k.c >= k.o ? p.bull : p.bear;
      final paint = Paint()
        ..color = col
        ..strokeWidth = 1;
      canvas.drawLine(Offset(cx, y(k.h)), Offset(cx, y(k.l)), paint);
      final top = y(k.c > k.o ? k.c : k.o), bot = y(k.c > k.o ? k.o : k.c);
      canvas.drawRect(
          Rect.fromLTRB(
              cx - bw / 2, top, cx + bw / 2, bot < top + 1 ? top + 1 : bot),
          paint);
    }

    // entry / exit markers
    final dash = Paint()
      ..color = p.muted
      ..strokeWidth = 1;
    for (final xx in [entryX, evalX]) {
      for (double yy = padT; yy < padT + h; yy += 6) {
        canvas.drawLine(Offset(xx, yy), Offset(xx, yy + 3), dash);
      }
    }
    canvas.drawCircle(
        Offset(entryX, y(pick.entryPrice)), 4.5, Paint()..color = p.title);
    canvas.drawCircle(Offset(evalX, y(pick.evalPrice)), 4.5,
        Paint()..color = profit ? p.bull : p.bear);
    _text(canvas, 'ENTRY', Offset(entryX + 4, padT + 2), color: p.sub);
    _text(canvas, 'EXIT', Offset(evalX + 4, padT + 13), color: p.sub);

    // time labels
    for (final t in [
      candles.first.t,
      pick.entryTime,
      pick.evalTime,
      candles.last.t
    ]) {
      final cx = x(t.millisecondsSinceEpoch)
          .clamp(padL + 14, size.width - padR - 14)
          .toDouble();
      _text(canvas, _time(t), Offset(cx, size.height - 14), center: true);
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.candles != candles || old.pick != pick;
}
