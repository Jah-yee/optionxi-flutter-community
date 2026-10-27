import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:optionxi/Main_Pages/Achivements/fastapi_achivement.dart';
import 'package:optionxi/Main_Pages/Sectorwise/act_sectorwise_stocks.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _T {
  static const bullishDark = Color(0xFF00D4A8);
  static const bullishLight = Color(0xFF00897B);
  static const bearishDark = Color(0xFFFF5C72);
  static const bearishLight = Color(0xFFD32F2F);
  static const fireDark = Color(0xFFFFB020);
  static const fireLight = Color(0xFFEF6C00);

  static const surfaceDark = Color(0xFF0D1117);
  static const cardDark = Color(0xFF161B22);
  static const elevatedDark = Color(0xFF1C2230);
  static const borderDark = Color(0xFF21262D);

  static const surfaceLight = Color(0xFFF6F7FA);
  static const cardLight = Color(0xFFFFFFFF);
  static const elevatedLight = Color(0xFFEFF3F8);
  static const borderLight = Color(0xFFE4E8EF);

  static const p1Dark = Color(0xFFE6EDF3);
  static const p2Dark = Color(0xFF8B949E);
  static const p3Dark = Color(0xFF484F58);

  static const p1Light = Color(0xFF0D1117);
  static const p2Light = Color(0xFF57606A);
  static const p3Light = Color(0xFFAFB8C1);

  static const rSm = 10.0;
  static const r = 14.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model — maps 1:1 onto the `sector_summary` table
// ─────────────────────────────────────────────────────────────────────────────
class SectorSummary {
  final String sector;
  final int stockCount;
  final int advancingCount;
  final int decliningCount;
  final double advancingPct;
  final double avgPcnt;
  final double medianPcnt;
  final double? volumeSurgeRatio;
  final double trendScore;
  final int? trendRank;
  final bool isTrending;
  final DateTime? updatedAt;

  const SectorSummary({
    required this.sector,
    required this.stockCount,
    required this.advancingCount,
    required this.decliningCount,
    required this.advancingPct,
    required this.avgPcnt,
    required this.medianPcnt,
    required this.volumeSurgeRatio,
    required this.trendScore,
    required this.trendRank,
    required this.isTrending,
    required this.updatedAt,
  });

  factory SectorSummary.fromJson(Map<String, dynamic> j) {
    double _d(dynamic v) => v == null ? 0.0 : (v as num).toDouble();
    int _i(dynamic v) => v == null ? 0 : (v as num).toInt();

    return SectorSummary(
      sector: (j['sec'] ?? 'Others') as String,
      stockCount: _i(j['stock_count']),
      advancingCount: _i(j['advancing_count']),
      decliningCount: _i(j['declining_count']),
      advancingPct: _d(j['advancing_pct']),
      avgPcnt: _d(j['avg_pcnt']),
      medianPcnt: _d(j['median_pcnt']),
      volumeSurgeRatio:
          j['volume_surge_ratio'] == null ? null : _d(j['volume_surge_ratio']),
      trendScore: _d(j['trend_score']),
      trendRank: j['trend_rank'] == null ? null : _i(j['trend_rank']),
      isTrending: (j['is_trending'] ?? false) as bool,
      updatedAt:
          j['updated_at'] == null ? null : DateTime.tryParse(j['updated_at']),
    );
  }

  // trend_score is a roughly-normal composite z-score (typically -3..3).
  // Squash it into an easy-to-read 0-100 "momentum" number for the UI.
  double get momentumPct => (1 / (1 + exp(-trendScore))) * 100;

  bool get isUp => medianPcnt >= 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────
class SectorAnalysisPage extends StatefulWidget {
  const SectorAnalysisPage({Key? key}) : super(key: key);

  @override
  State<SectorAnalysisPage> createState() => _SectorAnalysisPageState();
}

class _SectorAnalysisPageState extends State<SectorAnalysisPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseClient _supabase = Supabase.instance.client;

  List<SectorSummary> _allSectors = [];
  List<SectorSummary> _rising = [];
  List<SectorSummary> _falling = [];
  List<SectorSummary> _topTrending = [];
  bool _isLoading = true;
  bool _isNavigating = false;
  String? _error;
  bool _overviewExpanded = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
    AchievementEvents.openedSectorPulse();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Theme helpers ────────────────────────────────────────────────────────
  bool get _dark => Theme.of(context).brightness == Brightness.dark;

  Color get _bull => _dark ? _T.bullishDark : _T.bullishLight;
  Color get _bear => _dark ? _T.bearishDark : _T.bearishLight;
  Color get _fire => _dark ? _T.fireDark : _T.fireLight;

  Color get _surface => _dark ? _T.surfaceDark : _T.surfaceLight;
  Color get _card => _dark ? _T.cardDark : _T.cardLight;
  Color get _elevated => _dark ? _T.elevatedDark : _T.elevatedLight;
  Color get _border => _dark ? _T.borderDark : _T.borderLight;

  Color get _t1 => _dark ? _T.p1Dark : _T.p1Light;
  Color get _t2 => _dark ? _T.p2Dark : _T.p2Light;
  Color get _t3 => _dark ? _T.p3Dark : _T.p3Light;

  Color _accentFor(bool isUp) => isUp ? _bull : _bear;

  // ─── Data ─────────────────────────────────────────────────────────────────
  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _supabase
          .from('sector_summary')
          .select()
          .order('trend_score', ascending: false);

      final data = response as List<dynamic>;
      final sectors = data
          .map((e) => SectorSummary.fromJson(e as Map<String, dynamic>))
          .toList();

      final rising = sectors.where((s) => s.isUp).toList()
        ..sort((a, b) => b.trendScore.compareTo(a.trendScore));
      final falling = sectors.where((s) => !s.isUp).toList()
        ..sort((a, b) => a.trendScore.compareTo(b.trendScore));
      final top = sectors.where((s) => s.isTrending).toList()
        ..sort((a, b) => (a.trendRank ?? 999).compareTo(b.trendRank ?? 999));

      setState(() {
        _allSectors = sectors;
        _rising = rising;
        _falling = falling;
        _topTrending = top;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openSector(SectorSummary sector) async {
    HapticFeedback.selectionClick();
    setState(() => _isNavigating = true);
    try {
      final response = await _supabase
          .from('generated_values')
          .select(
              'stckname, pcnt, close, high, low, open, vol, sec, rsi14, ema20, sma20')
          .eq('sec', sector.sector);

      final data = response as List<dynamic>;
      final stocks = data
          .map((e) => StockData.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() => _isNavigating = false);
      Get.to(() => SectorStocksPage(sectorName: sector.sector, stocks: stocks));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isNavigating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load ${sector.sector}: $e')),
      );
    }
  }

  // ─── Root build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: Stack(
        children: [
          if (_isLoading)
            SafeArea(child: _buildSkeleton())
          else if (_error != null)
            SafeArea(child: _buildError())
          else
            NestedScrollView(
              headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
                _buildSliverAppBar(innerBoxIsScrolled),
                SliverToBoxAdapter(child: _buildOverviewSection()),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedHeaderDelegate(
                    height: 52,
                    child: _buildTabBar(),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildList(_rising, isUp: true),
                  _buildList(_falling, isUp: false),
                ],
              ),
            ),
          if (_isNavigating)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  // ─── Collapsing top bar (the "sliver" everyone asked for) ─────────────────
  Widget _buildSliverAppBar(bool isScrolled) {
    return SliverAppBar(
      pinned: true,
      floating: true,
      snap: true,
      backgroundColor: _card,
      surfaceTintColor: Colors.transparent,
      elevation: isScrolled ? 1 : 0,
      shadowColor: Colors.black.withOpacity(0.08),
      toolbarHeight: 58,
      titleSpacing: 2,
      leadingWidth: 50,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: _iconBtn(Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.of(context).maybePop()),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Sector Pulse',
            style: TextStyle(
              color: _t1,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          Text(
            'Trending sectors',
            style: TextStyle(
                color: _t2, fontSize: 11, fontWeight: FontWeight.w400),
          ),
        ],
      ),
      actions: [
        _buildMoodPill(),
        const SizedBox(width: 8),
        _iconBtn(Icons.refresh_rounded, onTap: () {
          HapticFeedback.lightImpact();
          _fetchData();
        }),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _iconBtn(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        // decoration: BoxDecoration(
        //   color: _elevated,
        //   borderRadius: BorderRadius.circular(_T.rSm),
        //   border: Border.all(color: _border),
        // ),
        child: Icon(icon, size: 15, color: _t2),
      ),
    );
  }

  Widget _buildMoodPill() {
    final total = _rising.length + _falling.length;
    if (total == 0) return const SizedBox.shrink();
    final upPct = (_rising.length / total * 100).round();
    final downPct = 100 - upPct;
    final isUpDominant = upPct >= downPct;
    final dominantPct = isUpDominant ? upPct : downPct;
    final c = isUpDominant ? _bull : _bear;
    final label = isUpDominant ? 'Mostly up' : 'Mostly down';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text('$label · $dominantPct%',
              style: TextStyle(
                  color: c, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ─── Market overview (tap to collapse, kept out of the main scroll) ───────
  Widget _buildOverviewSection() {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _overviewExpanded = !_overviewExpanded);
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _elevated,
              borderRadius: BorderRadius.circular(_T.r),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Icon(
                  _overviewExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: _t2,
                ),
                const SizedBox(width: 6),
                Icon(Icons.insights_rounded, size: 14, color: _bull),
                const SizedBox(width: 6),
                Text('Market overview',
                    style: TextStyle(
                        color: _t1, fontSize: 12, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (!_overviewExpanded) ...[
                  _miniStat('${_rising.length} up', _bull),
                  const SizedBox(width: 6),
                  _miniStat('${_falling.length} down', _bear),
                ],
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: _overviewExpanded
              ? Column(
                  children: [
                    _buildBreadthBar(),
                    if (_topTrending.isNotEmpty) _buildTrendingStrip(),
                    const SizedBox(height: 4),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _miniStat(String label, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style:
                TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
      );

  // ─── Breadth bar ──────────────────────────────────────────────────────────
  Widget _buildBreadthBar() {
    final total = (_rising.length + _falling.length).toDouble();
    if (total == 0) return const SizedBox.shrink();
    final upRatio = _rising.length / total;
    final upPct = (upRatio * 100).round();
    final downPct = 100 - upPct;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(_T.r),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, size: 12, color: _bull),
              const SizedBox(width: 4),
              Text('${_rising.length} up',
                  style: TextStyle(
                      color: _bull, fontSize: 11, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$upPct% ↑  ·  $downPct% ↓',
                  style: TextStyle(
                      color: _t2, fontSize: 11, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${_falling.length} down',
                  style: TextStyle(
                      color: _bear, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(Icons.trending_down_rounded, size: 12, color: _bear),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: upRatio),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (ctx, v, _) => Stack(
                children: [
                  Container(height: 6, color: _bear.withOpacity(0.25)),
                  FractionallySizedBox(
                    widthFactor: v.clamp(0.0, 1.0),
                    child: Container(height: 6, color: _bull),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Trending strip ───────────────────────────────────────────────────────
  Widget _buildTrendingStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department_rounded, size: 14, color: _fire),
              const SizedBox(width: 5),
              Text('Hot right now',
                  style: TextStyle(
                      color: _t1, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _topTrending.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final s = _topTrending[i];
                final c = _accentFor(s.isUp);
                return GestureDetector(
                  onTap: () => _openSector(s),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.withOpacity(0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('#${s.trendRank ?? i + 1}',
                            style: TextStyle(
                                color: _fire,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        Text(s.sector,
                            style: TextStyle(
                                color: _t1,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text(
                          '${s.isUp ? '+' : ''}${s.medianPcnt.toStringAsFixed(1)}%',
                          style: TextStyle(
                              color: c,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab bar (pinned under the app bar) ────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: _elevated,
          borderRadius: BorderRadius.circular(_T.r),
          border: Border.all(color: _border),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(_T.r - 2),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_dark ? 0.3 : 0.07),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(3),
          dividerColor: Colors.transparent,
          labelPadding: EdgeInsets.zero,
          labelColor: _t1,
          unselectedLabelColor: _t2,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 12.5),
          tabs: [
            _tab('Going up', Icons.trending_up_rounded, _rising.length, _bull),
            _tab('Going down', Icons.trending_down_rounded, _falling.length,
                _bear),
          ],
        ),
      ),
    );
  }

  Tab _tab(String label, IconData icon, int count, Color c) => Tab(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 5),
            Text(label),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: c.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: c, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  // ─── Sector list (slim rows) ───────────────────────────────────────────────
  Widget _buildList(List<SectorSummary> sectors, {required bool isUp}) {
    if (sectors.isEmpty) return _buildEmpty(isUp);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: sectors.length,
      itemBuilder: (ctx, i) => _buildCard(sectors[i]),
    );
  }

  Widget _buildCard(SectorSummary s) {
    final accent = _accentFor(s.isUp);
    final momentum = (s.momentumPct / 100).clamp(0.0, 1.0);
    final busy = (s.volumeSurgeRatio ?? 0) >= 1.3;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_T.r),
        child: InkWell(
          onTap: () => _openSector(s),
          borderRadius: BorderRadius.circular(_T.r),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(_T.r),
              border: Border.all(
                color: s.isTrending ? _fire.withOpacity(0.5) : _border,
                width: s.isTrending ? 1.3 : 1,
              ),
            ),
            child: Row(
              children: [
                // Little vector "sparkline" glyph — drawn in code, no image asset needed.
                CustomPaint(
                  size: const Size(34, 34),
                  painter: _TrendGlyphPainter(
                      color: accent, momentum: momentum, isUp: s.isUp),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              s.sector,
                              style: TextStyle(
                                color: _t1,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (s.isTrending) ...[
                            const SizedBox(width: 5),
                            Icon(Icons.local_fire_department_rounded,
                                size: 12, color: _fire),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${s.stockCount} stocks · ${s.advancingCount} up, ${s.decliningCount} down${busy ? ' · busy trading' : ''}',
                        style: TextStyle(
                            color: _t2,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${s.isUp ? '+' : ''}${s.medianPcnt.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: accent,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(momentum * 100).toStringAsFixed(0)}% strength',
                      style: TextStyle(color: _t3, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────
  Widget _buildEmpty(bool isUp) {
    final c = _accentFor(isUp);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: c.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.withOpacity(0.2)),
            ),
            child: Icon(
                isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 28,
                color: c),
          ),
          const SizedBox(height: 18),
          Text('No sectors ${isUp ? 'going up' : 'going down'} today',
              style: TextStyle(
                  color: _t1, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Check back once the market moves\nmore clearly one way.',
              style: TextStyle(color: _t2, fontSize: 12.5),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ─── Error state ──────────────────────────────────────────────────────────
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _bear.withOpacity(0.1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _bear.withOpacity(0.3)),
              ),
              child: Icon(Icons.cloud_off_rounded, color: _bear, size: 26),
            ),
            const SizedBox(height: 18),
            Text('Something went wrong',
                style: TextStyle(
                    color: _t1, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(_error ?? 'Unknown error',
                style: TextStyle(color: _t2, fontSize: 12.5),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _fetchData,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                decoration: BoxDecoration(
                  color: _bull,
                  borderRadius: BorderRadius.circular(_T.r),
                ),
                child: Text('Try again',
                    style: TextStyle(
                        color: _dark ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Skeleton ─────────────────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return Column(
      children: [
        _skel(margin: const EdgeInsets.fromLTRB(16, 12, 16, 0), height: 58),
        _skel(margin: const EdgeInsets.fromLTRB(16, 10, 16, 0), height: 40),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: 7,
            itemBuilder: (_, i) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(_T.r),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  _skel(width: 34, height: 34, r: 17),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _skel(width: 120, height: 14),
                        const SizedBox(height: 6),
                        _skel(width: 160, height: 11),
                      ],
                    ),
                  ),
                  _skel(width: 48, height: 14),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _skel({
    double? width,
    double? height,
    double r = _T.r,
    EdgeInsets margin = EdgeInsets.zero,
  }) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: _dark ? const Color(0xFF21262D) : const Color(0xFFE8EDF3),
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A tiny vector "trend" glyph, drawn with CustomPainter — gives each row a
// crisp, scalable SVG-style icon without shipping an image asset.
// ─────────────────────────────────────────────────────────────────────────────
class _TrendGlyphPainter extends CustomPainter {
  final Color color;
  final double momentum; // 0..1, unused for shape but kept for future tuning
  final bool isUp;

  _TrendGlyphPainter(
      {required this.color, required this.momentum, required this.isUp});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
        center, size.width / 2, Paint()..color = color.withOpacity(0.12));

    final w = size.width;
    final h = size.height;
    final start = Offset(w * 0.26, isUp ? h * 0.68 : h * 0.32);
    final end = Offset(w * 0.74, isUp ? h * 0.30 : h * 0.70);
    final mid = Offset(w * 0.5, isUp ? h * 0.58 : h * 0.42);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // arrowhead at the end of the line
    final angle = (end - mid).direction;
    const arrowLen = 4.0;
    final p1 =
        end - Offset(cos(angle - 0.5) * arrowLen, sin(angle - 0.5) * arrowLen);
    final p2 =
        end - Offset(cos(angle + 0.5) * arrowLen, sin(angle + 0.5) * arrowLen);
    canvas.drawLine(end, p1, linePaint);
    canvas.drawLine(end, p2, linePaint);
  }

  @override
  bool shouldRepaint(covariant _TrendGlyphPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.isUp != isUp ||
      oldDelegate.momentum != momentum;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pinned sliver header helper (used for the tab bar)
// ─────────────────────────────────────────────────────────────────────────────
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  _PinnedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
