import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

// ============================================================================
// PALETTE
// ============================================================================

class _P {
  final Color surface, border, shadow, titleText, subText, mutedText;
  final Color accent, bull, bear, neutral, sheetBg, sheetHandle;

  const _P({
    required this.surface,
    required this.border,
    required this.shadow,
    required this.titleText,
    required this.subText,
    required this.mutedText,
    required this.accent,
    required this.bull,
    required this.bear,
    required this.neutral,
    required this.sheetBg,
    required this.sheetHandle,
  });

  factory _P.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const _P(
        surface: Color(0xFF151820),
        border: Color(0xFF252B3A),
        shadow: Color(0x66000000),
        titleText: Color(0xFFEDF0F7),
        subText: Color(0xFF9AA1B2),
        mutedText: Color(0xFF828A9B),
        accent: Color(0xFF6366F1),
        bull: Color(0xFF3B82F6),
        bear: Color(0xFFF43F5E),
        neutral: Color(0xFF14B8A6),
        sheetBg: Color(0xFF151820),
        sheetHandle: Color(0xFF3A4152),
      );
    }
    return const _P(
      surface: Color(0xFFFFFFFF),
      border: Color(0xFFE2E5EE),
      shadow: Color(0x1A1A1A2E),
      titleText: Color(0xFF111827),
      subText: Color(0xFF565B6B),
      mutedText: Color(0xFF6B7280),
      accent: Color(0xFF6366F1),
      bull: Color(0xFF3B82F6),
      bear: Color(0xFFF43F5E),
      neutral: Color(0xFF14B8A6),
      sheetBg: Color(0xFFFFFFFF),
      sheetHandle: Color(0xFFE2E5EE),
    );
  }
}

// ============================================================================
// MOOD
// ============================================================================

class _Mood {
  final String headline, plain, voteWord;
  final IconData icon;
  final Color Function(_P p) color;
  const _Mood({
    required this.headline,
    required this.plain,
    required this.voteWord,
    required this.icon,
    required this.color,
  });

  static const up = _Mood(
    headline: 'Likely going up',
    plain: 'Buyers are in control',
    voteWord: 'up',
    icon: Icons.trending_up_rounded,
    color: _bull,
  );
  static const down = _Mood(
    headline: 'Likely going down',
    plain: 'Sellers are in control',
    voteWord: 'down',
    icon: Icons.trending_down_rounded,
    color: _bear,
  );
  static const flat = _Mood(
    headline: 'Undecided',
    plain: 'No clear winner yet',
    voteWord: 'unsure',
    icon: Icons.trending_flat_rounded,
    color: _neutral,
  );

  static Color _bull(_P p) => p.bull;
  static Color _bear(_P p) => p.bear;
  static Color _neutral(_P p) => p.neutral;

  static _Mood of(String type) =>
      type == 'Bull' ? up : (type == 'Bear' ? down : flat);
}

String _trendWord(String t) {
  final s = t.toLowerCase();
  if (s.contains('bull')) return 'Up';
  if (s.contains('bear')) return 'Down';
  return 'Sideways';
}

// Color _trendColor(_P p, String t) {
//   final s = t.toLowerCase();
//   if (s.contains('bull')) return p.bull;
//   if (s.contains('bear')) return p.bear;
//   return p.neutral;
// }

IconData _trendIcon(String t) {
  final s = t.toLowerCase();
  if (s.contains('bull')) return Icons.north_east_rounded;
  if (s.contains('bear')) return Icons.south_east_rounded;
  return Icons.east_rounded;
}

String _confidence(double p) => p >= 70
    ? 'High confidence'
    : (p >= 60 ? 'Medium confidence' : 'Low confidence');

// ============================================================================
// CONFIG
// ============================================================================

const double _kMinEntryProbability = 72.0;

const int _kSignalWindowStartHour = 9;
const int _kSignalWindowStartMinute = 20;
const int _kSignalWindowEndHour = 15;
const int _kSignalWindowEndMinute = 20;

const int _kMaxLookbackDays = 7;

// ============================================================================
// STATE MODEL
// ============================================================================

enum _Status { loading, hasData, noData, error }

enum _MarketPhase { beforeOpen, open, afterClose, weekend }

/// Latest atlas_output row, any probability, any entry flag.
class _Current {
  final DateTime ts;
  final String type;
  final double probability;
  final String shortterm;
  final String longterm;
  final bool upBreakout;
  final bool lowBreakout;
  final int positive, neutral, negative;
  const _Current({
    required this.ts,
    required this.type,
    required this.probability,
    required this.shortterm,
    required this.longterm,
    required this.upBreakout,
    required this.lowBreakout,
    required this.positive,
    required this.neutral,
    required this.negative,
  });

  int get total => positive + neutral + negative;
  _Mood get mood => _Mood.of(type);

  String get summary {
    if (total == 0) return mood.plain;
    final n = type == 'Bull' ? positive : (type == 'Bear' ? negative : neutral);
    return '$n of $total market gauges say ${mood.voteWord}.';
  }
}

/// Last first-entry signal that passed the probability + time-window filter.
class _QualifyingSignal {
  final DateTime ts;
  final bool isBull;
  const _QualifyingSignal({required this.ts, required this.isBull});
}

// ============================================================================
// DATE HELPERS
// ============================================================================

DateTime _stripTime(DateTime d) => DateTime(d.year, d.month, d.day);

bool _isWeekendDate(DateTime d) =>
    d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

DateTime _latestWeekdayOnOrBefore(DateTime d) {
  var x = _stripTime(d);
  while (_isWeekendDate(x)) {
    x = x.subtract(const Duration(days: 1));
  }
  return x;
}

DateTime _prevWeekday(DateTime d) {
  var x = d.subtract(const Duration(days: 1));
  while (_isWeekendDate(x)) {
    x = x.subtract(const Duration(days: 1));
  }
  return x;
}

bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _withinSignalWindow(DateTime local) {
  final start = DateTime(local.year, local.month, local.day,
      _kSignalWindowStartHour, _kSignalWindowStartMinute);
  final end = DateTime(local.year, local.month, local.day,
      _kSignalWindowEndHour, _kSignalWindowEndMinute);
  return !local.isBefore(start) && !local.isAfter(end);
}

// ============================================================================
// PUBLIC WIDGET
// ============================================================================

class MarketSentimentSection_Index extends StatefulWidget {
  final EdgeInsetsGeometry margin;

  const MarketSentimentSection_Index({
    super.key,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  State<MarketSentimentSection_Index> createState() =>
      _MarketSentimentSection_IndexState();
}

class _MarketSentimentSection_IndexState
    extends State<MarketSentimentSection_Index> {
  _Status _status = _Status.loading;
  _Current? _current;
  _QualifyingSignal? _lastEntry;
  bool _lastEntryIsToday = true;
  DateTime? _lastEntryDate;
  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _minuteTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    super.dispose();
  }

  _MarketPhase get _phase {
    final n = DateTime.now();
    if (_isWeekendDate(n)) return _MarketPhase.weekend;
    final open = DateTime(n.year, n.month, n.day, 9, 15);
    final close = DateTime(n.year, n.month, n.day, 15, 30);
    if (n.isBefore(open)) return _MarketPhase.beforeOpen;
    if (n.isAfter(close)) return _MarketPhase.afterClose;
    return _MarketPhase.open;
  }

  bool get _isLive => _phase == _MarketPhase.open;

  // ── data ────────────────────────────────────────────────────────────────

  /// Latest row, no filters: this is the "current" trend.
  Future<_Current?> _fetchCurrent() async {
    final rows = await Supabase.instance.client
        .from('atlas_output')
        .select(
            'created_at,probability,type,upbreakout,lowbreakout,shortterm,longterm,"Postive Indicators","Neutral Indicators","Negative Indicators"')
        .order('created_at', ascending: false)
        .limit(1);

    final list = rows as List;
    if (list.isEmpty) return null;
    final m = list.first as Map<String, dynamic>;
    return _Current(
      ts: DateTime.parse(m['created_at'] as String).toLocal(),
      type: (m['type'] as String?) ?? '',
      probability: ((m['probability'] as num?) ?? 0).toDouble(),
      shortterm: (m['shortterm'] as String?) ?? '',
      longterm: (m['longterm'] as String?) ?? '',
      upBreakout: m['upbreakout'] == true,
      lowBreakout: m['lowbreakout'] == true,
      positive: ((m['Postive Indicators'] as num?) ?? 0).toInt(),
      neutral: ((m['Neutral Indicators'] as num?) ?? 0).toInt(),
      negative: ((m['Negative Indicators'] as num?) ?? 0).toInt(),
    );
  }

  /// NOTE: column names with spaces/mixed case must be double-quoted inside
  /// the PostgREST select string.
  Future<_QualifyingSignal?> _fetchFirstQualifyingSignal(DateTime date) async {
    final startUtc = DateTime.utc(date.year, date.month, date.day, 0, 0, 0)
        .subtract(const Duration(hours: 5, minutes: 30));
    final endUtc = DateTime.utc(date.year, date.month, date.day, 23, 59, 59)
        .subtract(const Duration(hours: 5, minutes: 30));

    final rows = await Supabase.instance.client
        .from('atlas_output')
        .select('created_at,probability,upbreakout,type')
        .eq('entry', true)
        .gte('probability', _kMinEntryProbability)
        .gte('created_at', startUtc.toIso8601String())
        .lte('created_at', endUtc.toIso8601String())
        .order('created_at', ascending: true);

    for (final row in (rows as List)) {
      final m = row as Map<String, dynamic>;
      final ts = DateTime.parse(m['created_at'] as String).toLocal();
      if (!_withinSignalWindow(ts)) continue;
      final isBull = (m['type'] == 'Bull') || (m['upbreakout'] == true);
      return _QualifyingSignal(ts: ts, isBull: isBull);
    }
    return null;
  }

  Future<void> _refresh() async {
    // Only show skeleton on first load; silent refresh afterwards (no flicker).
    if (mounted && _current == null) setState(() => _status = _Status.loading);

    try {
      final current = await _fetchCurrent();
      if (current == null) {
        _current = null;
        if (mounted) setState(() => _status = _Status.noData);
        return;
      }

      DateTime day = _latestWeekdayOnOrBefore(DateTime.now());
      bool isToday = _isSameDate(day, DateTime.now());
      _QualifyingSignal? found = await _fetchFirstQualifyingSignal(day);

      int guard = 0;
      while (found == null && guard < _kMaxLookbackDays) {
        day = _prevWeekday(day);
        isToday = false;
        found = await _fetchFirstQualifyingSignal(day);
        guard++;
      }

      _current = current;
      _lastEntry = found;
      _lastEntryIsToday = isToday;
      _lastEntryDate = found == null ? null : day;

      if (mounted) setState(() => _status = _Status.hasData);
    } catch (e) {
      debugPrint('market sentiment fetch error: $e');
      if (mounted && _current == null) setState(() => _status = _Status.error);
    }
  }

  // ── nav ─────────────────────────────────────────────────────────────────

  void _goChart() => Get.toNamed('/market-sentiments-chart');

  void _openChart() {
    Navigator.of(context).maybePop();
    _goChart();
  }

  void _openAccuracy() {
    Navigator.of(context).maybePop();
    Get.toNamed('/backtest/nifty');
  }

  void _openActionsSheet() {
    final p = _P.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ActionsSheet(
        p: p,
        onChart: _openChart,
        onAccuracy: _openAccuracy,
      ),
    );
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = _P.of(context);
    final canOpenSheet =
        _status == _Status.hasData || _status == _Status.noData;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: canOpenSheet ? _openActionsSheet : null,
        child: Ink(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: p.shadow,
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _buildBody(p),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(_P p) {
    switch (_status) {
      case _Status.loading:
        return _SkeletonHero(key: const ValueKey('loading'), p: p);
      case _Status.error:
        return _ErrorInline(
            key: const ValueKey('error'), p: p, onRetry: _refresh);
      case _Status.noData:
        return _NoSignalInline(key: const ValueKey('noData'), p: p);
      case _Status.hasData:
        return _Hero(
          key: const ValueKey('hasData'),
          p: p,
          cur: _current!,
          lastEntry: _lastEntry,
          lastEntryIsToday: _lastEntryIsToday,
          lastEntryDate: _lastEntryDate,
          live: _isLive,
        );
    }
  }
}

// ============================================================================
// HERO — current read (latest row) + trend chips + last fresh move
// ============================================================================

class _Hero extends StatelessWidget {
  final _P p;
  final _Current cur;
  final _QualifyingSignal? lastEntry;
  final bool lastEntryIsToday;
  final DateTime? lastEntryDate;
  final bool live;

  const _Hero({
    super.key,
    required this.p,
    required this.cur,
    required this.lastEntry,
    required this.lastEntryIsToday,
    required this.lastEntryDate,
    required this.live,
  });

  @override
  Widget build(BuildContext context) {
    final m = cur.mood;
    final dirColor = m.color(p);
    final c2 = Color.lerp(dirColor, p.accent, 0.55)!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [dirColor, c2],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: dirColor.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live/updated label + time
          Row(
            children: [
              if (live) ...[
                const _PulsingDot(color: Color(0xFF10B981), pulse: true),
                const SizedBox(width: 6),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  'Latest read, ${timeago.format(cur.ts)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(m.icon, color: Colors.white, size: 26),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            m.headline,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${m.plain}. ${cur.summary}',
                      style: const TextStyle(
                          fontSize: 13, height: 1.35, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  _Ring(value: cur.probability, size: 60),
                  const SizedBox(height: 4),
                  Text(
                    _confidence(cur.probability),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
          if (cur.total > 0) ...[
            const SizedBox(height: 12),
            _VoteBar(pos: cur.positive, neut: cur.neutral, neg: cur.negative),
          ],
          const SizedBox(height: 12),
          // Current trend row
          Row(
            children: [
              Expanded(
                child:
                    _TrendTile(label: 'Short-term', trend: cur.shortterm, p: p),
              ),
              const SizedBox(width: 8),
              Expanded(
                child:
                    _TrendTile(label: 'Long-term', trend: cur.longterm, p: p),
              ),
            ],
          ),
          if (cur.upBreakout || cur.lowBreakout) ...[
            const SizedBox(height: 8),
            _GlassChip(
              icon: cur.upBreakout ? Icons.north_rounded : Icons.south_rounded,
              label: cur.upBreakout
                  ? 'Broke above recent high'
                  : 'Broke below recent low',
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _lastEntryText(),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.7), size: 20),
            ],
          ),
        ],
      ),
    );
  }

  String _lastEntryText() {
    final e = lastEntry;
    if (e == null) return 'No strong fresh move in the last few trading days';
    final day = lastEntryIsToday
        ? 'Today'
        : DateFormat('EEE, d MMM').format(lastEntryDate!);
    final dir = e.isBull ? 'up' : 'down';
    return 'Last strong move: $dir · $day, ${DateFormat('h:mm a').format(e.ts)}';
  }
}

class _TrendTile extends StatelessWidget {
  final String label;
  final String trend;
  final _P p;
  const _TrendTile({required this.label, required this.trend, required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(_trendIcon(trend), size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70)),
                Text(_trendWord(trend),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _GlassChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double value; // 0..100
  final double size;
  const _Ring({required this.value, this.size = 60});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: (value / 100).clamp(0.0, 1.0),
                strokeWidth: size * 0.11,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            Text(
              '${value.round()}%',
              style: TextStyle(
                fontSize: size * 0.26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
}

class _VoteBar extends StatelessWidget {
  final int pos, neut, neg;
  const _VoteBar({required this.pos, required this.neut, required this.neg});

  @override
  Widget build(BuildContext context) {
    if (pos + neut + neg == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(children: [
          if (pos > 0)
            Expanded(
                flex: pos,
                child: Container(color: Colors.white.withValues(alpha: 0.95))),
          if (neut > 0)
            Expanded(
                flex: neut,
                child: Container(color: Colors.white.withValues(alpha: 0.45))),
          if (neg > 0)
            Expanded(
                flex: neg,
                child: Container(color: Colors.white.withValues(alpha: 0.2))),
        ]),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _PulsingDot({required this.color, this.pulse = true});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
    );
    if (!widget.pulse) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_c),
      child: dot,
    );
  }
}

// ============================================================================
// SKELETON (loading)
// ============================================================================

class _SkeletonHero extends StatefulWidget {
  final _P p;
  const _SkeletonHero({super.key, required this.p});

  @override
  State<_SkeletonHero> createState() => _SkeletonHeroState();
}

class _SkeletonHeroState extends State<_SkeletonHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _bar(double width, double height, {double radius = 6}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: widget.p.border,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(_c),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.p.border.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _bar(110, 10),
            const SizedBox(height: 12),
            Row(
              children: [
                _bar(26, 26, radius: 8),
                const SizedBox(width: 10),
                _bar(150, 18),
                const Spacer(),
                _bar(52, 52, radius: 26),
              ],
            ),
            const SizedBox(height: 12),
            _bar(double.infinity, 6),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _bar(double.infinity, 40, radius: 12)),
                const SizedBox(width: 8),
                Expanded(child: _bar(double.infinity, 40, radius: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// NO DATA (inline)
// ============================================================================

class _NoSignalInline extends StatelessWidget {
  final _P p;
  const _NoSignalInline({super.key, required this.p});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.visibility_outlined, size: 18, color: p.mutedText),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No reading yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: p.titleText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'New reads appear here as soon as Atlas produces them.',
                style: TextStyle(fontSize: 12, color: p.mutedText),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: p.mutedText, size: 20),
      ],
    );
  }
}

// ============================================================================
// ERROR (inline)
// ============================================================================

class _ErrorInline extends StatelessWidget {
  final _P p;
  final VoidCallback onRetry;
  const _ErrorInline({super.key, required this.p, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 18, color: p.bear),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "Couldn't load signal data",
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: p.titleText),
          ),
        ),
        GestureDetector(
          onTap: onRetry,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, size: 14, color: p.accent),
              const SizedBox(width: 4),
              Text('Retry',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.accent)),
            ],
          ),
        ),
      ],
    );
  }
}
// ============================================================================
// ACTIONS SHEET — info is calm & muted, the two CTAs are the focus
// Drop-in replacement: same constructor (p, onChart, onAccuracy).
// Replace the old _GuideRow, _ActionsSheet and _SheetButton classes with this.
// Needs: import 'dart:math' as math;  (add at top of file)
// ============================================================================

class _ActionsSheet extends StatefulWidget {
  final _P p;
  final VoidCallback onChart;
  final VoidCallback onAccuracy;
  const _ActionsSheet({
    required this.p,
    required this.onChart,
    required this.onAccuracy,
  });

  @override
  State<_ActionsSheet> createState() => _ActionsSheetState();
}

class _ActionsSheetState extends State<_ActionsSheet>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// Staggered fade + slide-up for a section.
  Widget _stagger(double start, double end, Widget child) {
    final anim = CurvedAnimation(
      parent: _enter,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * 14),
          child: c,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.9;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 14 + bottomInset),
      decoration: BoxDecoration(
        color: p.sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: p.sheetHandle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Scrollable calm info area (safe on small screens)
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _stagger(
                    0.0,
                    0.35,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Market Sentiments',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: p.titleText,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Is the market mood positive or negative right now?',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: p.subText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Legend (muted)
                  _stagger(
                    0.1,
                    0.5,
                    Row(
                      children: [
                        Expanded(
                          child: _LegendChip(
                            p: p,
                            icon: Icons.trending_up_rounded,
                            label: 'Up',
                            hint: 'More buyers',
                            color: p.bull,
                            loop: _loop,
                            phase: 0.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _LegendChip(
                            p: p,
                            icon: Icons.trending_flat_rounded,
                            label: 'Unsure',
                            hint: 'No clear winner',
                            color: p.neutral,
                            loop: _loop,
                            phase: 0.33,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _LegendChip(
                            p: p,
                            icon: Icons.trending_down_rounded,
                            label: 'Down',
                            hint: 'More sellers',
                            color: p.bear,
                            loop: _loop,
                            phase: 0.66,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Tips (muted)
                  _stagger(
                    0.18,
                    0.6,
                    Column(
                      children: [
                        _TipRow(
                          p: p,
                          icon: Icons.how_to_vote_rounded,
                          bold: 'The bar:',
                          text:
                              'Many market signals each vote up, down or unsure.',
                        ),
                        const SizedBox(height: 8),
                        _TipRow(
                          p: p,
                          icon: Icons.schedule_rounded,
                          bold: 'Short vs long-term:',
                          text:
                              'Today\'s mood vs the bigger picture. If both agree, trust it more.',
                        ),
                        const SizedBox(height: 8),
                        _TipRow(
                          p: p,
                          icon: Icons.percent_rounded,
                          bold: 'The % ring:',
                          text: 'How sure we are. Higher means more confident.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // CTAs — the focus
          _stagger(
            0.25,
            0.8,
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _CtaCard(
                      p: p,
                      filled: true,
                      title: 'All signals',
                      subtitle: 'See every past prediction on the price chart',
                      buttonLabel: 'View chart',
                      buttonIcon: Icons.candlestick_chart_rounded,
                      onTap: widget.onChart,
                      visual: AnimatedBuilder(
                        animation: Listenable.merge([_enter, _loop]),
                        builder: (_, __) => CustomPaint(
                          painter: _SignalsPainter(
                            progress: Curves.easeInOutCubic.transform(
                              ((_enter.value - 0.25) / 0.6).clamp(0.0, 1.0),
                            ),
                            pulse: _loop.value,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CtaCard(
                      p: p,
                      filled: false,
                      title: 'Accuracy',
                      subtitle:
                          'How often our past predictions turned out right',
                      buttonLabel: 'See accuracy',
                      buttonIcon: Icons.insights_rounded,
                      onTap: widget.onAccuracy,
                      visual: AnimatedBuilder(
                        animation: Listenable.merge([_enter, _loop]),
                        builder: (_, __) => CustomPaint(
                          painter: _BarsPainter(
                            progress:
                                ((_enter.value - 0.3) / 0.65).clamp(0.0, 1.0),
                            pulse: _loop.value,
                            color: p.accent,
                            track: p.border,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Disclaimer (muted)
          _stagger(
            0.5,
            1.0,
            Text(
              'A guide, not investment advice. Markets can surprise, and past results don\'t promise future ones.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: p.mutedText.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Legend chip — muted container, only the icon carries color
// ----------------------------------------------------------------------------

class _LegendChip extends StatelessWidget {
  final _P p;
  final IconData icon;
  final String label;
  final String hint;
  final Color color;
  final Animation<double> loop;
  final double phase;
  const _LegendChip({
    required this.p,
    required this.icon,
    required this.label,
    required this.hint,
    required this.color,
    required this.loop,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: p.border.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: loop,
                builder: (_, __) {
                  final t = (loop.value + phase) % 1.0;
                  final s = 1.0 + 0.16 * math.sin(t * math.pi);
                  return Transform.scale(
                    scale: s,
                    child: Icon(icon, size: 20, color: color),
                  );
                },
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: p.titleText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: p.mutedText),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// One-line plain explainer: icon + short sentence (muted)
// ----------------------------------------------------------------------------

class _TipRow extends StatelessWidget {
  final _P p;
  final IconData icon;
  final String bold;
  final String text;
  const _TipRow({
    required this.p,
    required this.icon,
    required this.bold,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: p.mutedText),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$bold ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: p.subText,
                  ),
                ),
                TextSpan(text: text),
              ],
            ),
            style: TextStyle(fontSize: 13, height: 1.4, color: p.mutedText),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// CTA card: animated visual + title + subtitle + a real button
// ----------------------------------------------------------------------------

class _CtaCard extends StatefulWidget {
  final _P p;
  final bool filled;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final IconData buttonIcon;
  final Widget visual;
  final VoidCallback onTap;
  const _CtaCard({
    required this.p,
    required this.filled,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.visual,
    required this.onTap,
  });

  @override
  State<_CtaCard> createState() => _CtaCardState();
}

class _CtaCardState extends State<_CtaCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final f = widget.filled;
    final titleC = f ? Colors.white : p.titleText;
    final subC = f ? Colors.white.withValues(alpha: 0.85) : p.subText;

    // Button colors: white on the gradient card, solid accent on the light card
    final btnBg = f ? Colors.white : p.accent;
    final btnFg = f ? p.accent : Colors.white;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: f
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [p.accent, Color.lerp(p.accent, p.bull, 0.6)!],
                  )
                : null,
            color: f ? null : p.surface,
            borderRadius: BorderRadius.circular(20),
            border:
                f ? null : Border.all(color: p.accent.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: p.accent.withValues(alpha: f ? 0.30 : 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  height: 62, width: double.infinity, child: widget.visual),
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: titleC,
                ),
              ),
              const SizedBox(height: 3),
              Expanded(
                child: Text(
                  widget.subtitle,
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: subC),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: btnBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.buttonIcon, size: 17, color: btnFg),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.buttonLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: btnFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 16, color: btnFg),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Painter: line draws itself, signal dots pop in, last dot pulses
// ----------------------------------------------------------------------------

class _SignalsPainter extends CustomPainter {
  final double progress; // 0..1 line draw
  final double pulse; // 0..1 looping
  _SignalsPainter({required this.progress, required this.pulse});

  static const _ys = [0.75, 0.58, 0.66, 0.38, 0.50, 0.22, 0.34, 0.10];
  static const _signalIdx = [2, 4, 7];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final n = _ys.length;
    final pts = List.generate(
      n,
      (i) => Offset(
        size.width * i / (n - 1),
        size.height * 0.12 + size.height * 0.76 * _ys[i],
      ),
    );

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < n - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }

    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);

    canvas.drawPath(
      drawn,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    for (final idx in _signalIdx) {
      final at = idx / (n - 1);
      if (progress < at) continue;
      final pop = ((progress - at) / 0.12).clamp(0.0, 1.0);
      final c = pts[idx];
      final isLast = idx == n - 1;

      if (isLast) {
        canvas.drawCircle(
          c,
          5 + 7 * pulse,
          Paint()..color = Colors.white.withValues(alpha: 0.35 * (1 - pulse)),
        );
      }
      canvas.drawCircle(c, 5.5 * pop, Paint()..color = Colors.white);
      canvas.drawCircle(
        c,
        2.6 * pop,
        Paint()..color = const Color(0xFF6366F1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalsPainter old) =>
      old.progress != progress || old.pulse != pulse;
}

// ----------------------------------------------------------------------------
// Painter: bars grow in a stagger, latest bar breathes
// ----------------------------------------------------------------------------

class _BarsPainter extends CustomPainter {
  final double progress; // 0..1
  final double pulse; // 0..1 looping
  final Color color;
  final Color track;
  _BarsPainter({
    required this.progress,
    required this.pulse,
    required this.color,
    required this.track,
  });

  static const _hs = [0.40, 0.58, 0.48, 0.72, 0.62, 0.86, 0.78];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final n = _hs.length;
    const gap = 5.0;
    final bw = (size.width - gap * (n - 1)) / n;

    for (var i = 0; i < n; i++) {
      final start = i * 0.08;
      final t = Curves.easeOutBack
          .transform(((progress - start) / 0.55).clamp(0.0, 1.0));
      final x = i * (bw + gap);
      final full = size.height * _hs[i];
      final isLast = i == n - 1;
      final h = full * t + (isLast ? 3 * pulse * t : 0);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, bw, size.height),
          const Radius.circular(5),
        ),
        Paint()..color = track.withValues(alpha: 0.45),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, bw, h),
          const Radius.circular(5),
        ),
        Paint()
          ..color = isLast ? color : color.withValues(alpha: 0.35 + 0.05 * i),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) =>
      old.progress != progress || old.pulse != pulse;
}
