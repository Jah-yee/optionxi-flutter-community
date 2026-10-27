import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:optionxi/Main_Pages/MarketSentiments/act_market_sentiments_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:optionxi/Main_Pages/Indices/act_full_index_page.dart';
import 'package:optionxi/Main_Pages/MarketSentiments/act_market_sentiments.dart';
// NOTE: this is the file that defines `AtlasChartService` and `OhlcvBar`
// (the market-sentiment chart page). Update the path below if the actual
// filename in your project is different — it wasn't given to me directly.

class IndicesGlance extends StatefulWidget {
  const IndicesGlance({super.key});

  @override
  State<IndicesGlance> createState() => _IndicesGlanceState();
}

class _IndicesGlanceState extends State<IndicesGlance>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> indices = [];
  bool loading = true;
  String? error;
  RealtimeChannel? _channel;

  // For infinite / ticker scroll
  late ScrollController _scrollController;
  Timer? _autoScrollTimer;
  bool _userInteracting = false;

  // Adjustable ticker speed (px moved per 30ms tick). Tap the speed pill
  // to cycle through these.
  static const List<double> _speedLevels = [0.35, 0.7, 1.2, 2.0];
  static const List<String> _speedLabels = ['0.5x', '1x', '1.5x', '2x'];
  int _speedIndex = 1;

  // Track flashing indices for price change animation
  final Map<String, AnimationController> _flashControllers = {};
  final Map<String, Color?> _lastColors = {};
  Map<String, double> _previousLtps = {};

  // Only these indices have OHLCV history to chart in the detail sheet.
  static const Map<String, String> _chartSymbolMap = {
    'NIFTY50': 'NIFTY',
    'NIFTYBANK': 'BANKNIFTY',
  };

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onUserScroll);
    fetchIndices();
    setupRealtimeSubscription();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.removeListener(_onUserScroll);
    _scrollController.dispose();
    for (final c in _flashControllers.values) {
      c.dispose();
    }
    _channel?.unsubscribe();
    super.dispose();
  }

  void _onUserScroll() {
    if (_scrollController.position.isScrollingNotifier.value) {
      _userInteracting = true;
      _autoScrollTimer?.cancel();
      _autoScrollTimer = Timer(const Duration(seconds: 3), () {
        _userInteracting = false;
        _startAutoScroll();
      });
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (_userInteracting) return;
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final current = _scrollController.offset;
      if (max <= 0) return;
      double next = current + _speedLevels[_speedIndex];
      if (next >= max) next = 0;
      _scrollController.jumpTo(next);
    });
  }

  void _cycleSpeed() {
    setState(() {
      _speedIndex = (_speedIndex + 1) % _speedLevels.length;
    });
  }

  Future<void> fetchIndices() async {
    try {
      final data = await Supabase.instance.client
          .from('live_nifty_indices')
          .select('symbol, ltp, pcnt, l, h, pc')
          .inFilter('symbol',
              ['NIFTY50', 'NIFTYBANK', 'INDIAVIX', 'NIFTYIT', 'NIFTYMIDCAP50']);

      if (mounted) {
        final newList = List<Map<String, dynamic>>.from(data);

        for (final item in newList) {
          final sym = item['symbol'] as String;
          final newLtp = (item['ltp'] as num).toDouble();

          if (_previousLtps.containsKey(sym)) {
            final oldLtp = _previousLtps[sym]!;
            if (newLtp != oldLtp) {
              _triggerFlash(sym, newLtp > oldLtp);
            }
          }
          _previousLtps[sym] = newLtp;
        }

        setState(() {
          indices = newList;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Failed to load indices';
        });
      }
    }
  }

  void _triggerFlash(String symbol, bool isUp) {
    _flashControllers[symbol]?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flashControllers[symbol] = ctrl;
    _lastColors[symbol] = isUp ? Colors.green : Colors.red;
    ctrl.forward().then((_) {
      if (mounted) setState(() => _lastColors[symbol] = null);
    });
    setState(() {});
  }

  void setupRealtimeSubscription() {
    _channel = Supabase.instance.client
        .channel('indices_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_nifty_indices',
          callback: (payload) => fetchIndices(),
        )
        .subscribe();
  }

  String _getDisplayName(String symbol) {
    switch (symbol) {
      case 'NIFTY50':
        return 'NIFTY 50';
      case 'NIFTYBANK':
        return 'BANK NIFTY';
      case 'INDIAVIX':
        return 'INDIA VIX';
      case 'NIFTYIT':
        return 'NIFTY IT';
      case 'NIFTYMIDCAP50':
        return 'MIDCAP 50';
      default:
        return symbol;
    }
  }

  String _getShortName(String symbol) {
    switch (symbol) {
      case 'NIFTY50':
        return 'NIFTY 50';
      case 'NIFTYBANK':
        return 'BANK NIFTY';
      case 'INDIAVIX':
        return 'INDIA VIX';
      case 'NIFTYIT':
        return 'NIFTY IT';
      case 'NIFTYMIDCAP50':
        return 'MIDCAP 50';
      default:
        return symbol.substring(0, symbol.length.clamp(0, 4));
    }
  }

  String _formatLtp(double v) {
    if (v >= 10000) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  Widget _buildSentimentSliver(bool isDark) {
    if (indices.isEmpty) return const SizedBox.shrink();

    final total = indices.length;
    final bullish = indices.where((i) => (i['pcnt'] as num) >= 0).length;
    final bearish = total - bullish;
    final bullishRatio = total > 0 ? bullish / total : 0.5;

    final upColor = isDark ? const Color(0xFF00D4AA) : const Color(0xFF00897B);
    final downColor =
        isDark ? const Color(0xFFFF5C5C) : const Color(0xFFD32F2F);
    final labelColor =
        isDark ? const Color(0xFF5A6175) : const Color(0xFF9BA4B5);

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$bullish Bullish',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: upColor,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                'Sentiment',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '$bearish Bearish',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: downColor,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [upColor, downColor],
                stops: [bullishRatio, bullishRatio],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTickerStrip(isDark),
        if (!loading && error == null)
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FullIndicesPage()),
              );
            },
            child: _buildSentimentSliver(isDark),
          ),
      ],
    );
  }

  // ── ticker tape ─────────────────────────────────────────────────────────
  Widget _buildTickerStrip(bool isDark) {
    if (loading) {
      return SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: isDark ? Colors.tealAccent : Colors.teal,
            ),
          ),
        ),
      );
    }

    if (error != null) {
      return SizedBox(
        height: 40,
        child: Center(
          child: Text(
            error!,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: isDark ? Colors.red[300] : Colors.red[600],
            ),
          ),
        ),
      );
    }

    final displayList = [...indices, ...indices, ...indices];
    final trackColor =
        isDark ? const Color(0xFF0F1117) : const Color(0xFFF7F8FA);

    return Stack(
      alignment: Alignment.centerRight,
      children: [
        Container(
          color: trackColor,
          child: GestureDetector(
            onHorizontalDragStart: (_) {
              _userInteracting = true;
              _autoScrollTimer?.cancel();
            },
            onHorizontalDragEnd: (_) {
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) {
                  _userInteracting = false;
                  _startAutoScroll();
                }
              });
            },
            child: SizedBox(
              height: 40,
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(left: 12, right: 60),
                itemCount: displayList.length,
                itemBuilder: (context, idx) {
                  final index = displayList[idx % indices.length];
                  return _buildTickerItem(context, index, isDark);
                },
              ),
            ),
          ),
        ),
        // Positioned(
        //   right: 6,
        //   child: _SpeedPill(
        //     label: _speedLabels[_speedIndex],
        //     isDark: isDark,
        //     onTap: _cycleSpeed,
        //   ),
        // ),
      ],
    );
  }

  Widget _buildTickerItem(
      BuildContext context, Map<String, dynamic> index, bool isDark) {
    final symbol = index['symbol'] as String;
    final ltp = (index['ltp'] as num).toDouble();
    final pcnt = (index['pcnt'] as num).toDouble();
    final high = (index['h'] as num?)?.toDouble();
    final low = (index['l'] as num?)?.toDouble();
    final previousClose = (index['pc'] as num?)?.toDouble() ?? ltp;
    final isPositive = pcnt >= 0;
    final change = ltp - previousClose;

    final upColor = isDark ? const Color(0xFF00D4AA) : const Color(0xFF00897B);
    final downColor =
        isDark ? const Color(0xFFFF5C5C) : const Color(0xFFD32F2F);
    final accentColor = isPositive ? upColor : downColor;
    final valueColor =
        isDark ? const Color(0xFFEAEDF3) : const Color(0xFF131722);
    final labelColor =
        isDark ? const Color(0xFF5A6175) : const Color(0xFF9BA4B5);
    final dividerColor =
        isDark ? const Color(0xFF1E2230) : const Color(0xFFE2E6ED);

    final flashColor = _lastColors[symbol];
    final flashCtrl = _flashControllers[symbol];

    return AnimatedBuilder(
      animation: flashCtrl ?? kAlwaysCompleteAnimation,
      builder: (context, _) {
        double overlayOpacity = 0.0;
        if (flashColor != null && flashCtrl != null) {
          overlayOpacity = (1 - flashCtrl.value) * 0.18;
        }
        return Material(
          color: flashColor != null
              ? flashColor.withOpacity(overlayOpacity)
              : Colors.transparent,
          child: InkWell(
            onTap: () => _openDetail(
              symbol: symbol,
              displayName: _getDisplayName(symbol),
              ltp: ltp,
              pcnt: pcnt,
              change: change,
              isPositive: isPositive,
              high: high,
              low: low,
              previousClose: previousClose,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getShortName(symbol),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                      fontFamily: 'monospace',
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatLtp(ltp),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: valueColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    isPositive
                        ? Icons.arrow_drop_up_rounded
                        : Icons.arrow_drop_down_rounded,
                    size: 16,
                    color: accentColor,
                  ),
                  Text(
                    '${isPositive ? '+' : ''}${pcnt.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 16, color: dividerColor),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openDetail({
    required String symbol,
    required String displayName,
    required double ltp,
    required double pcnt,
    required double change,
    required bool isPositive,
    double? high,
    double? low,
    double? previousClose,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _IndexDetailSheet(
        symbol: symbol,
        displayName: displayName,
        ltp: ltp,
        pcnt: pcnt,
        change: change,
        isPositive: isPositive,
        high: high,
        low: low,
        previousClose: previousClose,
        chartSymbolMap: _chartSymbolMap,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Speed pill overlay
// ═════════════════════════════════════════════════════════════════════════════
class _SpeedPill extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _SpeedPill(
      {required this.label, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg =
        isDark ? Colors.black.withOpacity(0.55) : Colors.white.withOpacity(0.9);
    final fg = isDark ? const Color(0xFF00D4AA) : const Color(0xFF00897B);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fg.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed_rounded, size: 11, color: fg),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: fg,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Bottom sheet: index detail + chart (NIFTY / BANKNIFTY only)
// ═════════════════════════════════════════════════════════════════════════════
class _IndexDetailSheet extends StatefulWidget {
  final String symbol;
  final String displayName;
  final double ltp;
  final double pcnt;
  final double change;
  final bool isPositive;
  final double? high;
  final double? low;
  final double? previousClose;
  final Map<String, String> chartSymbolMap;

  const _IndexDetailSheet({
    required this.symbol,
    required this.displayName,
    required this.ltp,
    required this.pcnt,
    required this.change,
    required this.isPositive,
    required this.chartSymbolMap,
    this.high,
    this.low,
    this.previousClose,
  });

  @override
  State<_IndexDetailSheet> createState() => _IndexDetailSheetState();
}

class _IndexDetailSheetState extends State<_IndexDetailSheet> {
  bool get _hasChart => widget.chartSymbolMap.containsKey(widget.symbol);

  List<OhlcvBar>? _bars;
  bool _loading = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    if (_hasChart) _fetchChart();
  }

  // Last 75 five-minute bars = one full trading session (9:15-15:30).
  // Fetching by count instead of a calendar date means weekends/holidays
  // just show the last session that actually has data, with no gap.
  static const int _barCount = 75;

  Future<void> _fetchChart() async {
    setState(() {
      _loading = true;
      _fetchError = null;
    });
    try {
      final mapped = widget.chartSymbolMap[widget.symbol]!;
      final data = await Supabase.instance.client
          .from('nifty_ohlcv')
          .select('ts,open,high,low,close,volume')
          .eq('symbol', mapped)
          .order('ts', ascending: false)
          .limit(_barCount);
      final bars = (data as List)
          .map((e) => OhlcvBar.fromJson(e as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
      if (!mounted) return;
      setState(() {
        _bars = bars;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchError = 'Could not load the chart';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isPositive ? SX.bull : SX.bear;
    final h = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.85),
      decoration: BoxDecoration(
        color: context.sxSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.sxBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.displayName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: context.sxTextP,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.ltp.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: context.sxTextP,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isPositive
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 14,
                          color: accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.change.abs().toStringAsFixed(1)} (${widget.pcnt.abs().toStringAsFixed(2)}%)',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.high != null ||
                  widget.low != null ||
                  widget.previousClose != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (widget.high != null)
                      _StatChip(
                          label: 'High',
                          value: widget.high!.toStringAsFixed(2)),
                    if (widget.high != null) const SizedBox(width: 10),
                    if (widget.low != null)
                      _StatChip(
                          label: 'Low', value: widget.low!.toStringAsFixed(2)),
                    if (widget.low != null) const SizedBox(width: 10),
                    if (widget.previousClose != null)
                      _StatChip(
                          label: 'Prev close',
                          value: widget.previousClose!.toStringAsFixed(2)),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              if (_hasChart)
                _buildChartSection(context)
              else
                _buildNoChartNotice(context),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FullIndicesPage()),
                    );
                  },
                  icon: const Icon(Icons.grid_view_rounded, size: 16),
                  label: const Text('View all indices'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: context.sxBorder),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartSection(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(color: SX.accent)),
      );
    }
    if (_fetchError != null || _bars == null || _bars!.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            _fetchError ?? 'No chart data for today yet',
            style: TextStyle(fontSize: 12.5, color: context.sxTextS),
          ),
        ),
      );
    }

    final grid = context.sxTextS.withOpacity(0.18);
    final label = context.sxTextS;

    return SizedBox(
      height: 220,
      child: SfCartesianChart(
        backgroundColor: Colors.transparent,
        plotAreaBorderWidth: 0,
        legend: const Legend(isVisible: false),
        tooltipBehavior: TooltipBehavior(enable: true),
        trackballBehavior: TrackballBehavior(
          enable: true,
          activationMode: ActivationMode.singleTap,
          tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
        ),
        // DateTimeCategoryAxis plots bars back-to-back by index rather than
        // by elapsed time, so there's no stretch of empty axis for the
        // overnight gap or a weekend between sessions.
        primaryXAxis: DateTimeCategoryAxis(
          dateFormat: DateFormat('h:mm a'),
          axisLine: AxisLine(width: 0.5, color: grid),
          majorGridLines: MajorGridLines(width: 0.3, color: grid),
          // minorGridLines: const MinorGridLines(width: 0),
          labelStyle: TextStyle(fontSize: 10, color: label),
          labelIntersectAction: AxisLabelIntersectAction.hide,
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
            dataSource: _bars!,
            xValueMapper: (b, _) => b.ts,
            openValueMapper: (b, _) => b.open,
            highValueMapper: (b, _) => b.high,
            lowValueMapper: (b, _) => b.low,
            closeValueMapper: (b, _) => b.close,
            bullColor: SX.bull,
            bearColor: SX.bear,
            enableSolidCandles: true,
            animationDuration: 350,
            name: 'Price',
          ),
        ],
      ),
    );
  }

  Widget _buildNoChartNotice(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.sxBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.sxBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.show_chart_rounded, size: 18, color: context.sxTextS),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Intraday chart is available for Nifty 50 and Bank Nifty only.',
              style: TextStyle(fontSize: 12.5, color: context.sxTextS),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: context.sxTextS)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.sxTextP,
            ),
          ),
        ],
      ),
    );
  }
}
