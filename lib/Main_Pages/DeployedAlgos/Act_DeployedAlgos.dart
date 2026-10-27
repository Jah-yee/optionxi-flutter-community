import 'dart:ui' show FontFeature;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:optionxi/Components/cust_contact_us.dart';
import 'package:optionxi/PushNotification/notifcation_service_firebase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

// =============================================================================
// DESIGN NOTES
//
// - Rows, not cards. Algos are a ledger: full-width rows split by hairlines, so
//   the list reads like a watchlist instead of a stack of tiles.
// - The lifecycle track is the one distinctive element. An algo really does
//   move through a sequence (updated > assigned > on call > phase 1 > deployed),
//   so each row shows where it is, and the detail screen labels every stage.
// - Slots are shown as physical slots (filled / empty), not a progress bar.
// - Signals are a timeline grouped by day, with the time in a fixed left column.
// - Everything takes its colour from the app's ColorScheme; only the status
//   colours are custom, and they are theme-aware.
// =============================================================================

const _tabular = [FontFeature.tabularFigures()];

String _formatClock(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m ${dt.hour >= 12 ? 'pm' : 'am'}';
}

String _formatDay(DateTime dt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${dt.day} ${months[dt.month - 1]}';
  return dt.year == now.year ? base : '$base ${dt.year}';
}

// =============================================================================
// DEPLOYED ALGOS — main screen
// =============================================================================

class DeployedAlgosScreen extends StatefulWidget {
  const DeployedAlgosScreen({super.key});

  @override
  State<DeployedAlgosScreen> createState() => _DeployedAlgosScreenState();
}

class _DeployedAlgosScreenState extends State<DeployedAlgosScreen> {
  final AlgoService _service = AlgoService();
  late Stream<List<AlgoModel>> _algosStream;
  late Future<int?> _limitFuture;
  String? _pendingAlgoId; // set from push notification args

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    NotificationServiceFirebase().ensureFreshTokenForAlgos();
    _algosStream = _service.watchAlgos();
    _limitFuture = _service.getAlgoLimit();
    _searchController.addListener(() {
      final next = _searchController.text.trim().toLowerCase();
      if (next != _query) setState(() => _query = next);
    });

    _pendingAlgoId = _extractAlgoId(Get.arguments);
    if (_pendingAlgoId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingAlgo());
    }
  }

  String? _extractAlgoId(dynamic args) {
    if (args is Map) {
      final id = args['algoId'];
      if (id != null && id.toString().isNotEmpty) return id.toString();
    }
    return null;
  }

  Future<void> _openPendingAlgo() async {
    final algoId = _pendingAlgoId;
    if (algoId == null || !mounted) return;
    _pendingAlgoId = null; // consume once, avoid re-triggering on rebuild

    try {
      final algo = await _service.getAlgoById(algoId);
      if (algo == null || !mounted) return;
      _openAlgo(algo);
    } catch (e) {
      debugPrint('Failed to open algo $algoId from notification: $e');
    }
  }

  void _openAlgo(AlgoModel algo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlgoNotificationsScreen(algo: algo, service: _service),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _algosStream = _service.watchAlgos();
      _limitFuture = _service.getAlgoLimit();
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  Future<void> _handleAddAlgoTap() async {
    HapticFeedback.selectionClick();
    final limit = await _service.getAlgoLimit();
    if (!mounted) return;

    if (limit == null) {
      _showSubscribeSheet();
      return;
    }

    final canAdd = await _service.canAddAlgo();
    if (!mounted) return;
    if (!canAdd) {
      _showLockedSheet();
      return;
    }

    final created = await showAddAlgoSheet(context, _service);
    if (created == true && mounted) {
      setState(() => _limitFuture = _service.getAlgoLimit());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Text('Algo deployed'),
        ),
      );
    }
  }

  void _showLockedSheet() {
    _showInfoSheet(
      context,
      icon: Icons.lock_outline_rounded,
      title: 'All slots are in use',
      body: 'You\'ve deployed every algo your plan includes. '
          'Contact your admin to add more slots.',
      primaryLabel: 'Got it',
    );
  }

  void _showSubscribeSheet() {
    final screenContext = context;
    _showInfoSheet(
      context,
      icon: Icons.workspace_premium_rounded,
      title: 'Deploy your own algos',
      body: 'Subscribe to run your trading algos and get a notification '
          'the moment one triggers a signal.',
      extra: Builder(builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('₹1,500',
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800, fontFeatures: _tabular)),
            const SizedBox(width: 6),
            Text('per month',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
        );
      }),
      primaryLabel: 'Subscribe',
      onPrimary: () => showContactOptions(
          screenContext, "I want to subscribe to Algo Deployment"),
      secondaryLabel: 'Not now',
    );
  }

  Widget _buildAllowance(AsyncSnapshot<List<AlgoModel>> snapshot) {
    return FutureBuilder<int?>(
      future: _limitFuture,
      builder: (context, limitSnap) {
        // Note: a null result is meaningful ("not subscribed"), so check the
        // connection state rather than hasData.
        if (limitSnap.connectionState != ConnectionState.done ||
            limitSnap.hasError ||
            !snapshot.hasData) {
          return const SizedBox(height: 4);
        }
        final limit = limitSnap.data;
        if (limit == null) {
          return _PremiumBanner(onTap: _showSubscribeSheet);
        }
        return _SlotsStrip(used: snapshot.data!.length, limit: limit);
      },
    );
  }

  Widget _buildSearch(ColorScheme cs) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _searchOpen
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: SearchBar(
                controller: _searchController,
                autoFocus: true,
                hintText: 'Search by name or details',
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor:
                    WidgetStatePropertyAll(cs.surfaceContainerHigh),
                padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 16)),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
                leading: Icon(Icons.search_rounded,
                    size: 20, color: cs.onSurfaceVariant),
                trailing: [
                  if (_query.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: _searchController.clear,
                    ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  List<Widget> _buildContent(
    AsyncSnapshot<List<AlgoModel>> snapshot,
    List<AlgoModel> all,
    List<AlgoModel> filtered,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return [
        SliverList.builder(
          itemCount: 5,
          itemBuilder: (_, __) => const _AlgoRowSkeleton(),
        ),
      ];
    }

    if (snapshot.hasError) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorState(onRetry: _retry),
        ),
      ];
    }

    if (all.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyState(onTap: _handleAddAlgoTap),
        ),
      ];
    }

    if (filtered.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _NoResultsState(query: _searchController.text.trim()),
        ),
      ];
    }

    final cs = Theme.of(context).colorScheme;
    return [
      SliverList.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 20,
          endIndent: 20,
          color: cs.outlineVariant.withOpacity(0.45),
        ),
        itemBuilder: (context, index) {
          final algo = filtered[index];
          return AlgoRow(algo: algo, onTap: () => _openAlgo(algo));
        },
      ),
      SliverToBoxAdapter(
        child: SizedBox(height: 32 + MediaQuery.of(context).padding.bottom),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: StreamBuilder<List<AlgoModel>>(
        stream: _algosStream,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <AlgoModel>[];
          final filtered = _query.isEmpty
              ? all
              : all
                  .where((a) =>
                      a.name.toLowerCase().contains(_query) ||
                      a.details.toLowerCase().contains(_query))
                  .toList();

          return RefreshIndicator(
            onRefresh: () async => _retry(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Fix 1: pinned single-row header so title + actions align.
                // This screen has a back button, so titleSpacing is left at
                // its default; use `titleSpacing: 20` instead if this ever
                // becomes a bottom-nav tab with no back button.
                SliverAppBar(
                  pinned: true,
                  backgroundColor: cs.surface,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                  centerTitle: false,
                  title: Text(
                    'Deployed algos',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  actions: [
                    IconButton(
                      tooltip: _searchOpen ? 'Close search' : 'Search',
                      icon: Icon(_searchOpen
                          ? Icons.close_rounded
                          : Icons.search_rounded),
                      onPressed: _toggleSearch,
                    ),
                    // Fix 2: filledTonal is softer than filled and matches
                    // the plain search icon.
                    Padding(
                      padding: const EdgeInsets.only(right: 12, left: 2),
                      child: IconButton.filledTonal(
                        tooltip: 'Deploy an algo',
                        icon: const Icon(Icons.add_rounded),
                        onPressed: _handleAddAlgoTap,
                      ),
                    ),
                  ],
                ),
                SliverToBoxAdapter(child: _buildAllowance(snapshot)),
                SliverToBoxAdapter(child: _buildSearch(cs)),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ..._buildContent(snapshot, all, filtered),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// SHARED SHEET
// =============================================================================

Future<void> _showInfoSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required String primaryLabel,
  Widget? extra,
  VoidCallback? onPrimary,
  String? secondaryLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final cs = theme.colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cs.primary, size: 22),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.5)),
            if (extra != null) ...[
              const SizedBox(height: 18),
              extra,
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  onPrimary?.call();
                },
                child: Text(primaryLabel),
              ),
            ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(secondaryLabel),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

// =============================================================================
// SLOTS STRIP + PREMIUM BANNER
// =============================================================================

class _SlotsStrip extends StatelessWidget {
  final int used;
  final int limit;
  const _SlotsStrip({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final free = (limit - used).clamp(0, limit);
    final isFull = free == 0;

    return Padding(
      // Fix 3: 8px top padding (was 4) for breathing room under the header.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$used of $limit slots in use',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, fontFeatures: _tabular),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isFull
                        ? 'Contact your admin to add more'
                        : '$free ${free == 1 ? 'slot' : 'slots'} available',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(limit, (i) {
                final filled = i < used;
                return Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 20,
                    height: 34,
                    decoration: BoxDecoration(
                      color: filled ? cs.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: filled
                            ? cs.primary
                            : cs.outlineVariant.withOpacity(0.9),
                        width: 1.5,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _PremiumBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      // Fix 3: 8px top padding (was 4).
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Material(
        color: cs.primaryContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.workspace_premium_rounded,
                    color: cs.onPrimaryContainer, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Get live signals from your own algos',
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹1,500 per month',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onPrimaryContainer.withOpacity(0.8),
                            fontFeatures: _tabular),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded,
                    color: cs.onPrimaryContainer, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ALGO ROW
// =============================================================================

class AlgoRow extends StatelessWidget {
  final AlgoModel algo;
  final VoidCallback onTap;

  const AlgoRow({super.key, required this.algo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    algo.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  timeago.format(
                      DateTime.fromMillisecondsSinceEpoch(algo.createdAt)),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              algo.details,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 86,
                  child: _LifecycleTrack(status: algo.status),
                ),
                const SizedBox(width: 12),
                Expanded(child: _StatusLabel(status: algo.status)),
                _TimeframeTag(timeframe: algo.timeframe),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LIFECYCLE TRACK, STATUS LABEL, TIMEFRAME TAG
// =============================================================================

class _LifecycleTrack extends StatelessWidget {
  final AlgoStatus status;
  final bool labelled;
  const _LifecycleTrack({required this.status, this.labelled = false});

  static const _labels = ['Updated', 'Assigned', 'On call', 'Phase 1', 'Live'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = status.color(context);
    final stage = status.stage;
    final height = labelled ? 6.0 : 4.0;

    final bars = Row(
      children: List.generate(_labels.length, (i) {
        final Color fill;
        if (stage == null) {
          fill = color.withOpacity(0.25);
        } else if (i <= stage) {
          fill = color;
        } else {
          fill = cs.surfaceContainerHighest;
        }
        return Expanded(
          child: Container(
            height: height,
            margin: EdgeInsets.only(right: i == _labels.length - 1 ? 0 : 4),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(height),
            ),
          ),
        );
      }),
    );

    if (!labelled) return bars;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bars,
        const SizedBox(height: 8),
        Row(
          children: List.generate(_labels.length, (i) {
            final current = stage == i;
            return Expanded(
              child: Text(
                _labels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: current ? color : cs.onSurfaceVariant,
                  fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final AlgoStatus status;
  const _StatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status.color(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            status.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _TimeframeTag extends StatelessWidget {
  final String timeframe;
  const _TimeframeTag({required this.timeframe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        timeframe,
        style: theme.textTheme.labelSmall?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w700,
          fontFeatures: _tabular,
        ),
      ),
    );
  }
}

// =============================================================================
// SKELETONS
// =============================================================================

class _PulseBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const _PulseBox({this.width, required this.height, this.radius = 6});

  @override
  State<_PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<_PulseBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class _AlgoRowSkeleton extends StatelessWidget {
  const _AlgoRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PulseBox(width: 150, height: 15),
          SizedBox(height: 10),
          _PulseBox(width: double.infinity, height: 11),
          SizedBox(height: 6),
          _PulseBox(width: 220, height: 11),
          SizedBox(height: 16),
          Row(
            children: [
              _PulseBox(width: 86, height: 4, radius: 4),
              SizedBox(width: 12),
              _PulseBox(width: 80, height: 11),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignalSkeleton extends StatelessWidget {
  const _SignalSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 48, child: _PulseBox(height: 11)),
          SizedBox(width: 48),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PulseBox(width: 170, height: 14),
                SizedBox(height: 8),
                _PulseBox(width: double.infinity, height: 11),
                SizedBox(height: 6),
                _PulseBox(width: 120, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// EMPTY / ERROR / NO-RESULTS STATES
// =============================================================================

class _StateLayout extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Color? iconColor;

  const _StateLayout({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = iconColor ?? cs.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 24, 36, 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: tint.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 28, color: tint),
            ),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.45)),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _StateLayout(
      icon: Icons.cloud_off_rounded,
      iconColor: cs.error,
      title: 'Couldn\'t load your algos',
      body: 'Check your connection, then try again.',
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Try again'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _StateLayout(
      icon: Icons.auto_graph_rounded,
      title: 'No algos deployed yet',
      body: 'Deploy your first algo to get a notification every time '
          'it triggers a signal.',
      action: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Deploy an algo'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  final String query;
  const _NoResultsState({required this.query});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _StateLayout(
      icon: Icons.search_off_rounded,
      iconColor: cs.onSurfaceVariant,
      title: 'No algos match "$query"',
      body: 'Try a different name, or search by words in the details.',
    );
  }
}

// =============================================================================
// ALGO DETAIL — lifecycle + signal timeline
// =============================================================================

class AlgoNotificationsScreen extends StatefulWidget {
  final AlgoModel algo;
  final AlgoService service;

  const AlgoNotificationsScreen({
    super.key,
    required this.algo,
    required this.service,
  });

  @override
  State<AlgoNotificationsScreen> createState() =>
      _AlgoNotificationsScreenState();
}

class _AlgoNotificationsScreenState extends State<AlgoNotificationsScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<AlgoNotificationModel> _items = [];
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  bool _initialLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 240 &&
        !_loading &&
        _hasMore &&
        _error == null) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await widget.service.fetchNotificationsPage(
        algoId: widget.algo.id,
        page: _page,
      );

      if (!mounted) return;

      setState(() {
        _items.addAll(page);
        _page++;
        _hasMore = page.length == AlgoService.kPageSize;
        _initialLoading = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoading = false;
        _error = 'Couldn\'t load signals';
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    await _loadPage();
  }

  /// Flattens signals into day headers + signal entries.
  List<Object> _buildRows() {
    final rows = <Object>[];
    String? lastKey;
    for (final n in _items) {
      final d = n.dateTime;
      final key = '${d.year}-${d.month}-${d.day}';
      if (key != lastKey) {
        rows.add(_formatDay(d));
        lastKey = key;
      }
      rows.add(n);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final algo = widget.algo;

    return Scaffold(
      backgroundColor: cs.surface,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Optional: same pinned single-row header. Long algo names get
            // an ellipsis instead of being squeezed into a large title.
            SliverAppBar(
              pinned: true,
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              centerTitle: false,
              title: Text(
                algo.name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            SliverToBoxAdapter(child: _buildHeader(theme, cs)),
            SliverToBoxAdapter(child: _buildSignalsHeading(theme, cs)),
            ..._buildSignals(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs) {
    final algo = widget.algo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            algo.details,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 22),
          _LifecycleTrack(status: algo.status, labelled: true),
          const SizedBox(height: 18),
          Row(
            children: [
              _StatusLabel(status: algo.status),
              const SizedBox(width: 10),
              _TimeframeTag(timeframe: algo.timeframe),
              const Spacer(),
              Text(
                'Added ${timeago.format(DateTime.fromMillisecondsSinceEpoch(algo.createdAt))}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(0.5)),
        ],
      ),
    );
  }

  Widget _buildSignalsHeading(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('Signals',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          if (_items.isNotEmpty)
            Text(
              '${_items.length}${_hasMore ? '+' : ''}',
              style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant, fontFeatures: _tabular),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSignals(ColorScheme cs) {
    if (_initialLoading) {
      return [
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        SliverList.builder(
          itemCount: 5,
          itemBuilder: (_, __) => const _SignalSkeleton(),
        ),
      ];
    }

    if (_error != null && _items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _StateLayout(
            icon: Icons.cloud_off_rounded,
            iconColor: cs.error,
            title: _error!,
            body: 'Check your connection, then try again.',
            action: OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ];
    }

    if (_items.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: _StateLayout(
            icon: Icons.notifications_none_rounded,
            title: 'No signals yet',
            body: 'When this algo triggers, the signal and its details '
                'will appear here.',
          ),
        ),
      ];
    }

    final rows = _buildRows();
    final bottomPad = 32 + MediaQuery.of(context).padding.bottom;

    return [
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          if (row is String) return _DayHeader(label: row);
          final notification = row as AlgoNotificationModel;
          final isFirst = identical(notification, _items.first);
          final isLast = index == rows.length - 1 && !_hasMore;
          return _SignalTile(
            notification: notification,
            isFirst: isFirst,
            isLast: isLast,
          );
        },
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 8, bottom: bottomPad),
          child: Center(
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _error != null
                    ? TextButton.icon(
                        onPressed: _loadPage,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Couldn\'t load more. Try again'),
                      )
                    : const SizedBox.shrink(),
          ),
        ),
      ),
    ];
  }
}

class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  final AlgoNotificationModel notification;
  final bool isFirst;
  final bool isLast;

  const _SignalTile({
    required this.notification,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 60,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  _formatClock(notification.dateTime),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isFirst ? cs.onSurface : cs.onSurfaceVariant,
                    fontWeight: isFirst ? FontWeight.w700 : FontWeight.w500,
                    fontFeatures: _tabular,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 4),
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFirst ? cs.primary : cs.surface,
                      border: Border.all(
                        color: isFirst ? cs.primary : cs.outline,
                        width: 1.75,
                      ),
                    ),
                  ),
                  Expanded(
                    child: isLast
                        ? const SizedBox.shrink()
                        : Container(
                            width: 1.5,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: cs.outlineVariant.withOpacity(0.7),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
                    ),
                    if (notification.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant, height: 1.45),
                      ),
                    ],
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

// =============================================================================
// ADD ALGO — bottom sheet
// =============================================================================

const List<String> kTimeframes = ['1m', '5m', '15m', '1h', '4h', '1D'];

/// Shows the deploy sheet. Returns true if an algo was created.
Future<bool?> showAddAlgoSheet(BuildContext context, AlgoService service) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => AddAlgoSheet(service: service),
  );
}

class AddAlgoSheet extends StatefulWidget {
  final AlgoService service;
  const AddAlgoSheet({super.key, required this.service});

  @override
  State<AddAlgoSheet> createState() => _AddAlgoSheetState();
}

class _AddAlgoSheetState extends State<AddAlgoSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _detailsController = TextEditingController();
  String _timeframe = kTimeframes.first;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(
    BuildContext context, {
    required String label,
    String? hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      border: border(Colors.transparent, 0),
      enabledBorder: border(Colors.transparent, 0),
      focusedBorder: border(cs.primary, 1.5),
      errorBorder: border(cs.error, 1),
      focusedErrorBorder: border(cs.error, 1.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await widget.service.addAlgo(
        name: _nameController.text,
        details: _detailsController.text,
        timeframe: _timeframe,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Couldn\'t deploy this algo. Check your connection '
            'and try again.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Deploy an algo',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'This uses one of your slots, and the slot stays locked '
                'after you deploy.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                enabled: !_submitting,
                decoration: _decoration(
                  context,
                  label: 'Algo name',
                  hint: 'e.g. Nifty Breakout Scalper',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter a name for this algo'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _detailsController,
                minLines: 3,
                maxLines: 5,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(
                  context,
                  label: 'Details',
                  hint: 'Strategy logic, instruments, risk notes',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Add a few details about the strategy'
                    : null,
              ),
              const SizedBox(height: 20),
              Text('Timeframe',
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              _TimeframePicker(
                value: _timeframe,
                enabled: !_submitting,
                onChanged: (tf) {
                  HapticFeedback.selectionClick();
                  setState(() => _timeframe = tf);
                },
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 18, color: cs.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_errorText!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.error, height: 1.4)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                          ),
                        )
                      : const Text('Deploy algo'),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeframePicker extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _TimeframePicker({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: kTimeframes.map((tf) {
          final selected = tf == value;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: 'Timeframe $tf',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? () => onChanged(tf) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? cs.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tf,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: _tabular,
                      color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================================
// DATA LAYER (unchanged behaviour)
// =============================================================================

/// Thin wrapper around Firebase Realtime Database for the "Deployed Algos"
/// feature.
///
/// Data shape:
/// algo_deployed/{uid}/{algoId}/{name, details, timeframe, status, createdAt}
/// algo_deployed/{uid}/{algoId}/notifications/{notifId}/{title, description, timestamp}
/// subscribed_algo_users/{uid}/{limit}

class AlgoService {
  AlgoService({FirebaseDatabase? database, FirebaseAuth? auth})
      : _database = database ?? FirebaseDatabase.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _supabase = Supabase.instance.client;

  final FirebaseDatabase _database;
  final FirebaseAuth _auth;
  final SupabaseClient _supabase;

  static const int kPageSize = 20;

  DatabaseReference get _root => _database.ref();

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('No authenticated user found.');
    }
    return uid;
  }

  /// Live stream of the current user's deployed algos.
  Stream<List<AlgoModel>> watchAlgos() {
    return _root.child('algo_deployed/$_uid').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return <AlgoModel>[];

      final map = Map<dynamic, dynamic>.from(raw);
      final algos = map.entries
          .map((e) => AlgoModel.fromMap(
                e.key.toString(),
                Map<dynamic, dynamic>.from(e.value as Map),
              ))
          .toList();

      algos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return algos;
    });
  }

  Future<AlgoModel?> getAlgoById(String algoId) async {
    final snap = await _root.child('algo_deployed/$_uid/$algoId').get();
    if (!snap.exists || snap.value == null) return null;
    return AlgoModel.fromMap(
      algoId,
      Map<dynamic, dynamic>.from(snap.value as Map),
    );
  }

  /// Paginated fetch for notifications.
  Future<List<AlgoNotificationModel>> fetchNotificationsPage({
    required String algoId,
    required int page,
  }) async {
    final from = page * kPageSize;
    final to = from + kPageSize - 1;

    final rows = await _supabase
        .from('algo_notifications')
        .select()
        .eq('uid_algo', '$_uid:$algoId')
        .order('created_at', ascending: false)
        .range(from, to);

    return (rows as List)
        .map((r) =>
            AlgoNotificationModel.fromSupabase(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Returns the algo limit for the current user, or `null` if the user
  /// isn't on a plan that grants algo deployment access.
  Future<int?> getAlgoLimit() async {
    final row = await _supabase
        .from('subscribed_users')
        .select('active_plan_key, expires_at')
        .eq('suid', _uid)
        .maybeSingle();

    if (row == null) return null; // no subscription record at all

    final planKey = (row['active_plan_key'] as String?)?.toLowerCase();
    if (planKey != 'max') return null; // only the "max" plan unlocks algo slots

    // Treat an expired plan as unsubscribed.
    final expiresAtRaw = row['expires_at'] as String?;
    if (expiresAtRaw != null) {
      final expiresAt = DateTime.tryParse(expiresAtRaw);
      if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
        return null;
      }
    }

    return 3; // "max" plan → 3 deployment slots
  }

  /// Checks the current algo count against the allowed limit.
  /// Returns true if the user is still allowed to add another algo.
  Future<bool> canAddAlgo() async {
    final limit = await getAlgoLimit();
    if (limit == null) return false; // not subscribed at all
    final snap = await _root.child('algo_deployed/$_uid').get();
    final currentCount = (snap.exists && snap.value is Map)
        ? Map<dynamic, dynamic>.from(snap.value as Map).length
        : 0;
    return currentCount < limit;
  }

  /// Adds a new algo under algo_deployed/{uid}/{newId}.
  /// Caller should already have verified [canAddAlgo].
  Future<void> addAlgo({
    required String name,
    required String details,
    required String timeframe,
  }) async {
    final ref = _root.child('algo_deployed/$_uid').push();
    final algo = AlgoModel(
      id: ref.key ?? '',
      name: name.trim(),
      details: details.trim(),
      timeframe: timeframe,
      status: AlgoStatus.updated,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.set(algo.toMap());
  }

  /// Ensures a subscribed_algo_users/{uid} record exists with a default
  /// limit of 1, so admins can find & edit it later without guessing.
  Future<void> ensureSubscriptionRecord() async {
    final ref = _root.child('subscribed_algo_users/$_uid');
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({'limit': 1});
    }
  }
}

class AlgoModel {
  final String id;
  final String name;
  final String details;
  final String timeframe;
  final AlgoStatus status;
  final int createdAt; // millisecondsSinceEpoch

  AlgoModel({
    required this.id,
    required this.name,
    required this.details,
    required this.timeframe,
    required this.status,
    required this.createdAt,
  });

  factory AlgoModel.fromMap(String id, Map<dynamic, dynamic> map) {
    return AlgoModel(
      id: id,
      name: (map['name'] ?? '').toString(),
      details: (map['details'] ?? '').toString(),
      timeframe: (map['timeframe'] ?? '').toString(),
      status: AlgoStatus.fromValue(map['status']?.toString()),
      createdAt: map['createdAt'] is int
          ? map['createdAt']
          : int.tryParse(map['createdAt']?.toString() ?? '') ??
              DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'details': details,
      'timeframe': timeframe,
      'status': status.value,
      'createdAt': createdAt,
    };
  }
}

/// All lifecycle states an algo can be in.
/// Stored in Firebase as the raw string in [value].
enum AlgoStatus {
  updated('updated', 'Updated'),
  developerAssigned('developer_assigned', 'Developer assigned'),
  onCall('on_call', 'On call'),
  phase1('phase_1', 'Phase 1'),
  deployed('deployed', 'Deployed'),
  clientNotPickingUp('client_not_picking_up', 'Client not picking up'),
  cancelling('cancelling', 'Cancelling'),
  cancelled('cancelled', 'Cancelled');

  final String value;
  final String label;
  const AlgoStatus(this.value, this.label);

  static AlgoStatus fromValue(String? raw) {
    return AlgoStatus.values.firstWhere(
      (s) => s.value == raw,
      orElse: () => AlgoStatus.updated,
    );
  }

  /// Position on the five-step deployment track (0 to 4), or `null` for
  /// states that sit outside the normal path (cancelling, cancelled).
  /// "Client not picking up" stalls at the on-call step.
  int? get stage {
    switch (this) {
      case AlgoStatus.updated:
        return 0;
      case AlgoStatus.developerAssigned:
        return 1;
      case AlgoStatus.onCall:
      case AlgoStatus.clientNotPickingUp:
        return 2;
      case AlgoStatus.phase1:
        return 3;
      case AlgoStatus.deployed:
        return 4;
      case AlgoStatus.cancelling:
      case AlgoStatus.cancelled:
        return null;
    }
  }

  /// Theme-aware color so it reads correctly in both light & dark mode.
  Color color(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (this) {
      case AlgoStatus.updated:
        return isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);
      case AlgoStatus.developerAssigned:
        return isDark ? const Color(0xFFBA68C8) : const Color(0xFF6A1B9A);
      case AlgoStatus.onCall:
        return isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
      case AlgoStatus.phase1:
        return isDark ? const Color(0xFF4FC3F7) : const Color(0xFF0277BD);
      case AlgoStatus.deployed:
        return isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
      case AlgoStatus.clientNotPickingUp:
        return isDark ? const Color(0xFFE57373) : const Color(0xFFC62828);
      case AlgoStatus.cancelling:
        return isDark ? const Color(0xFFFF8A65) : const Color(0xFFD84315);
      case AlgoStatus.cancelled:
        return isDark ? const Color(0xFF90A4AE) : const Color(0xFF546E7A);
    }
  }
}

class AlgoNotificationModel {
  final String id;
  final String title;
  final String description;
  final int timestamp; // millisecondsSinceEpoch

  AlgoNotificationModel({
    required this.id,
    required this.title,
    required this.description,
    required this.timestamp,
  });

  factory AlgoNotificationModel.fromSupabase(Map<String, dynamic> row) {
    return AlgoNotificationModel(
      id: row['id'].toString(),
      title: (row['title'] ?? '').toString(),
      description: (row['description'] ?? '').toString(),
      timestamp:
          DateTime.parse(row['created_at'] as String).millisecondsSinceEpoch,
    );
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}
