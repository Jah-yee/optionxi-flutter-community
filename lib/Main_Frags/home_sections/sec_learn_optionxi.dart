// ============================================================
//  OptionXi — widget_learn_banner.dart
//
//  Drop this near the top of Home (below the header, above the
//  market-movers strip is a good spot). It fetches lesson state
//  once, shows a compact progress banner if there's anything left
//  to learn, and hides itself once every lesson is done.
//
//  States: loading (thin skeleton) -> error (compact retry chip)
//  -> loaded (progress banner) -> hidden (dismissed or all done).
//
//  Usage in Home:
//    const LearnOptionXIBanner(),
// ============================================================

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:optionxi/Main_Pages/Learning/act_learn_optionxi.dart';
import 'package:optionxi/Main_Pages/Learning/fastapi_onboarding.dart';

enum _BannerStatus { loading, error, loaded }

class LearnOptionXIBanner extends StatefulWidget {
  const LearnOptionXIBanner({super.key});

  @override
  State<LearnOptionXIBanner> createState() => _LearnOptionXIBannerState();
}

class _LearnOptionXIBannerState extends State<LearnOptionXIBanner> {
  _BannerStatus _status = _BannerStatus.loading;
  List<OnboardingModule>? _modules;
  bool _hidden = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _status = _BannerStatus.loading;
      _errorMessage = null;
    });
    try {
      final (modules, premium) = await OnboardingClient.fetchLessons();
      if (!mounted) return;
      setState(() {
        _modules = modules;
        _status = _BannerStatus.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _BannerStatus.error;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('Not signed in')) return 'Sign in to see your progress';
    if (msg.contains('SocketException') || msg.contains('TimeoutException')) {
      return 'Couldn\'t connect — check your internet';
    }
    return 'Couldn\'t load your lessons';
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();

    switch (_status) {
      case _BannerStatus.loading:
        return _buildLoadingSkeleton(context);
      case _BannerStatus.error:
        return _buildErrorChip(context);
      case _BannerStatus.loaded:
        return _buildLoadedBanner(context);
    }
  }

  // ── Loading ────────────────────────────────────────────────

  Widget _buildLoadingSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 74,
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _shimmerBox(46, 46, radius: 23, context: context),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _shimmerBox(160, 14, radius: 4, context: context),
                    const SizedBox(height: 8),
                    _shimmerBox(100, 11, radius: 4, context: context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmerBox(double width, double height,
      {required double radius, required BuildContext context}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  // ── Error ──────────────────────────────────────────────────

  Widget _buildErrorChip(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded,
                  color: theme.colorScheme.onSurfaceVariant, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorMessage ?? 'Couldn\'t load your lessons',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _load,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry', style: TextStyle(fontSize: 13)),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    size: 18),
                onPressed: () => setState(() => _hidden = true),
                tooltip: 'Dismiss for now',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Loaded ─────────────────────────────────────────────────

  Widget _buildLoadedBanner(BuildContext context) {
    final modules = _modules!;
    final allLessons = modules.expand((m) => m.lessons).toList();
    final completed = allLessons.where((l) => l.completed).length;
    final total = allLessons.length;

    // Nothing to show: no lessons configured, or everything's done.
    if (total == 0 || completed == total) return const SizedBox.shrink();

    final progress = completed / total;
    final theme = Theme.of(context);

    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.toNamed("/learn-optionxi"),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withBlue(220).withOpacity(0.9),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        backgroundColor: Colors.white.withOpacity(0.25),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        completed == 0
                            ? 'New here? Learn OptionXI in 5 minutes'
                            : 'Pick up where you left off',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$completed of $total lessons done',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: Colors.white.withOpacity(0.7), size: 18),
                  onPressed: () => setState(() => _hidden = true),
                  tooltip: 'Dismiss for now',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
