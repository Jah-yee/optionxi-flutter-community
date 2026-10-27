import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:optionxi/Components/cust_floating_ai.dart';
import 'package:optionxi/VirtualTradeJournal/add_journal_page.dart';
import 'package:optionxi/VirtualTradeJournal/db_read_supabase_journal_portfolio.dart';
import 'package:optionxi/VirtualTradeJournal/edit_journal_page.dart';
import 'package:optionxi/VirtualTradeJournal/journal_ui_kit.dart';
import 'package:optionxi/VirtualTrading/VDataModel/v_tradehistory.dart';
import 'package:timeago/timeago.dart' as timeago;

// ═════════════════════════════════════════════════════════════════════════
//  Trading report:  [ Calendar ] [ Weekly ] [ Growth ] [ All trades ]
//
//  Same plain-language style as the Journal screen:
//    Booked P&L   = profit/loss you locked in by closing trades
//    Made money   = a closed trade that ended in profit
//    Lost money   = a closed trade that ended in a loss
//    Bought       = normal buy ("long")
//    Sold first   = short sell
//
//  Self-contained: it loads its own data, keeps its own (tagged) controller
//  and reuses the shared JT design kit.
// ═════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────
//  Small helpers
// ─────────────────────────────────────────────

DateTime _day(DateTime x) {
  final l = x.toLocal();
  return DateTime(l.year, l.month, l.day);
}

int _key(DateTime d) {
  final l = d.toLocal();
  return l.year * 10000 + l.month * 100 + l.day;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _weekStartOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

double _sumPnl(Iterable<JournalTradeHistory> l) =>
    l.fold<double>(0, (s, t) => s + t.profitLoss);

Map<int, List<JournalTradeHistory>> _groupByDay(
    Iterable<JournalTradeHistory> trades) {
  final map = <int, List<JournalTradeHistory>>{};
  for (final t in trades) {
    map.putIfAbsent(_key(t.exitDate), () => []).add(t);
  }
  return map;
}

String _plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

// ─────────────────────────────────────────────
//  Stats
// ─────────────────────────────────────────────

class _Stats {
  final int count;
  final int wins;
  final int losses;
  final double total;
  final double avgWin;
  final double avgLoss;
  final JournalTradeHistory? best;
  final JournalTradeHistory? worst;

  const _Stats._(this.count, this.wins, this.losses, this.total, this.avgWin,
      this.avgLoss, this.best, this.worst);

  factory _Stats.of(List<JournalTradeHistory> l) {
    double total = 0, winSum = 0, lossSum = 0;
    int w = 0, ls = 0;
    JournalTradeHistory? best, worst;
    for (final t in l) {
      total += t.profitLoss;
      if (t.profitLoss > 0) {
        w++;
        winSum += t.profitLoss;
      } else if (t.profitLoss < 0) {
        ls++;
        lossSum += -t.profitLoss;
      }
      if (best == null || t.profitLoss > best.profitLoss) best = t;
      if (worst == null || t.profitLoss < worst.profitLoss) worst = t;
    }
    return _Stats._(l.length, w, ls, total, w == 0 ? 0 : winSum / w,
        ls == 0 ? 0 : lossSum / ls, best, worst);
  }

  int get decided => wins + losses;
  double get winRate => decided == 0 ? 0 : wins / decided * 100;
}

// ═════════════════════════════════════════════════════════════════════════
//  Controller
// ═════════════════════════════════════════════════════════════════════════

/// Loads closed trades for the report.
///
///  * Fetch errors keep the last good data and raise [hasError].
///  * Pull-to-refresh never tears down the screen (only the first load uses
///    [isLoading]).
///  * Out-of-order responses are ignored.
///  * Going further back (a longer period, an older month) quietly widens the
///    loaded window instead of showing an empty screen.
class JournalReportController extends GetxController {
  final String? suid;
  JournalReportController({this.suid});

  static const int allTime = 3650;
  static const List<({String label, int days})> periods = [
    (label: '7 days', days: 7),
    (label: '30 days', days: 30),
    (label: '3 months', days: 90),
    (label: '6 months', days: 180),
    (label: '1 year', days: 365),
    (label: 'All time', days: allTime),
  ];

  final PortfolioJournalService _service = PortfolioJournalService();

  final RxList<JournalTradeHistory> allTrades = <JournalTradeHistory>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isRefreshing = false.obs;
  final RxBool hasError = false.obs;

  /// Period the summary / growth / list use.
  final RxInt selectedDays = 30.obs;

  /// How far back we've actually fetched (calendar uses everything loaded).
  final RxInt loadedDays = 180.obs;

  String userSuid = '';
  bool _closed = false;
  bool _hasLoaded = false;
  bool _skipFirst = true;
  int _req = 0;

  StreamSubscription? _sub;
  Timer? _debounce;
  Timer? _retry;

  String get periodText {
    final opt = periods.firstWhere((o) => o.days == selectedDays.value,
        orElse: () => periods[1]);
    return opt.days == allTime ? 'all time' : 'last ${opt.label}';
  }

  /// Closed trades inside the selected period.
  List<JournalTradeHistory> periodTrades() {
    final days = selectedDays.value;
    final list = allTrades.toList();
    if (days >= allTime) return list;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return list.where((t) => t.exitDate.isAfter(cutoff)).toList();
  }

  @override
  void onInit() {
    super.onInit();
    _bootstrap();
  }

  @override
  void onClose() {
    _closed = true;
    _debounce?.cancel();
    _retry?.cancel();
    _sub?.cancel();
    super.onClose();
  }

  Future<void> _bootstrap() async {
    userSuid = await _resolveUid();
    if (_closed) return;
    if (userSuid.isEmpty) {
      hasError(true);
      isLoading(false);
      return;
    }
    _listen();
    await load();
  }

  Future<String> _resolveUid() async {
    final given = suid;
    if (given != null && given.isNotEmpty) return given;
    final current = FirebaseAuth.instance.currentUser?.uid;
    if (current != null && current.isNotEmpty) return current;
    try {
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 8));
      return user?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Pull-to-refresh / retry / reload after add or edit. Safe any time.
  Future<void> load() async {
    if (userSuid.isEmpty) {
      userSuid = await _resolveUid();
      if (_closed) return;
      if (userSuid.isEmpty) {
        hasError(true);
        isLoading(false);
        return;
      }
      if (_sub == null) _listen();
    }

    hasError(false);
    if (_hasLoaded) {
      isRefreshing(true);
    } else {
      isLoading(true);
    }

    final req = ++_req;
    try {
      final data =
          await _service.fetchTradeHistory(userSuid, days: loadedDays.value);
      if (_closed || req != _req) return;
      data.sort((a, b) => b.exitDate.compareTo(a.exitDate));
      allTrades.assignAll(data);
      _hasLoaded = true;
    } catch (e) {
      if (_closed || req != _req) return;
      hasError(true);
      debugPrint('Report fetch error: $e');
    } finally {
      if (!_closed && req == _req) {
        isLoading(false);
        isRefreshing(false);
      }
    }
  }

  void setPeriod(int days) {
    if (selectedDays.value == days) return;
    selectedDays.value = days;
    ensureDays(days);
  }

  /// Make sure at least [days] of history is loaded.
  void ensureDays(int days) {
    final need = _roundUp(days);
    if (need <= loadedDays.value) return;
    loadedDays.value = need;
    load();
  }

  /// Make sure history back to [from] is loaded (calendar / week navigation).
  void ensureCovers(DateTime from) {
    final d = DateTime.now().difference(from).inDays + 1;
    if (d > 0) ensureDays(d);
  }

  int _roundUp(int d) {
    for (final p in periods) {
      if (p.days >= d) return p.days;
    }
    return allTime;
  }

  void _listen() {
    _sub?.cancel();
    _skipFirst = true; // first event is just the current snapshot
    _sub = _service.subscribeToTradeHistoryChanges(userSuid).listen(
      (_) {
        if (_skipFirst) {
          _skipFirst = false;
          return;
        }
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350), load);
      },
      onError: (e) {
        debugPrint('Report subscription error: $e');
        if (_closed) return;
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 5), () {
          if (!_closed) _listen();
        });
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════

enum _Mode { calendar, weekly, growth, list }

enum _Filter { all, wins, losses }

enum _Sort { newest, biggestGain, biggestLoss }

class JournalAnalyticsPage extends StatefulWidget {
  /// Pass a [suid] to view someone else's report. Omit for the signed-in user.
  final String? suid;
  const JournalAnalyticsPage({Key? key, this.suid}) : super(key: key);

  @override
  State<JournalAnalyticsPage> createState() => _JournalAnalyticsPageState();
}

class _JournalAnalyticsPageState extends State<JournalAnalyticsPage> {
  late final JournalReportController c;
  late final String _tag;

  _Mode _mode = _Mode.calendar;
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.newest;

  late DateTime _month;
  late DateTime _week;
  DateTime? _selected;

  /// Open trade cards, keyed by trade id.
  final Set<int> _expanded = {};

  bool get _isOwner {
    final target = widget.suid;
    if (target == null || target.isEmpty) return true;
    return target == FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  void initState() {
    super.initState();
    _tag = 'report_${widget.suid ?? 'me'}_${identityHashCode(this)}';
    c = Get.put(JournalReportController(suid: widget.suid), tag: _tag);
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    _week = _weekStartOf(now);
  }

  @override
  void dispose() {
    Get.delete<JournalReportController>(tag: _tag);
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _editTrade(JournalTradeHistory t) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditJournalPage(journal: t)),
    );
    c.load();
  }

  Future<void> _addJournal() async {
    final raw = _selected ?? DateTime.now();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddJournalPage(
            initialDate: DateTime(raw.year, raw.month, raw.day, 9)),
      ),
    );
    c.load();
  }

  void _toggle(JournalTradeHistory t) => setState(() {
        if (!_expanded.add(t.id)) _expanded.remove(t.id);
      });

  void _selectDay(DateTime d) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = DateTime(d.year, d.month, d.day);
      _month = DateTime(d.year, d.month);
    });
  }

  void _changeMonth(int delta) {
    HapticFeedback.selectionClick();
    final m = DateTime(_month.year, _month.month + delta);
    setState(() => _month = m);
    c.ensureCovers(m);
  }

  void _changeWeek(int delta) {
    HapticFeedback.selectionClick();
    final w = DateTime(_week.year, _week.month, _week.day + 7 * delta);
    setState(() => _week = w);
    c.ensureCovers(w);
  }

  void _setMode(_Mode m) {
    HapticFeedback.selectionClick();
    setState(() {
      if (m == _Mode.weekly && _selected != null) {
        _week = _weekStartOf(_selected!);
      }
      _mode = m;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JT.bg(context),
      appBar: AppBar(
        backgroundColor: JT.bg(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: JT.text(context)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title:
            Text('Your trading report', style: JT.heading(context, size: 18)),
        centerTitle: false,
        actions: [
          Obx(() => c.isRefreshing.value
              ? const Padding(
                  padding: EdgeInsets.only(right: 18),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: JT.blue),
                  ),
                )
              : IconButton(
                  tooltip: 'Refresh',
                  icon: Icon(Icons.refresh_rounded, color: JT.text(context)),
                  onPressed: c.load,
                )),
        ],
      ),
      floatingActionButton: _isOwner
          ? MagicalAIButton(onPressed: _addJournal, label: 'Add journal')
          : null,
      body: Obx(() {
        final all = c.allTrades.toList();
        final hasError = c.hasError.value;
        final loading = c.isLoading.value;
        final refreshing = c.isRefreshing.value;
        final period = c.periodTrades();

        if (loading && all.isEmpty) return const _ReportSkeleton();

        if (all.isEmpty) {
          return RefreshIndicator(
            onRefresh: c.load,
            child: _ScrollableMessage(
              child: hasError
                  ? _EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'We couldn\'t load your trades',
                      subtitle:
                          'Please check your internet connection and try again.',
                      action: JtButton(
                        label: 'Try again',
                        icon: Icons.refresh_rounded,
                        filled: true,
                        onTap: c.load,
                      ),
                    )
                  : _EmptyState(
                      icon: Icons.insights_rounded,
                      title: 'No closed trades yet',
                      subtitle:
                          'Close a trade, or add one to your journal, and your '
                          'calendar, charts and summary will appear here.',
                      action: _isOwner
                          ? JtButton(
                              label: 'Add a journal entry',
                              icon: Icons.add_rounded,
                              filled: true,
                              onTap: _addJournal,
                            )
                          : null,
                    ),
            ),
          );
        }

        final byDay = _groupByDay(all);
        final stats = _Stats.of(period);

        return RefreshIndicator(
          onRefresh: c.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                  child: _SyncBanner(
                      show: hasError, busy: refreshing, onRetry: c.load)),
              SliverToBoxAdapter(
                child: _SummaryCard(stats: stats, period: c.periodText),
              ),
              SliverToBoxAdapter(child: _PeriodChips(controller: c)),
              SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: refreshing
                      ? const Padding(
                          key: ValueKey('bar'),
                          padding: EdgeInsets.fromLTRB(16, 2, 16, 0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                            child: LinearProgressIndicator(minHeight: 3),
                          ),
                        )
                      : const SizedBox(key: ValueKey('none'), height: 3),
                ),
              ),
              SliverToBoxAdapter(
                child: _ModeSwitch(mode: _mode, onChanged: _setMode),
              ),
              ..._modeSlivers(all, period, byDay, stats),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        );
      }),
    );
  }

  List<Widget> _modeSlivers(
    List<JournalTradeHistory> all,
    List<JournalTradeHistory> period,
    Map<int, List<JournalTradeHistory>> byDay,
    _Stats stats,
  ) {
    switch (_mode) {
      case _Mode.calendar:
        return _calendarSlivers(all, byDay);
      case _Mode.weekly:
        return _weeklySlivers(byDay);
      case _Mode.growth:
        return _growthSlivers(period, stats);
      case _Mode.list:
        return _listSlivers(period);
    }
  }

  Widget _box(Widget child,
          {EdgeInsets padding = const EdgeInsets.fromLTRB(16, 0, 16, 12)}) =>
      SliverToBoxAdapter(child: Padding(padding: padding, child: child));

  // ── Calendar ───────────────────────────────────────────────────────────

  List<Widget> _calendarSlivers(
    List<JournalTradeHistory> all,
    Map<int, List<JournalTradeHistory>> byDay,
  ) {
    final now = DateTime.now();
    final canNext = DateTime(_month.year, _month.month + 1)
        .isBefore(DateTime(now.year, now.month + 1));
    final monthTrades = all.where((t) {
      final d = t.exitDate.toLocal();
      return d.year == _month.year && d.month == _month.month;
    }).toList();
    final sel = _selected;
    final List<JournalTradeHistory> selTrades = sel == null
        ? const <JournalTradeHistory>[]
        : (byDay[_key(sel)] ?? const <JournalTradeHistory>[]);

    return [
      _box(_Heatmap(
        byDay: byDay,
        focusedMonth: _month,
        selected: _selected,
        onTap: _selectDay,
      )),
      _box(_MonthCard(
        month: _month,
        stats: _Stats.of(monthTrades),
        onPrev: () => _changeMonth(-1),
        onNext: canNext ? () => _changeMonth(1) : null,
      )),
      _box(_CalendarGrid(
        month: _month,
        selected: _selected,
        byDay: byDay,
        onSelect: _selectDay,
      )),
      if (sel != null)
        _box(
          _dayBlock(sel, selTrades, showEmpty: true),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        ),
    ];
  }

  Widget _dayBlock(DateTime day, List<JournalTradeHistory> trades,
      {bool showEmpty = false}) {
    if (trades.isEmpty) {
      if (!showEmpty) return const SizedBox.shrink();
      return _EmptyNote(
        icon: Icons.event_available_rounded,
        text: 'No trades closed on ${DateFormat('d MMM').format(day)}',
      );
    }
    final total = _sumPnl(trades);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(DateFormat('EEEE, d MMMM').format(day),
                    style: JT.heading(context, size: 14)),
              ),
              Text(_plural(trades.length, 'trade'),
                  style: JT.caption(context, size: 12)),
              const SizedBox(width: 10),
              Text(jtMoney(total, signed: true),
                  style: JT.number(context, size: 13, color: JT.pnl(total))),
            ],
          ),
        ),
        for (final t in trades)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _tile(t),
          ),
      ],
    );
  }

  Widget _tile(JournalTradeHistory t) => KeyedSubtree(
        key: ValueKey('T-${t.id}'),
        child: _TradeTile(
          trade: t,
          expanded: _expanded.contains(t.id),
          canEdit: _isOwner,
          onToggle: () => _toggle(t),
          onEdit: () => _editTrade(t),
        ),
      );

  // ── Weekly ─────────────────────────────────────────────────────────────

  List<Widget> _weeklySlivers(Map<int, List<JournalTradeHistory>> byDay) {
    final today = _day(DateTime.now());
    final days = List.generate(
        7, (i) => DateTime(_week.year, _week.month, _week.day + i));
    final nextStart = DateTime(_week.year, _week.month, _week.day + 7);
    final canNext = !nextStart.isAfter(today);
    final List<JournalTradeHistory> weekTrades = [
      for (final d in days)
        ...(byDay[_key(d)] ?? const <JournalTradeHistory>[]),
    ];
    final stats = _Stats.of(weekTrades);
    final end = days.last;

    return [
      _box(
        _Card(
          child: Column(
            children: [
              Row(
                children: [
                  _NavBtn(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => _changeWeek(-1)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DateFormat('d MMM').format(_week)} – '
                          '${DateFormat('d MMM yyyy').format(end)}',
                          style: JT.heading(context, size: 15),
                        ),
                        const SizedBox(height: 2),
                        Text('${_plural(weekTrades.length, 'trade')} this week',
                            style: JT.caption(context)),
                      ],
                    ),
                  ),
                  _NavBtn(
                    icon: Icons.chevron_right_rounded,
                    onTap: canNext ? () => _changeWeek(1) : null,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _MiniTile(
                      label: 'Booked',
                      value: jtMoney(stats.total, signed: true),
                      color: JT.pnl(stats.total)),
                  const SizedBox(width: 8),
                  _MiniTile(
                      label: 'Made money',
                      value: '${stats.wins}',
                      color: JT.profit),
                  const SizedBox(width: 8),
                  _MiniTile(
                      label: 'Lost money',
                      value: '${stats.losses}',
                      color: JT.loss),
                ],
              ),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      ),
      _box(
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Day by day', style: JT.heading(context, size: 14)),
              const SizedBox(height: 16),
              _DayBars(days: days, byDay: byDay),
            ],
          ),
        ),
      ),
      _box(
        Column(
          children: [
            for (final d in days)
              _dayBlock(d, byDay[_key(d)] ?? const <JournalTradeHistory>[]),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      ),
    ];
  }

  // ── Growth ─────────────────────────────────────────────────────────────

  List<Widget> _growthSlivers(List<JournalTradeHistory> period, _Stats s) {
    final sorted = [...period]
      ..sort((a, b) => a.exitDate.compareTo(b.exitDate));
    double cum = 0;
    final values = [for (final t in sorted) cum += t.profitLoss];
    final longs = period.where((t) => !t.isShortSell).toList();
    final shorts = period.where((t) => t.isShortSell).toList();
    final biggest = [...period]
      ..sort((a, b) => b.profitLoss.abs().compareTo(a.profitLoss.abs()));

    final ratio = s.avgLoss <= 0 || s.avgWin <= 0 ? null : s.avgWin / s.avgLoss;

    return [
      _box(
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How your money has grown · ${c.periodText}',
                  style: JT.caption(context, size: 12)),
              const SizedBox(height: 4),
              JtCount(
                value: s.total,
                format: (v) => jtMoney(v, signed: true),
                style: JT.number(context, size: 28, color: JT.pnl(s.total)),
              ),
              const SizedBox(height: 14),
              if (values.isEmpty)
                const _EmptyNote(
                    icon: Icons.show_chart_rounded,
                    text: 'No closed trades in this period')
              else ...[
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _SparkPainter(
                      values: values,
                      line: values.last >= 0 ? JT.profit : JT.loss,
                      grid: JT.border(context),
                      dotInner: JT.surface(context),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        DateFormat('d MMM yy')
                            .format(sorted.first.exitDate.toLocal()),
                        style: JT.caption(context, size: 11)),
                    Text(
                        DateFormat('d MMM yy')
                            .format(sorted.last.exitDate.toLocal()),
                        style: JT.caption(context, size: 11)),
                  ],
                ),
              ],
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      ),
      _box(Row(
        children: [
          _StatBox(
              label: 'Success rate',
              value: s.decided == 0 ? '—' : '${s.winRate.toStringAsFixed(0)}%',
              hint: s.decided == 0
                  ? 'Close a trade to see this'
                  : '${s.wins} of ${s.decided} made money',
              color: s.winRate >= 50 ? JT.profit : JT.amber),
          const SizedBox(width: 10),
          _StatBox(
              label: 'Win vs loss size',
              value: ratio == null ? '—' : '${ratio.toStringAsFixed(2)}x',
              hint: ratio == null
                  ? 'Needs a win and a loss'
                  : 'Avg win ÷ avg loss',
              color: ratio == null
                  ? JT.text2(context)
                  : (ratio >= 1 ? JT.profit : JT.amber)),
        ],
      )),
      _box(Row(
        children: [
          _StatBox(
              label: 'Average win',
              value: s.wins == 0 ? '—' : jtMoney(s.avgWin),
              hint: 'When a trade makes money',
              color: JT.profit),
          const SizedBox(width: 10),
          _StatBox(
              label: 'Average loss',
              value: s.losses == 0 ? '—' : jtMoney(s.avgLoss),
              hint: 'When a trade loses money',
              color: JT.loss),
        ],
      )),
      if (s.best != null && s.worst != null)
        _box(Row(
          children: [
            _Highlight(title: 'Best trade', trade: s.best!, color: JT.profit),
            const SizedBox(width: 10),
            _Highlight(
                title: 'Toughest trade', trade: s.worst!, color: JT.loss),
          ],
        )),
      if (period.isNotEmpty)
        _box(_Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bought vs sold first',
                  style: JT.heading(context, size: 14)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _SideColumn(isShort: false, trades: longs),
                  const _VLine(),
                  _SideColumn(isShort: true, trades: shorts),
                ],
              ),
            ],
          ),
        )),
      if (biggest.isNotEmpty)
        _box(
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
            child: Text('Your biggest trades',
                style: JT.heading(context, size: 14)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        ),
      if (biggest.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _tile(biggest[i]),
              ),
              childCount: math.min(5, biggest.length),
            ),
          ),
        ),
    ];
  }

  // ── All trades ─────────────────────────────────────────────────────────

  List<Widget> _listSlivers(List<JournalTradeHistory> period) {
    var list = [...period];
    if (_filter == _Filter.wins) {
      list = list.where((t) => t.profitLoss > 0).toList();
    } else if (_filter == _Filter.losses) {
      list = list.where((t) => t.profitLoss < 0).toList();
    }
    switch (_sort) {
      case _Sort.biggestGain:
        list.sort((a, b) => b.profitLoss.compareTo(a.profitLoss));
        break;
      case _Sort.biggestLoss:
        list.sort((a, b) => a.profitLoss.compareTo(b.profitLoss));
        break;
      case _Sort.newest:
        list.sort((a, b) => b.exitDate.compareTo(a.exitDate));
    }
    final total = _sumPnl(list);

    return [
      _box(
        Row(
          children: [
            _FilterPill(
              label: 'All',
              active: _filter == _Filter.all,
              onTap: () => setState(() => _filter = _Filter.all),
            ),
            const SizedBox(width: 8),
            _FilterPill(
              label: 'Made money',
              active: _filter == _Filter.wins,
              color: JT.profit,
              onTap: () => setState(() => _filter =
                  _filter == _Filter.wins ? _Filter.all : _Filter.wins),
            ),
            const SizedBox(width: 8),
            _FilterPill(
              label: 'Lost money',
              active: _filter == _Filter.losses,
              color: JT.loss,
              onTap: () => setState(() => _filter =
                  _filter == _Filter.losses ? _Filter.all : _Filter.losses),
            ),
            const Spacer(),
            JtPressable(
              onTap: _showSortSheet,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.sort_rounded,
                    size: 20, color: JT.text2(context)),
              ),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      ),
      _box(
        Row(
          children: [
            Text('${_plural(list.length, 'trade')} · ${_sortLabel(_sort)}',
                style: JT.caption(context, size: 12)),
            const Spacer(),
            Text(jtMoney(total, signed: true),
                style: JT.number(context, size: 13, color: JT.pnl(total))),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      ),
      if (list.isEmpty)
        _box(const _EmptyNote(
            icon: Icons.inbox_outlined, text: 'No trades match this filter'))
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _tile(list[i]),
              ),
              childCount: list.length,
            ),
          ),
        ),
    ];
  }

  String _sortLabel(_Sort s) {
    switch (s) {
      case _Sort.newest:
        return 'Newest first';
      case _Sort.biggestGain:
        return 'Biggest gain first';
      case _Sort.biggestLoss:
        return 'Biggest loss first';
    }
  }

  void _showSortSheet() {
    HapticFeedback.selectionClick();
    showJtSheet<void>(
      context,
      (ctx) => JtSheet(
        title: 'Sort trades',
        child: Column(
          children: [
            for (final s in _Sort.values)
              JtPressable(
                onTap: () {
                  setState(() => _sort = s);
                  Navigator.of(ctx).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        _sort == s
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: _sort == s ? JT.blue : JT.text3(ctx),
                      ),
                      const SizedBox(width: 12),
                      Text(_sortLabel(s), style: JT.body(ctx, size: 15)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Header pieces
// ═════════════════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final _Stats stats;
  final String period;
  const _SummaryCard({required this.stats, required this.period});

  @override
  Widget build(BuildContext context) {
    final color = JT.pnl(stats.total);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [JT.tint(context, color, 0.15), JT.surface(context)],
        ),
        border: Border.all(color: color.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(JT.isDark(context) ? 0.25 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Booked profit / loss · $period',
              style: JT.caption(context, size: 12)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: JtCount(
                    value: stats.total,
                    format: (v) => jtMoney(v, signed: true),
                    style: JT.number(context, size: 30, color: color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  stats.count == 0
                      ? 'No trades'
                      : _plural(stats.count, 'trade'),
                  style: JT.caption(context, size: 12),
                ),
              ),
            ],
          ),
          if (stats.decided > 0) ...[
            const SizedBox(height: 14),
            _WinLossBar(wins: stats.wins, losses: stats.losses),
            const SizedBox(height: 8),
            Row(
              children: [
                const _Dot(color: JT.profit),
                const SizedBox(width: 6),
                Text('${stats.wins} made money',
                    style: JT.caption(context, size: 12)),
                const SizedBox(width: 14),
                const _Dot(color: JT.loss),
                const SizedBox(width: 6),
                Text('${stats.losses} lost money',
                    style: JT.caption(context, size: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _WinLossBar extends StatelessWidget {
  final int wins;
  final int losses;
  const _WinLossBar({required this.wins, required this.losses});

  @override
  Widget build(BuildContext context) {
    final total = wins + losses;
    final frac = total == 0 ? 0.0 : wins / total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: frac),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, f, __) => Row(
            children: [
              Expanded(
                flex: (f * 1000).round().clamp(0, 1000),
                child: Container(color: JT.profitBright),
              ),
              Expanded(
                flex: ((1 - f) * 1000).round().clamp(0, 1000),
                child: Container(color: JT.lossBright),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodChips extends StatelessWidget {
  final JournalReportController controller;
  const _PeriodChips({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = controller.selectedDays.value;
      return SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          physics: const BouncingScrollPhysics(),
          itemCount: JournalReportController.periods.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final opt = JournalReportController.periods[i];
            final active = selected == opt.days;
            return JtPressable(
              pressedScale: 0.95,
              onTap: () {
                HapticFeedback.selectionClick();
                controller.setPeriod(opt.days);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: active ? JT.blue : JT.surface(context),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: active ? JT.blue : JT.border(context)),
                ),
                child: Text(
                  opt.label,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? Colors.white : JT.text2(context),
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

class _ModeSwitch extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;
  const _ModeSwitch({required this.mode, required this.onChanged});

  static const _items = [
    (m: _Mode.calendar, icon: Icons.calendar_month_rounded, label: 'Calendar'),
    (m: _Mode.weekly, icon: Icons.view_week_rounded, label: 'Weekly'),
    (m: _Mode.growth, icon: Icons.show_chart_rounded, label: 'Growth'),
    (m: _Mode.list, icon: Icons.list_alt_rounded, label: 'All trades'),
  ];

  @override
  Widget build(BuildContext context) {
    final index = _items.indexWhere((e) => e.m == mode);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      padding: const EdgeInsets.all(4),
      height: 58,
      decoration: BoxDecoration(
        color: JT.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JT.border(context)),
      ),
      child: LayoutBuilder(
        builder: (ctx, box) {
          final w = box.maxWidth / _items.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: index * w,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: JT.blue,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: JT.blue.withOpacity(0.32),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final it in _items)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(it.m),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(it.icon,
                                size: 18,
                                color: it.m == mode
                                    ? Colors.white
                                    : JT.text2(context)),
                            const SizedBox(height: 3),
                            Text(
                              it.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: it.m == mode
                                    ? Colors.white
                                    : JT.text2(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  final bool show;
  final bool busy;
  final VoidCallback onRetry;
  const _SyncBanner(
      {required this.show, required this.busy, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: JT.tint(context, JT.amber, 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 16, color: JT.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Couldn\'t refresh. Showing your last saved data.',
                      style: JT.caption(context,
                          size: 12, color: JT.text(context)),
                    ),
                  ),
                  JtButton(
                    label: 'Retry',
                    height: 28,
                    color: JT.amber,
                    loading: busy,
                    onTap: onRetry,
                  ),
                ],
              ),
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Calendar pieces
// ═════════════════════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: JT.card(context),
        child: child,
      );
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onTap == null ? 0.35 : 1,
        child: JtPressable(
          onTap: onTap,
          pressedScale: 0.92,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: JT.surface2(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: JT.border(context)),
            ),
            child: Icon(icon, size: 20, color: JT.text2(context)),
          ),
        ),
      );
}

class _MiniTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniTile(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: JT.tint(context, color, 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JT.caption(context, size: 11)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: JT.number(context, size: 15, color: color)),
              ),
            ],
          ),
        ),
      );
}

class _MonthCard extends StatelessWidget {
  final DateTime month;
  final _Stats stats;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  const _MonthCard({
    required this.month,
    required this.stats,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          Row(
            children: [
              _NavBtn(icon: Icons.chevron_left_rounded, onTap: onPrev),
              Expanded(
                child: Center(
                  child: Text(DateFormat('MMMM yyyy').format(month),
                      style: JT.heading(context, size: 17)),
                ),
              ),
              _NavBtn(icon: Icons.chevron_right_rounded, onTap: onNext),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MiniTile(
                  label: 'This month',
                  value: stats.count == 0
                      ? '—'
                      : jtMoney(stats.total, signed: true),
                  color: stats.count == 0
                      ? JT.text2(context)
                      : JT.pnl(stats.total)),
              const SizedBox(width: 8),
              _MiniTile(
                  label: 'Trades', value: '${stats.count}', color: JT.blue),
              const SizedBox(width: 8),
              _MiniTile(
                  label: 'Success rate',
                  value: stats.decided == 0
                      ? '—'
                      : '${stats.winRate.toStringAsFixed(0)}%',
                  color: stats.winRate >= 50 ? JT.profit : JT.amber),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final DateTime month;
  final DateTime? selected;
  final Map<int, List<JournalTradeHistory>> byDay;
  final ValueChanged<DateTime> onSelect;
  const _CalendarGrid({
    required this.month,
    required this.selected,
    required this.byDay,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final offset = first.weekday - 1;
    final rows = ((offset + last.day) / 7).ceil();
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      decoration: JT.card(context),
      child: Column(
        children: [
          Row(
            children: [
              for (final d in const [
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
                'Sun'
              ])
                Expanded(
                  child: Center(
                    child: Text(d, style: JT.caption(context, size: 11)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(height: 1, color: JT.border(context)),
          const SizedBox(height: 4),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                      child: _cell(
                          context, r * 7 + col - offset + 1, last.day, today)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, int n, int daysInMonth, DateTime today) {
    if (n < 1 || n > daysInMonth) return const SizedBox(height: 54);
    final day = DateTime(month.year, month.month, n);
    final trades = byDay[_key(day)] ?? const <JournalTradeHistory>[];
    final pnl = _sumPnl(trades);
    final has = trades.isNotEmpty;
    final isSel = selected != null && _sameDay(selected!, day);
    final isToday = _sameDay(today, day);
    final color = JT.pnl(pnl);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(day),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.all(2),
        height: 50,
        decoration: BoxDecoration(
          color: isSel
              ? JT.blue
              : (has ? JT.tint(context, color, 0.10) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
          border:
              isToday && !isSel ? Border.all(color: JT.blue, width: 1.5) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$n',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight:
                    isSel || isToday ? FontWeight.w800 : FontWeight.w500,
                color: isSel
                    ? Colors.white
                    : (isToday ? JT.blue : JT.text(context)),
              ),
            ),
            if (has) ...[
              const SizedBox(height: 3),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isSel ? Colors.white : color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Last ~6 months, one square per day. Greener / redder = bigger result.
class _Heatmap extends StatelessWidget {
  final Map<int, List<JournalTradeHistory>> byDay;
  final DateTime focusedMonth;
  final DateTime? selected;
  final ValueChanged<DateTime> onTap;
  const _Heatmap({
    required this.byDay,
    required this.focusedMonth,
    required this.selected,
    required this.onTap,
  });

  static const double _cell = 12;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    final s0 = DateTime(today.year, today.month, today.day - 7 * 25);
    final start = DateTime(s0.year, s0.month, s0.day - (s0.weekday - 1));
    final days = <DateTime>[];
    for (var d = start;
        !d.isAfter(today);
        d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(d);
    }
    final cols = (days.length / 7).ceil();

    double maxAbs = 0;
    for (final d in days) {
      final v = _sumPnl(byDay[_key(d)] ?? const []).abs();
      if (v > maxAbs) maxAbs = v;
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Last 6 months', style: JT.heading(context, size: 14)),
              const Spacer(),
              const _Dot(color: JT.profitBright),
              const SizedBox(width: 4),
              Text('Profit', style: JT.caption(context, size: 11)),
              const SizedBox(width: 10),
              const _Dot(color: JT.lossBright),
              const SizedBox(width: 4),
              Text('Loss', style: JT.caption(context, size: 11)),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true, // newest weeks visible first
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 16,
                  width: cols * (_cell + _gap),
                  child: Stack(
                    children: [
                      for (var col = 0; col < cols; col++)
                        if (days[col * 7].day <= 7)
                          Positioned(
                            left: col * (_cell + _gap),
                            child: Text(
                              DateFormat('MMM').format(days[col * 7]),
                              style: JT.caption(context,
                                  size: 10, color: JT.text3(context)),
                            ),
                          ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var col = 0; col < cols; col++)
                      Padding(
                        padding:
                            EdgeInsets.only(right: col < cols - 1 ? _gap : 0),
                        child: Column(
                          children: [
                            for (var row = 0; row < 7; row++)
                              _square(
                                  context, days, col * 7 + row, today, maxAbs),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _square(BuildContext context, List<DateTime> days, int i,
      DateTime today, double maxAbs) {
    if (i >= days.length)
      return const SizedBox(width: _cell, height: _cell + _gap);
    final d = days[i];
    final pnl = _sumPnl(byDay[_key(d)] ?? const []);
    final has = (byDay[_key(d)] ?? const []).isNotEmpty;
    final intensity =
        maxAbs > 0 ? (pnl.abs() / maxAbs).clamp(0.0, 1.0).toDouble() : 0.0;

    Color color;
    if (!has || pnl == 0) {
      color = JT.border(context);
    } else {
      final base = pnl > 0 ? JT.profitBright : JT.lossBright;
      color = base.withOpacity(0.30 + 0.70 * intensity);
    }
    final isSel = selected != null && _sameDay(selected!, d);

    return GestureDetector(
      onTap: () => onTap(d),
      child: Container(
        width: _cell,
        height: _cell,
        margin: const EdgeInsets.only(bottom: _gap),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: isSel
              ? Border.all(color: JT.blue, width: 1.6)
              : (_sameDay(d, today)
                  ? Border.all(color: JT.text3(context))
                  : null),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Weekly pieces
// ═════════════════════════════════════════════════════════════════════════

class _DayBars extends StatelessWidget {
  final List<DateTime> days;
  final Map<int, List<JournalTradeHistory>> byDay;
  const _DayBars({required this.days, required this.byDay});

  @override
  Widget build(BuildContext context) {
    final pnls = [for (final d in days) _sumPnl(byDay[_key(d)] ?? const [])];
    final maxAbs = pnls.fold<double>(0, (m, v) => math.max(m, v.abs()));
    final today = DateTime.now();

    return SizedBox(
      height: 132,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: _bar(
                  context,
                  days[i],
                  pnls[i],
                  maxAbs,
                  (byDay[_key(days[i])] ?? const []).isNotEmpty,
                  _sameDay(days[i], today)),
            ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, DateTime d, double pnl, double maxAbs,
      bool has, bool isToday) {
    final color = !has ? JT.border(context) : JT.pnl(pnl);
    final frac = maxAbs > 0 ? pnl.abs() / maxAbs : 0.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 14,
          child: has
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(jtMoney(pnl.abs()),
                      style: JT.number(context, size: 10, color: color)),
                )
              : null,
        ),
        const SizedBox(height: 3),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(
              begin: 0, end: has ? (60 * frac).clamp(5.0, 60.0) : 3),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (_, h, __) => Container(
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          DateFormat('E').format(d),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
            color: isToday ? JT.blue : JT.text2(context),
          ),
        ),
        Text('${d.day}',
            style: JT.caption(context, size: 10, color: JT.text3(context))),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Growth pieces
// ═════════════════════════════════════════════════════════════════════════

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color line;
  final Color grid;
  final Color dotInner;
  _SparkPainter({
    required this.values,
    required this.line,
    required this.grid,
    required this.dotInner,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    // Always include 0 so you can see where "even" is.
    final minV = math.min(0.0, values.reduce(math.min));
    final maxV = math.max(0.0, values.reduce(math.max));
    var range = maxV - minV;
    if (range == 0) range = 1;

    double x(int i) => values.length == 1
        ? size.width / 2
        : i / (values.length - 1) * size.width;
    double y(double v) =>
        size.height -
        ((v - minV) / range * size.height * 0.84 + size.height * 0.08);

    // Zero line
    canvas.drawLine(
      Offset(0, y(0)),
      Offset(size.width, y(0)),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      if (values.length < 3) {
        path.lineTo(x(i), y(values[i]));
      } else {
        final x0 = x(i - 1), y0 = y(values[i - 1]);
        final x1 = x(i), y1 = y(values[i]);
        final mx = x0 + (x1 - x0) * 0.5;
        path.cubicTo(mx, y0, mx, y1, x1, y1);
      }
    }

    final fill = Path.from(path)
      ..lineTo(x(values.length - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withOpacity(0.20), line.withOpacity(0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final end = Offset(x(values.length - 1), y(values.last));
    canvas.drawCircle(end, 5, Paint()..color = line);
    canvas.drawCircle(end, 2.6, Paint()..color = dotInner);
  }

  @override
  bool shouldRepaint(_SparkPainter o) =>
      o.values != values || o.line != line || o.grid != grid;
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final Color color;
  const _StatBox({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: JT.card(context, radius: 16),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 44,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: JT.caption(context, size: 11)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          style: JT.number(context, size: 18, color: color)),
                    ),
                    const SizedBox(height: 2),
                    Text(hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JT.caption(context,
                            size: 10.5, color: JT.text3(context))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _Highlight extends StatelessWidget {
  final String title;
  final JournalTradeHistory trade;
  final Color color;
  const _Highlight(
      {required this.title, required this.trade, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: JT.tint(context, color, 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: JT.caption(context, size: 11, color: color)),
              const SizedBox(height: 6),
              Text(jtDisplaySymbol(trade.symbol),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JT.heading(context, size: 14)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(jtMoney(trade.profitLoss, signed: true),
                    style: JT.number(context, size: 18, color: color)),
              ),
              const SizedBox(height: 2),
              Text(DateFormat('d MMM yy').format(trade.exitDate.toLocal()),
                  style: JT.caption(context, size: 11)),
            ],
          ),
        ),
      );
}

class _SideColumn extends StatelessWidget {
  final bool isShort;
  final List<JournalTradeHistory> trades;
  const _SideColumn({required this.isShort, required this.trades});

  @override
  Widget build(BuildContext context) {
    final total = _sumPnl(trades);
    final s = _Stats.of(trades);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JtDirectionChip(isShort: isShort),
          const SizedBox(height: 10),
          if (trades.isEmpty)
            Text('No trades', style: JT.caption(context, size: 13))
          else ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(jtMoney(total, signed: true),
                  style: JT.number(context, size: 18, color: JT.pnl(total))),
            ),
            const SizedBox(height: 3),
            Text(
              '${_plural(trades.length, 'trade')}'
              '${s.decided > 0 ? ' · ${s.winRate.toStringAsFixed(0)}% made money' : ''}',
              style: JT.caption(context, size: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _VLine extends StatelessWidget {
  const _VLine();
  @override
  Widget build(BuildContext context) => Container(
      height: 56,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: JT.border(context));
}

// ═════════════════════════════════════════════════════════════════════════
//  List pieces
// ═════════════════════════════════════════════════════════════════════════

class _FilterPill extends StatelessWidget {
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback onTap;
  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? JT.blue;
    return JtPressable(
      pressedScale: 0.95,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? JT.tint(context, c, 0.12) : JT.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? c : JT.border(context)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            color: active ? c : JT.text2(context),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Trade card (one closed trade)
// ═════════════════════════════════════════════════════════════════════════

class _TradeTile extends StatelessWidget {
  final JournalTradeHistory trade;
  final bool expanded;
  final bool canEdit;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  const _TradeTile({
    required this.trade,
    required this.expanded,
    required this.canEdit,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final t = trade;
    final isShort = t.isShortSell;
    final pnl = t.profitLoss;
    final color = JT.pnl(pnl);
    final cost = t.entryPrice * t.quantity;
    final pct = cost > 0 ? pnl / cost * 100 : 0.0;
    final entry = t.entryDate.toLocal();
    final exit = t.exitDate.toLocal();
    final fmt = DateFormat('d MMM yyyy, h:mm a');
    final hasSafety = (t.stopLossPrice ?? 0) > 0;
    final hasGoal = (t.targetPrice ?? 0) > 0;

    return JtPressable(
      onTap: onToggle,
      pressedScale: 0.985,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: JT.card(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  JtLogo(symbolKey: jtLogoKey(t.symbol), accent: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(jtDisplaySymbol(t.symbol),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: JT.heading(context, size: 16)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            JtDirectionChip(isShort: isShort),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(_plural(t.quantity, 'share'),
                                  overflow: TextOverflow.ellipsis,
                                  style: JT.caption(context)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        pnl > 0
                            ? 'You made'
                            : (pnl < 0 ? 'You lost' : 'Break-even'),
                        style: JT.caption(context, size: 11, color: color),
                      ),
                      const SizedBox(height: 2),
                      Text(jtMoney(pnl.abs()),
                          style: JT.number(context, size: 17, color: color)),
                      const SizedBox(height: 4),
                      JtPctTag(pct: pct),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: JT.surface2(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: JT.border(context)),
                ),
                child: Row(
                  children: [
                    _Metric(
                      label: isShort ? 'Sold at' : 'Bought at',
                      value: jtPrice(t.entryPrice),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: JT.tint(context, color, 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 14, color: color),
                    ),
                    _Metric(
                      label: isShort ? 'Bought back at' : 'Sold at',
                      value: jtPrice(t.exitPrice),
                      color: color,
                      align: CrossAxisAlignment.end,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.access_time_rounded,
                      size: 13, color: JT.text3(context)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Closed ${timeago.format(t.exitDate)} · held ${jtDuration(entry, exit)}',
                      overflow: TextOverflow.ellipsis,
                      style: JT.caption(context, size: 12),
                    ),
                  ),
                  Text(expanded ? 'Less' : 'Details',
                      style: JT.caption(context,
                          size: 12, color: JT.text2(context))),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: JT.text2(context)),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !expanded
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(
                          children: [
                            Divider(height: 1, color: JT.border(context)),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _Info(
                                    icon: Icons.login_rounded,
                                    label: isShort ? 'Sold on' : 'Bought on',
                                    value: fmt.format(entry),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _Info(
                                    icon: Icons.logout_rounded,
                                    label:
                                        isShort ? 'Bought back on' : 'Sold on',
                                    value: fmt.format(exit),
                                  ),
                                ),
                              ],
                            ),
                            if (hasSafety || hasGoal) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  if (hasSafety)
                                    Expanded(
                                      child: _Info(
                                        icon: Icons.shield_outlined,
                                        label: 'Safety exit',
                                        value: jtPrice(t.stopLossPrice!),
                                      ),
                                    ),
                                  if (hasSafety && hasGoal)
                                    const SizedBox(width: 10),
                                  if (hasGoal)
                                    Expanded(
                                      child: _Info(
                                        icon: Icons.flag_outlined,
                                        label: 'Goal',
                                        value: jtPrice(t.targetPrice!),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (t.timeframe.isNotEmpty || t.charges > 0) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  if (t.timeframe.isNotEmpty)
                                    Expanded(
                                      child: _Info(
                                        icon: Icons.schedule_rounded,
                                        label: 'Planned for',
                                        value: t.timeframe,
                                      ),
                                    ),
                                  if (t.timeframe.isNotEmpty && t.charges > 0)
                                    const SizedBox(width: 10),
                                  if (t.charges > 0)
                                    Expanded(
                                      child: _Info(
                                        icon: Icons.receipt_long_outlined,
                                        label: 'Fees & charges',
                                        value: jtPrice(t.charges),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (t.reason != null &&
                                t.reason!.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _Note(text: t.reason!),
                            ],
                            if (canEdit) ...[
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerRight,
                                child: JtButton(
                                  label: 'Edit notes',
                                  icon: Icons.edit_outlined,
                                  height: 40,
                                  onTap: onEdit,
                                ),
                              ),
                            ],
                          ],
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

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final CrossAxisAlignment align;
  const _Metric({
    required this.label,
    required this.value,
    this.color,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: align,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JT.caption(context, size: 11)),
            const SizedBox(height: 3),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JT.number(context, size: 13, color: color)),
          ],
        ),
      );
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Info({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JT.surface2(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JT.border(context)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: JT.text2(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: JT.caption(context, size: 11)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: JT.body(context,
                          size: 12.5, weight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JT.tint(context, JT.blue, 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JT.blue.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_note_rounded, size: 16, color: JT.blue),
                const SizedBox(width: 6),
                Text('Why you took this trade',
                    style: JT.caption(context, size: 12, color: JT.blue)),
              ],
            ),
            const SizedBox(height: 6),
            Text(text, style: JT.body(context, size: 13.5)),
          ],
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════
//  Empty / loading states
// ═════════════════════════════════════════════════════════════════════════

class _EmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        decoration: JT.card(context),
        child: Column(
          children: [
            Icon(icon, size: 28, color: JT.text3(context)),
            const SizedBox(height: 8),
            Text(text,
                textAlign: TextAlign.center,
                style: JT.caption(context, size: 13)),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: JT.surface(context),
                shape: BoxShape.circle,
                border: Border.all(color: JT.border(context)),
              ),
              child: Icon(icon, size: 30, color: JT.text3(context)),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: JT.heading(context, size: 16)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: JT.caption(context, size: 13)),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      );
}

/// Pull-to-refresh friendly wrapper for full-height messages.
class _ScrollableMessage extends StatelessWidget {
  final Widget child;
  const _ScrollableMessage({required this.child});

  @override
  Widget build(BuildContext context) => CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: child),
          ),
        ],
      );
}

class _ReportSkeleton extends StatelessWidget {
  const _ReportSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: JT.card(context, radius: 22),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                JtSkeleton(width: 150, height: 12),
                SizedBox(height: 10),
                JtSkeleton(width: 200, height: 30, radius: 10),
                SizedBox(height: 16),
                JtSkeleton(height: 10, radius: 5),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              JtSkeleton(width: 70, height: 34, radius: 17),
              SizedBox(width: 8),
              JtSkeleton(width: 80, height: 34, radius: 17),
              SizedBox(width: 8),
              JtSkeleton(width: 90, height: 34, radius: 17),
            ],
          ),
          const SizedBox(height: 14),
          const JtSkeleton(height: 54, radius: 16),
          const SizedBox(height: 14),
          const JtSkeleton(height: 150, radius: 18),
          const SizedBox(height: 12),
          const JtSkeleton(height: 110, radius: 18),
        ],
      );
}
