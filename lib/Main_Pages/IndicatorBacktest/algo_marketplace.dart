// ─────────────────────────────────────────────────────────────────────────
// Community Algos — browse publicly shared backtest setups, view one in
// detail, and optionally save ("clone") it into your own saved algos.
//
// Reads/writes `community_algos` directly via Supabase — no Firebase auth
// required to browse or publish. Saving a copy into the user's own algos
// still goes through BacktestApiService (which IS Firebase-authenticated,
// since that's writing to *their* saved algos).
//
// Wire up from SavedBacktestsPage's `_browseMajorAlgos`:
//
//   Future<void> _browseMajorAlgos() async {
//     final saved = await Navigator.push<bool>(context, MaterialPageRoute(
//       builder: (_) => CommunityAlgosBrowsePage(api: _api),
//     ));
//     if (saved == true) _load();
//   }
//
// Requires: flutter_svg (for the inline icon set below).
// ─────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:optionxi/Main_Pages/IndicatorBacktest/indicator-backtest.dart';

const String kCommunityAlgosTable = 'community_algos';

// ─────────────────────────────────────────────
// DESIGN TOKENS — flat, quiet, professional.
// One accent, hairline borders, generous spacing.
// Green/red keep their trading meaning; amber = featured only.
// ─────────────────────────────────────────────
class _T {
  static const accent = Color(0xFF2F6BFF);
  static const green = Color(0xFF0E9F6E);
  static const red = Color(0xFFE5484D);
  static const amber = Color(0xFFD97706);

  static Color bg(bool d) =>
      d ? const Color(0xFF0C0E12) : const Color(0xFFF5F6F8);
  static Color surface(bool d) => d ? const Color(0xFF14171D) : Colors.white;
  static Color surface2(bool d) =>
      d ? const Color(0xFF1C2028) : const Color(0xFFEFF1F5);
  static Color border(bool d) =>
      d ? const Color(0xFF242932) : const Color(0xFFE5E7EC);
  static Color text(bool d) =>
      d ? const Color(0xFFEDEFF3) : const Color(0xFF101318);
  static Color sub(bool d) =>
      d ? const Color(0xFF8A93A3) : const Color(0xFF5F6875);

  // Overline label — small, tracked-out, muted. Used for field labels.
  static TextStyle overline(bool d, {Color? color}) => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: color ?? sub(d),
      );
}

Color _hitRateColor(double? hr, bool dark) {
  if (hr == null) return _T.sub(dark);
  if (hr >= 60) return _T.green;
  if (hr >= 40) return _T.amber;
  return _T.red;
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays}d ago';
  if (d.inDays < 365) return '${d.inDays ~/ 30}mo ago';
  return '${d.inDays ~/ 365}y ago';
}

// ─────────────────────────────────────────────
// INLINE SVG ICON SET — 24×24, stroke-based.
// Recolored via colorFilter, so "black" below is just a placeholder.
// ─────────────────────────────────────────────
class _I {
  static const bookmark =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21l-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg>';
  static const trendingUp =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17l6-6 4 4 8-8"/><path d="M14 7h7v7"/></svg>';
  static const trendingDown =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7l6 6 4-4 8 8"/><path d="M14 17h7v-7"/></svg>';
  static const target =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.2" fill="black"/></svg>';
  static const users =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.2 3.4-5 6.5-5s5.7 1.8 6.5 5"/><circle cx="17.5" cy="9" r="2.5"/><path d="M16.5 15.2c2.6.3 4.4 1.9 5 4.3"/></svg>';
  static const calendar =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M8 3v4M16 3v4M3 10h18"/></svg>';
  static const clock =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/></svg>';
  static const chart =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4v3M7 17v3"/><rect x="4.5" y="7" width="5" height="10" rx="1"/><path d="M17 2v3M17 13v3"/><rect x="14.5" y="5" width="5" height="8" rx="1"/></svg>';
  static const award =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="9" r="6"/><path d="M8.5 14L7 22l5-3 5 3-1.5-8"/></svg>';
  static const download =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="M7 11l5 5 5-5"/><path d="M4 20h16"/></svg>';
  static const check =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12.5l5 5L20 6.5"/></svg>';
  static const alert =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5"/><circle cx="12" cy="16.8" r="0.4" fill="black"/></svg>';
  static const searchEmpty =
      '<svg viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/><path d="M8.5 11h5"/></svg>';
}

Widget _svg(String raw, Color color, {double size = 18}) => SvgPicture.string(
      raw,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );

// ─────────────────────────────────────────────
// TOAST — quiet pill, icon + one line, top-anchored feel via margin
// ─────────────────────────────────────────────
void _toast(BuildContext context, String msg, {required bool ok}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: (ok ? _T.green : _T.red).withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Center(
            child: _svg(ok ? _I.check : _I.alert, ok ? _T.green : _T.red,
                size: 12)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(msg,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFEDEFF3))),
      ),
    ]),
    backgroundColor: const Color(0xFF1B1E26),
    behavior: SnackBarBehavior.floating,
    elevation: 0,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF2C313C))),
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    duration: const Duration(seconds: 3),
  ));
}

// ─────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────

class CommunityAlgoModel {
  final String id;
  final String creatorName;
  final String? creatorAvatarUrl;
  final String name;
  final String? description;
  final String symbol;
  final int days;
  final String direction;
  final int confirmBars;
  final List<ConditionModel> conditions;
  final double? hitRate;
  final int? matchedBars;
  final int? confirmed;
  final int? failed;
  final int? totalBars;
  final int cloneCount;
  final bool isFeatured;
  final DateTime createdAt;

  CommunityAlgoModel({
    required this.id,
    required this.creatorName,
    this.creatorAvatarUrl,
    required this.name,
    this.description,
    required this.symbol,
    required this.days,
    required this.direction,
    required this.confirmBars,
    required this.conditions,
    this.hitRate,
    this.matchedBars,
    this.confirmed,
    this.failed,
    this.totalBars,
    this.cloneCount = 0,
    this.isFeatured = false,
    required this.createdAt,
  });

  factory CommunityAlgoModel.fromJson(Map<String, dynamic> j) =>
      CommunityAlgoModel(
        id: j['id'].toString(),
        creatorName: j['creator_name'] ?? 'Anonymous',
        creatorAvatarUrl: j['creator_avatar_url'],
        name: j['name'] ?? '',
        description: j['description'],
        symbol: j['symbol'] ?? 'NIFTY',
        days: j['days'] ?? 14,
        direction: j['direction'] ?? 'Bullish',
        confirmBars: j['confirm_bars'] ?? 3,
        conditions: ((j['conditions'] as List?) ?? [])
            .map((c) => ConditionModel.fromJson(Map<String, dynamic>.from(c)))
            .toList(),
        hitRate: (j['hit_rate'] as num?)?.toDouble(),
        matchedBars: j['matched_bars'],
        confirmed: j['confirmed'],
        failed: j['failed'],
        totalBars: j['total_bars'],
        cloneCount: j['clone_count'] ?? 0,
        isFeatured: j['is_featured'] ?? false,
        createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
      );
}

enum _SortMode { featured, topHitRate, mostCloned, newest }

// Plain-English lines for each sort mode's loading state.
String _loadingLabel(_SortMode mode) {
  switch (mode) {
    case _SortMode.featured:
      return 'Finding the algos our team likes best…';
    case _SortMode.topHitRate:
      return 'Sorting algos by how often they\'ve been right…';
    case _SortMode.mostCloned:
      return 'Finding the algos most traders have copied…';
    case _SortMode.newest:
      return 'Fetching the latest algos shared by the community…';
  }
}

String _sortLabel(_SortMode m) {
  switch (m) {
    case _SortMode.featured:
      return 'Featured';
    case _SortMode.topHitRate:
      return 'Top hit rate';
    case _SortMode.mostCloned:
      return 'Most saved';
    case _SortMode.newest:
      return 'Newest';
  }
}

// ─────────────────────────────────────────────
// BROWSE PAGE
// ─────────────────────────────────────────────

class CommunityAlgosBrowsePage extends StatefulWidget {
  final BacktestApiService api;
  const CommunityAlgosBrowsePage({super.key, required this.api});

  @override
  State<CommunityAlgosBrowsePage> createState() =>
      _CommunityAlgosBrowsePageState();
}

class _CommunityAlgosBrowsePageState extends State<CommunityAlgosBrowsePage> {
  List<CommunityAlgoModel> _algos = [];
  bool _loading = true;
  String? _error;
  _SortMode _sort = _SortMode.featured;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = Supabase.instance.client.from(kCommunityAlgosTable).select();
      final PostgrestTransformBuilder<List<Map<String, dynamic>>> sorted;
      switch (_sort) {
        case _SortMode.featured:
          sorted = query
              .order('is_featured', ascending: false)
              .order('hit_rate', ascending: false, nullsFirst: false);
          break;
        case _SortMode.topHitRate:
          sorted = query.order('hit_rate', ascending: false, nullsFirst: false);
          break;
        case _SortMode.mostCloned:
          sorted = query.order('clone_count', ascending: false);
          break;
        case _SortMode.newest:
          sorted = query.order('created_at', ascending: false);
          break;
      }
      final res = await sorted.limit(100);
      if (!mounted) return;
      setState(() {
        _algos = (res as List)
            .map((e) =>
                CommunityAlgoModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetail(CommunityAlgoModel algo) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityAlgoDetailPage(api: widget.api, algo: algo),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    return Scaffold(
      backgroundColor: _T.bg(dark),
      appBar: AppBar(
        backgroundColor: _T.bg(dark),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        title: Text('Community algos',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: _T.text(dark))),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Text(
            'Setups other traders have shared. Open one to see how it works — then save a copy to your own algos in one tap.',
            style: TextStyle(fontSize: 13, height: 1.45, color: _T.sub(dark)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SegmentedSortControl(
            dark: dark,
            selected: _sort,
            onChanged: (m) {
              if (_sort == m) return;
              setState(() => _sort = m);
              _load();
            },
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _loading
              ? _BrowseLoadingState(dark: dark, label: _loadingLabel(_sort))
              : _error != null
                  ? _ErrorState(dark: dark, message: _error!, onRetry: _load)
                  : _algos.isEmpty
                      ? _EmptyState(dark: dark)
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _T.accent,
                          backgroundColor: _T.surface(dark),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
                            itemCount: _algos.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => _CommunityAlgoCard(
                              algo: _algos[i],
                              dark: dark,
                              onTap: () => _openDetail(_algos[i]),
                            ),
                          ),
                        ),
        ),
      ]),
    );
  }
}

// Segmented control for sort — one quiet pill container, animated selection.
class _SegmentedSortControl extends StatelessWidget {
  final bool dark;
  final _SortMode selected;
  final ValueChanged<_SortMode> onChanged;
  const _SegmentedSortControl({
    required this.dark,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _T.surface2(dark),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        for (final m in _SortMode.values) ...[
          if (m != _SortMode.values.first) const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected == m ? _T.surface(dark) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: selected == m
                      ? Border.all(color: _T.border(dark))
                      : Border.all(color: Colors.transparent),
                  boxShadow: selected == m
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(dark ? 0.35 : 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  _sortLabel(m),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected == m ? FontWeight.w700 : FontWeight.w600,
                    color: selected == m ? _T.text(dark) : _T.sub(dark),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final bool dark;
  final String message;
  final VoidCallback onRetry;
  const _ErrorState(
      {required this.dark, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _svg(_I.alert, _T.red, size: 36),
          const SizedBox(height: 14),
          Text('Couldn\'t load community algos',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _T.text(dark))),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.4, color: _T.sub(dark))),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: _T.accent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Try again',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool dark;
  const _EmptyState({required this.dark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _T.accent.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Center(child: _svg(_I.searchEmpty, _T.accent, size: 30)),
          ),
          const SizedBox(height: 16),
          Text('No shared algos yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _T.text(dark))),
          const SizedBox(height: 6),
          Text(
            'When traders publish a setup, it\'ll show up here for everyone to copy.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.45, color: _T.sub(dark)),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// STATIC SKELETON — no animation, quiet placeholder bars.
// ─────────────────────────────────────────────
Widget _skelBar(bool dark, double w, double h, {double r = 6}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: _T.surface2(dark),
        borderRadius: BorderRadius.circular(r),
      ),
    );

// Static loading state for the browse page — a quiet line of context
// plus placeholder cards. No shimmer, no motion.
class _BrowseLoadingState extends StatelessWidget {
  final bool dark;
  final String label;
  const _BrowseLoadingState({required this.dark, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _T.accent),
          ),
          const SizedBox(height: 12),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _T.text(dark))),
          const SizedBox(height: 4),
          Text('Browsing only — nothing here can place trades.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: _T.sub(dark))),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, __) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _T.surface(dark),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _T.border(dark)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _skelBar(dark, 28, 28, r: 14),
                  const SizedBox(width: 10),
                  _skelBar(dark, 90, 10),
                  const Spacer(),
                  _skelBar(dark, 64, 18, r: 9),
                ]),
                const SizedBox(height: 16),
                _skelBar(dark, 170, 13),
                const SizedBox(height: 8),
                _skelBar(dark, 120, 10),
                const SizedBox(height: 14),
                Row(children: [
                  _skelBar(dark, 90, 22, r: 8),
                  const Spacer(),
                  _skelBar(dark, 76, 22, r: 8),
                ]),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
// ALGO CARD — tactile, ripple, hero on the name
// ─────────────────────────────────────────────
class _CommunityAlgoCard extends StatelessWidget {
  final CommunityAlgoModel algo;
  final bool dark;
  final VoidCallback onTap;
  const _CommunityAlgoCard(
      {required this.algo, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bullish = algo.direction == 'Bullish';
    final dirColor = bullish ? _T.green : _T.red;
    final hr = algo.hitRate;
    final hrColor = _hitRateColor(hr, dark);

    return Material(
      color: _T.surface(dark),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: _T.accent.withOpacity(0.06),
        highlightColor: _T.accent.withOpacity(0.04),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.border(dark)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Creator row
              Row(children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: _T.accent.withOpacity(0.1),
                  backgroundImage: algo.creatorAvatarUrl != null
                      ? NetworkImage(algo.creatorAvatarUrl!)
                      : null,
                  child: algo.creatorAvatarUrl == null
                      ? Text(
                          algo.creatorName.isNotEmpty
                              ? algo.creatorName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _T.accent),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(algo.creatorName,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _T.sub(dark)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Text('${_timeAgo(algo.createdAt)} · ',
                    style: TextStyle(fontSize: 11, color: _T.sub(dark))),
                if (algo.isFeatured)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _svg(_I.award, _T.amber, size: 12),
                    const SizedBox(width: 3),
                    Text('FEATURED',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: _T.amber)),
                  ]),
              ]),
              const SizedBox(height: 12),
              // Name + direction
              Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: dirColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                      child: _svg(
                          bullish ? _I.trendingUp : _I.trendingDown, dirColor,
                          size: 16)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Hero(
                    tag: 'community-algo-name-${algo.id}',
                    child: Material(
                      color: Colors.transparent,
                      child: Text(algo.name,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: _T.text(dark)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.only(left: 38),
                child: Text(
                    '${algo.symbol} · ${algo.direction} · ${algo.days}-day lookback',
                    style: TextStyle(fontSize: 11.5, color: _T.sub(dark))),
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: _T.border(dark)),
              const SizedBox(height: 12),
              // Footer stats
              Row(children: [
                _statChip(
                    dark: dark,
                    icon: _I.users,
                    label:
                        '${algo.cloneCount} ${algo.cloneCount == 1 ? "trader saved" : "traders saved"}',
                    color: _T.sub(dark)),
                const Spacer(),
                _statChip(
                    dark: dark,
                    icon: _I.target,
                    label: hr != null
                        ? '${hr.toStringAsFixed(0)}% hit rate'
                        : 'No data yet',
                    color: hrColor),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(
      {required bool dark,
      required String icon,
      required String label,
      required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(dark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _svg(icon, color, size: 13),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// DETAIL PAGE
// ─────────────────────────────────────────────

class CommunityAlgoDetailPage extends StatefulWidget {
  final BacktestApiService api;
  final CommunityAlgoModel algo;
  const CommunityAlgoDetailPage(
      {super.key, required this.api, required this.algo});

  @override
  State<CommunityAlgoDetailPage> createState() =>
      _CommunityAlgoDetailPageState();
}

class _CommunityAlgoDetailPageState extends State<CommunityAlgoDetailPage> {
  late CommunityAlgoModel _algo = widget.algo;
  bool _loadingDetail = true;
  bool _saving = false;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final res = await Supabase.instance.client
          .from(kCommunityAlgosTable)
          .select()
          .eq('id', _algo.id)
          .single();
      if (!mounted) return;
      setState(() {
        _algo = CommunityAlgoModel.fromJson(Map<String, dynamic>.from(res));
      });
    } catch (_) {
      // Keep the model passed in from the list.
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _saveToMyAlgos() async {
    setState(() => _saving = true);
    try {
      final myAlgos = await widget.api.listAlgos();
      final plan = await widget.api.getUserPlan();
      final limit = algoLimitForPlan(plan);
      if (myAlgos.length >= limit) {
        if (mounted) _showUpgradeDialog(plan);
        return;
      }

      final algo = _algo;
      await widget.api.createAlgo(
        name: algo.name,
        symbol: algo.symbol,
        days: algo.days,
        direction: algo.direction,
        confirmBars: algo.confirmBars,
        conditions: algo.conditions,
      );

      // Best-effort — a failed bump shouldn't block the save.
      try {
        await Supabase.instance.client.rpc('increment_community_algo_clone',
            params: {'algo_id': algo.id});
      } catch (_) {}

      if (!mounted) return;
      _toast(context, 'Saved to your algos', ok: true);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => SavedBacktestsPage()),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (mounted) _toast(context, e.toString(), ok: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showUpgradeDialog(String plan) {
    final dark = _isDark;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _T.surface(dark),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Limit reached',
            style:
                TextStyle(color: _T.text(dark), fontWeight: FontWeight.w800)),
        content: Text(
          plan.toLowerCase() == 'max'
              ? 'You\'ve reached the maximum limit of $kMaxAlgoLimit algos.'
              : 'You\'ve reached your saved-algo limit for the $plan plan. Upgrade for more capacity.',
          style: TextStyle(color: _T.sub(dark), fontSize: 14, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: _T.sub(dark)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    final algo = _algo;
    final bullish = algo.direction == 'Bullish';
    final dirColor = bullish ? _T.green : _T.red;
    final hr = algo.hitRate;
    final hrColor = _hitRateColor(hr, dark);

    return Scaffold(
      backgroundColor: _T.bg(dark),
      appBar: AppBar(
        backgroundColor: _T.bg(dark),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 0,
        title: Text('Algo details',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: _T.text(dark))),
      ),
      body: _loadingDetail
          ? _DetailSkeleton(dark: dark)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              children: [
                _OverviewCard(
                    algo: algo,
                    dark: dark,
                    dirColor: dirColor,
                    hrColor: hrColor),
                const SizedBox(height: 12),
                _HitRateCard(algo: algo, dark: dark),
                const SizedBox(height: 12),
                if (algo.description != null &&
                    algo.description!.trim().isNotEmpty) ...[
                  _SectionCard(
                    dark: dark,
                    overline: 'NOTES FROM THE CREATOR',
                    child: Text(algo.description!,
                        style: TextStyle(
                            fontSize: 13, height: 1.55, color: _T.sub(dark))),
                  ),
                  const SizedBox(height: 12),
                ],
                _SectionCard(
                  dark: dark,
                  overline: 'HOW IT TRIGGERS',
                  child: algo.conditions.isEmpty
                      ? Text('No conditions recorded for this setup.',
                          style: TextStyle(fontSize: 12.5, color: _T.sub(dark)))
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int i = 0; i < algo.conditions.length; i++)
                              _ConditionStep(
                                dark: dark,
                                index: i + 1,
                                isLast: i == algo.conditions.length - 1,
                                text: algo.conditions[i].summary,
                              ),
                          ],
                        ),
                ),
              ],
            ),
      bottomNavigationBar: _loadingDetail
          ? null
          : _BottomCta(dark: dark, saving: _saving, onSave: _saveToMyAlgos),
    );
  }
}

// Creator + name + the key facts, laid out as a quiet stat sheet.
class _OverviewCard extends StatelessWidget {
  final CommunityAlgoModel algo;
  final bool dark;
  final Color dirColor;
  final Color hrColor;
  const _OverviewCard({
    required this.algo,
    required this.dark,
    required this.dirColor,
    required this.hrColor,
  });

  @override
  Widget build(BuildContext context) {
    final bullish = algo.direction == 'Bullish';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _T.surface(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.border(dark)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: _T.accent.withOpacity(0.1),
              backgroundImage: algo.creatorAvatarUrl != null
                  ? NetworkImage(algo.creatorAvatarUrl!)
                  : null,
              child: algo.creatorAvatarUrl == null
                  ? Text(
                      algo.creatorName.isNotEmpty
                          ? algo.creatorName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _T.accent),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'community-algo-name-${algo.id}',
                    child: Material(
                      color: Colors.transparent,
                      child: Text(algo.name,
                          style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: _T.text(dark)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                      'Shared by ${algo.creatorName} · ${_timeAgo(algo.createdAt)}',
                      style: TextStyle(fontSize: 11.5, color: _T.sub(dark))),
                ],
              ),
            ),
            if (algo.isFeatured)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: _T.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _svg(_I.award, _T.amber, size: 11),
                  const SizedBox(width: 4),
                  Text('FEATURED',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: _T.amber)),
                ]),
              ),
          ]),
          const SizedBox(height: 16),
          Divider(height: 1, color: _T.border(dark)),
          // Saved banner — the social proof, stated plainly.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(children: [
              _svg(_I.bookmark, _T.accent, size: 16),
              const SizedBox(width: 9),
              Expanded(
                child: RichText(
                  text: TextSpan(children: [
                    TextSpan(
                      text: '${algo.cloneCount}',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: _T.text(dark)),
                    ),
                    TextSpan(
                      text: algo.cloneCount == 1
                          ? ' trader has saved this to their own algos'
                          : ' traders have saved this to their own algos',
                      style: TextStyle(fontSize: 12, color: _T.sub(dark)),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: _T.border(dark)),
          const SizedBox(height: 14),
          // Fact grid — 2 per row, hairline-divided.
          Row(children: [
            Expanded(
                child: _fact(bullish ? _I.trendingUp : _I.trendingDown,
                    'DIRECTION', algo.direction,
                    valueColor: dirColor)),
            Container(width: 1, height: 34, color: _T.border(dark)),
            Expanded(
                child: _fact(_I.chart, 'SYMBOL', algo.symbol, padLeft: true)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _fact(_I.calendar, 'LOOKS BACK', '${algo.days} days')),
            Container(width: 1, height: 34, color: _T.border(dark)),
            Expanded(
                child: _fact(
                    _I.clock, 'CONFIRMS WITHIN', '${algo.confirmBars} candles',
                    padLeft: true)),
          ]),
        ],
      ),
    );
  }

  Widget _fact(String icon, String label, String value,
      {Color? valueColor, bool padLeft = false}) {
    return Padding(
      padding: EdgeInsets.only(left: padLeft ? 16 : 0, right: padLeft ? 0 : 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: _svg(icon, _T.sub(dark), size: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: _T.overline(dark)),
                const SizedBox(height: 3),
                Text(value,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: valueColor ?? _T.text(dark))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// The one number that matters most, explained in a sentence — plus the
// confirmed/failed split when history exists.
class _HitRateCard extends StatelessWidget {
  final CommunityAlgoModel algo;
  final bool dark;
  const _HitRateCard({required this.algo, required this.dark});

  @override
  Widget build(BuildContext context) {
    final hr = algo.hitRate;
    final color = _hitRateColor(hr, dark);
    final pct = ((hr ?? 0).clamp(0, 100)) / 100;
    final total = algo.totalBars;
    final confirmed = algo.confirmed;
    final failed = algo.failed;

    String detail;
    if (hr == null || total == null || total == 0) {
      detail = 'Not enough backtest history yet to show a reliable hit rate.';
    } else {
      detail =
          'Out of $total times this setup showed up, it played out correctly '
          '${confirmed ?? 0} time${(confirmed ?? 0) == 1 ? '' : 's'}.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _T.surface(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.border(dark)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: TweenAnimationBuilder<double>(
                      tween:
                          Tween(begin: 0, end: hr != null ? pct.toDouble() : 0),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => CircularProgressIndicator(
                        value: v,
                        strokeWidth: 6.5,
                        strokeCap: StrokeCap.round,
                        backgroundColor: color.withOpacity(0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ),
                  Text(hr != null ? '${hr.toStringAsFixed(0)}%' : '—',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('HISTORICAL HIT RATE', style: _T.overline(dark)),
                    const SizedBox(height: 5),
                    Text(detail,
                        style: TextStyle(
                            fontSize: 12, height: 1.45, color: _T.sub(dark))),
                  ],
                ),
              ),
            ],
          ),
          if (hr != null && total != null && total > 0) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: _T.border(dark)),
            const SizedBox(height: 12),
            Row(children: [
              _miniStat(_I.check, '${confirmed ?? 0} played out', _T.green),
              const SizedBox(width: 16),
              _miniStat(_I.alert, '${failed ?? 0} didn\'t', _T.red),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _svg(icon, color, size: 13),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
    ]);
  }
}

// Reusable section wrapper — overline title, no decorative icons.
class _SectionCard extends StatelessWidget {
  final bool dark;
  final String overline;
  final Widget child;
  const _SectionCard(
      {required this.dark, required this.overline, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _T.surface(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.border(dark)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(overline, style: _T.overline(dark)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// Numbered vertical timeline of conditions.
class _ConditionStep extends StatelessWidget {
  final bool dark;
  final int index;
  final bool isLast;
  final String text;
  const _ConditionStep(
      {required this.dark,
      required this.index,
      required this.isLast,
      required this.text});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration:
                  const BoxDecoration(color: _T.accent, shape: BoxShape.circle),
              child: Text('$index',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
            if (!isLast)
              Expanded(child: Container(width: 2, color: _T.border(dark))),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14, top: 1),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: _T.surface2(dark),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: _T.text(dark))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Sticky bottom action — one primary button, one clarifying line.
class _BottomCta extends StatelessWidget {
  final bool dark;
  final bool saving;
  final VoidCallback onSave;
  const _BottomCta(
      {required this.dark, required this.saving, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: _T.surface(dark),
        border: Border(top: BorderSide(color: _T.border(dark))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: saving ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: _T.accent,
                  disabledBackgroundColor: _T.accent.withOpacity(0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : _svg(_I.download, Colors.white, size: 17),
                label: Text(saving ? 'Saving…' : 'Save a copy to my algos',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Copies this setup into My algos — the original stays with the community.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: _T.sub(dark)),
            ),
          ],
        ),
      ),
    );
  }
}

// Static skeleton for the detail page. Every block sizes to its own
// content — no fixed heights, no Spacer — so it can never overflow.
class _DetailSkeleton extends StatelessWidget {
  final bool dark;
  const _DetailSkeleton({required this.dark});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _T.surface(dark),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.border(dark)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _skelBar(dark, 38, 38, r: 19),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      _skelBar(dark, 150, 13),
                      const SizedBox(height: 8),
                      _skelBar(dark, 100, 10),
                    ])),
              ]),
              const SizedBox(height: 16),
              _skelBar(dark, double.infinity, 1, r: 0),
              const SizedBox(height: 14),
              _skelBar(dark, 200, 11),
              const SizedBox(height: 14),
              _skelBar(dark, double.infinity, 1, r: 0),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _skelBar(dark, 90, 28)),
                const SizedBox(width: 16),
                Expanded(child: _skelBar(dark, 90, 28)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _skelBar(dark, 90, 28)),
                const SizedBox(width: 16),
                Expanded(child: _skelBar(dark, 90, 28)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _T.surface(dark),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.border(dark)),
          ),
          child: Row(children: [
            _skelBar(dark, 64, 64, r: 32),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  _skelBar(dark, 110, 9),
                  const SizedBox(height: 8),
                  _skelBar(dark, double.infinity, 10),
                  const SizedBox(height: 6),
                  _skelBar(dark, 180, 10),
                ])),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _T.surface(dark),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.border(dark)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _skelBar(dark, 110, 9),
              const SizedBox(height: 14),
              _skelBar(dark, double.infinity, 38, r: 10),
              const SizedBox(height: 8),
              _skelBar(dark, double.infinity, 38, r: 10),
              const SizedBox(height: 8),
              _skelBar(dark, double.infinity, 38, r: 10),
            ],
          ),
        ),
      ],
    );
  }
}
