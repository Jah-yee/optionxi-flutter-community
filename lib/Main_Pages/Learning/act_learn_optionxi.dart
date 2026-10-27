// ============================================================
//  OptionXi — act_learn_optionxi.dart   (v3 · fixed quiz grading + skeletons)
//
//  • Chunky 3D path nodes, winding "S" curve per module, connected
//    by drawn path lines (CustomPainter)
//  • Top stats bar: streak 🔥 · gems 💎 · hearts ❤️
//  • Daily quests as a horizontal card strip (premium-gated)
//  • Full-screen lesson flow: read (+ optional YouTube reference video)
//    → one-question-at-a-time quiz, answers are only selected as you go —
//      nothing is graded until you hit Finish → celebration result with a
//      per-question right/wrong breakdown from the server's response
//  • Lesson app bar: back button, heading, notifications shortcut
//  • Premium unlocks via rounded bottom sheet
//  • Skeleton loaders (shimmer) for both the path screen and the lesson
//    content screen instead of a bare spinner
// ============================================================

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:optionxi/Main_Pages/Learning/fastapi_onboarding.dart';
import 'package:optionxi/Main_Pages/SubscriptionsRazorpay/act_subscription_razorpay.dart';

// ─────────────────────────────────────────────────────────────
// Type-safe route names.
//
// Using named `static const` fields (instead of hand-typed string
// literals like Get.toNamed('/notification')) means every call site
// is checked by the analyzer for typos and gets IDE autocomplete.
// Register these in your GetMaterialApp's `getPages`, e.g.:
//
//   GetMaterialApp(
//     initialRoute: AppRoutes.home,
//     getPages: [
//       GetPage(name: AppRoutes.notifications, page: () => const NotificationsPage()),
//       ...
//     ],
//   )
//
// NOTE: this screen calls Get.toNamed(...), which requires the app's
// root widget to be a GetMaterialApp (not a plain MaterialApp) — see
// pubspec note below.
// ─────────────────────────────────────────────────────────────

abstract class AppRoutes {
  AppRoutes._();
  static const String home = '/';
}

// ─────────────────────────────────────────────────────────────
// Brand palette (Duolingo-flavoured)
// ─────────────────────────────────────────────────────────────

class DColors {
  DColors._();

  static const green = Color(0xFF58CC02);
  static const greenDark = Color(0xFF46A302);
  static const blue = Color(0xFF1CB0F6);
  static const blueDark = Color(0xFF1899D6);
  static const red = Color(0xFFFF4B4B);
  static const redDark = Color(0xFFEA2B2B);
  static const orange = Color(0xFFFF9600);
  static const gold = Color(0xFFFFC800);
  static const purple = Color(0xFFCE82FF);
  static const ink = Color(0xFF4B4B4B);
  static const grey = Color(0xFF777777);
  static const border = Color(0xFFE5E5E5);
  static const lockedFill = Color(0xFFF1F1F1);
  static const scaffold = Color(0xFFFFFFFF);
  static const cardBlue = Color(0xFFDDF4FF);
  static const cardGreen = Color(0xFFD7FFB8);
  static const skeletonBase = Color(0xFFEDEDED);
  static const skeletonHighlight = Color(0xFFF7F7F7);
}

// ─────────────────────────────────────────────────────────────
// Reusable chunky "3D" button (Duolingo signature)
// ─────────────────────────────────────────────────────────────

class DButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color color;
  final Color shadow;
  final Color textColor;
  final IconData? icon;
  final bool uppercase;
  final double height;

  const DButton({
    super.key,
    required this.text,
    this.onPressed,
    this.color = DColors.green,
    this.shadow = DColors.greenDark,
    this.textColor = Colors.white,
    this.icon,
    this.uppercase = true,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fill = enabled ? color : DColors.border;
    final edge = enabled ? shadow : const Color(0xFFBFBFBF);
    final fg = enabled ? textColor : const Color(0xFF9E9E9E);

    return GestureDetector(
      onTapDown: enabled ? (_) {} : null,
      onTap: onPressed,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            bottom: BorderSide(color: edge, width: 4),
          ),
          boxShadow: enabled ? null : null,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: fg, size: 22),
                const SizedBox(width: 8),
              ],
              Text(
                uppercase ? text.toUpperCase() : text,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Stat pill (streak / gems / hearts)
// ─────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  const _StatPill(
      {required this.icon,
      required this.value,
      required this.color,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 5),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: DColors.ink,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shimmer skeleton primitives
// ─────────────────────────────────────────────────────────────

/// Wraps its child tree in a looping left→right shimmer sweep. Any
/// [_SkeletonBox] beneath it picks up the animated gradient via
/// [ShaderMask], so a whole skeleton layout only needs a single
/// AnimationController.
class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final t = _controller.value;
            return LinearGradient(
              colors: const [
                DColors.skeletonBase,
                DColors.skeletonHighlight,
                DColors.skeletonBase,
              ],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment(-1 - t * 2, 0),
              end: Alignment(1 - t * 2, 0),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A single flat-colour placeholder block. Actual shimmer motion comes
/// from the [_Shimmer] ancestor's [ShaderMask].
class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  const _SkeletonBox({
    this.width = double.infinity,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: DColors.skeletonBase,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton for the whole Learn path screen: stat pills, quest strip,
/// and a handful of zig-zagging node placeholders — shown while
/// [OnboardingClient.fetchLessons] is in flight.
class _LearnPathSkeleton extends StatelessWidget {
  const _LearnPathSkeleton();

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            // header stats skeleton
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              color: DColors.blue.withOpacity(0.08),
              child: Column(
                children: [
                  Row(
                    children: const [
                      _SkeletonBox(width: 64, height: 28, radius: 20),
                      Spacer(),
                      _SkeletonBox(width: 64, height: 28, radius: 20),
                      SizedBox(width: 10),
                      _SkeletonBox(width: 64, height: 28, radius: 20),
                    ],
                  ),
                  SizedBox(height: 14),
                  _SkeletonBox(height: 16, radius: 8),
                ],
              ),
            ),
            // quest strip skeleton
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SkeletonBox(width: 130, height: 18),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 118,
                    child: Row(
                      children: const [
                        Expanded(child: _SkeletonBox(height: 118, radius: 16)),
                        SizedBox(width: 10),
                        Expanded(child: _SkeletonBox(height: 118, radius: 16)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // module banner skeleton
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
              child: const _SkeletonBox(height: 64, radius: 16),
            ),
            const SizedBox(height: 30),
            // zig-zagging node skeletons, with connecting path lines
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                // const dxOffsets = [0.0, -60.0, 60.0, -35.0]; //4 nodes
                const dxOffsets = [0.0, -60.0, 60.0]; // 3 nodes
                final centers = <Offset>[
                  for (int i = 0; i < dxOffsets.length; i++)
                    Offset(
                      width / 2 + dxOffsets[i],
                      i * (66.0 + 26.0) + 33.0, // node diameter + gap, centered
                    ),
                ];
                final totalHeight =
                    (dxOffsets.length - 1) * (66.0 + 26.0) + 66.0;

                return SizedBox(
                  height: totalHeight,
                  width: width,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _PathLinePainter(centers: centers),
                        ),
                      ),
                      for (final c in centers)
                        Positioned(
                          left: c.dx - 33,
                          top: c.dy - 33,
                          child: const _SkeletonBox(
                            width: 66,
                            height: 66,
                            radius: 33,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for a lesson's reading screen while its content loads:
/// a video-thumbnail block plus a handful of text-line placeholders.
class _LessonBodySkeleton extends StatelessWidget {
  const _LessonBodySkeleton();

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkeletonBox(width: 140, height: 22),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: const _SkeletonBox(height: double.infinity, radius: 16),
          ),
          const SizedBox(height: 16),
          for (final w in [1.0, 1.0, 0.9, 1.0, 0.6])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FractionallySizedBox(
                widthFactor: w,
                alignment: Alignment.centerLeft,
                child: const _SkeletonBox(height: 14),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PAGE: the path
// ─────────────────────────────────────────────────────────────

class LearnOptionXIPage extends StatefulWidget {
  const LearnOptionXIPage({super.key});

  @override
  State<LearnOptionXIPage> createState() => _LearnOptionXIPageState();
}

class _LearnOptionXIPageState extends State<LearnOptionXIPage> {
  late Future<(List<OnboardingModule>, bool)> _future;

  @override
  void initState() {
    super.initState();
    _future = OnboardingClient.fetchLessons();
  }

  void _refresh() => setState(() {
        _future = OnboardingClient.fetchLessons();
      });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DColors.scaffold,
      appBar: AppBar(
        backgroundColor: DColors.scaffold,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: DColors.ink, size: 26),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: const Text(
          'Learn OptionXI',
          style: TextStyle(
            color: DColors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 19,
          ),
        ),
      ),
      body: FutureBuilder<(List<OnboardingModule>, bool)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _LearnPathSkeleton();
          }
          if (snap.hasError || !snap.hasData) {
            return _ErrorState(onRetry: _refresh);
          }
          final (modules, isPremium) = snap.data!;
          final allLessons = modules.expand((m) => m.lessons).toList();
          final completed = allLessons.where((l) => l.completed).length;
          final totalXp = allLessons
              .where((l) => l.completed)
              .fold<int>(0, (sum, l) => sum + l.xpReward);

          return RefreshIndicator(
            color: DColors.green,
            onRefresh: () async => _refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _HeaderStats(
                    completed: completed,
                    total: allLessons.length,
                    xp: totalXp,
                  ),
                ),
                SliverToBoxAdapter(
                  child: DailyQuestStrip(isPremium: isPremium),
                ),
                for (final module in modules)
                  SliverToBoxAdapter(
                    child: _ModuleSection(module: module, onChanged: _refresh),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header: greeting + streak
// ─────────────────────────────────────────────────────────────

class _HeaderStats extends StatelessWidget {
  final int completed;
  final int total;
  final int xp;

  const _HeaderStats(
      {required this.completed, required this.total, required this.xp});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DColors.blue.withOpacity(0.08),
      padding: const EdgeInsets.only(
        top: 8,
        bottom: 14,
        left: 16,
        right: 16,
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          // slim linear progress
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : completed / total,
              minHeight: 16,
              backgroundColor: DColors.border,
              valueColor: const AlwaysStoppedAnimation(DColors.gold),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                completed == total
                    ? 'Course complete — legend!'
                    : '$completed of $total lessons',
                style: const TextStyle(
                  color: DColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                '$xp XP',
                style: const TextStyle(
                  color: DColors.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: DColors.grey),
            const SizedBox(height: 12),
            const Text('Could not load your lessons right now.',
                style: TextStyle(color: DColors.ink)),
            const SizedBox(height: 16),
            SizedBox(
              width: 180,
              child: DButton(text: 'Try again', onPressed: onRetry),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Daily quests — horizontal strip
// ─────────────────────────────────────────────────────────────

class DailyQuestStrip extends StatefulWidget {
  final bool isPremium;
  const DailyQuestStrip({super.key, required this.isPremium});

  @override
  State<DailyQuestStrip> createState() => _DailyQuestStripState();
}

class _DailyQuestStripState extends State<DailyQuestStrip> {
  late Future<(bool, List<DailyQuest>)> _future;

  @override
  void initState() {
    super.initState();
    _future = OnboardingClient.fetchTodayQuests();
  }

  Future<void> _complete(DailyQuest quest) async {
    try {
      final xp = await OnboardingClient.completeQuest(quest.id);
      if (!mounted) return;
      setState(() => _future = OnboardingClient.fetchTodayQuests());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DColors.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('Quest complete · +$xp XP',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, List<DailyQuest>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _Shimmer(
              child: _SkeletonBox(height: 118, radius: 16),
            ),
          );
        }
        if (!snap.hasData) return const SizedBox(height: 8);
        final (locked, quests) = snap.data!;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.bolt_rounded, color: DColors.gold, size: 22),
                  SizedBox(width: 6),
                  Text(
                    "Today's Quests",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: DColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (locked)
                _QuestLockedCard(
                  onUnlock: () => _showPremiumSheet(context),
                )
              else
                SizedBox(
                  height: 118,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: quests.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => _QuestCard(
                      quest: quests[i],
                      onComplete: () => _complete(quests[i]),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showPremiumSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PremiumSheet(
        onSubscribe: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const SubscriptionScreenRazorPay()),
          );
        },
      ),
    );
  }
}

class _QuestCard extends StatelessWidget {
  final DailyQuest quest;
  final VoidCallback onComplete;
  const _QuestCard({required this.quest, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: quest.completed ? DColors.cardGreen : DColors.cardBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              quest.completed ? DColors.green : DColors.blue.withOpacity(0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                quest.completed
                    ? Icons.check_circle_rounded
                    : Icons.bolt_rounded,
                size: 18,
                color: quest.completed ? DColors.green : DColors.blue,
              ),
              const SizedBox(width: 4),
              Text(
                '+${quest.xpReward} XP',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: quest.completed ? DColors.green : DColors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            quest.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: DColors.ink, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            quest.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: DColors.grey, fontSize: 12),
          ),
          const Spacer(),
          if (!quest.completed)
            GestureDetector(
              onTap: onComplete,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: DColors.blue,
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(
                      bottom: BorderSide(color: DColors.blueDark, width: 3)),
                ),
                child: const Text(
                  'DONE',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuestLockedCard extends StatelessWidget {
  final VoidCallback onUnlock;
  const _QuestLockedCard({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DColors.lockedFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, color: DColors.grey),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Fresh quests drop every day — Premium only.',
              style:
                  TextStyle(color: DColors.grey, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: onUnlock,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: DColors.gold,
                borderRadius: BorderRadius.circular(12),
                border: const Border(
                    bottom: BorderSide(color: DColors.orange, width: 3)),
              ),
              child: const Text('UNLOCK',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Premium bottom sheet
// ─────────────────────────────────────────────────────────────

class _PremiumSheet extends StatelessWidget {
  final VoidCallback onSubscribe;
  const _PremiumSheet({required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
                color: DColors.border, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(height: 20),
          const Icon(Icons.diamond_rounded, size: 56, color: DColors.gold),
          const SizedBox(height: 12),
          const Text('OptionXI Premium',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: DColors.ink)),
          const SizedBox(height: 8),
          const Text(
            'Unlock every lesson, remove the grind, get fresh daily quests.',
            textAlign: TextAlign.center,
            style: TextStyle(color: DColors.grey),
          ),
          const SizedBox(height: 20),
          DButton(
            text: 'Subscribe Now',
            color: DColors.gold,
            shadow: DColors.orange,
            onPressed: onSubscribe,
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Text('Maybe later',
                style: TextStyle(
                    color: DColors.blue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Module — winding "S" path of chunky nodes, joined by drawn lines
// ─────────────────────────────────────────────────────────────

/// Vertical distance between the centers of two consecutive path nodes.
const double _kNodeRowHeight = 92;

/// Diameter of the chunky node circle (its "top face").
const double _kNodeDiameter = 66;

/// Extra headroom above the very first node so the "START" bubble never
/// gets clipped.
const double _kPathTopPadding = 46;

/// Horizontal winding offsets: center → right → left → center…
/// (fraction of the available half-width, -1..1)
const List<double> _kNodeOffsets = [0.0, -0.55, 0.55, -0.35, 0.35];

class _ModuleSection extends StatelessWidget {
  final OnboardingModule module;
  final VoidCallback onChanged;

  const _ModuleSection({required this.module, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        children: [
          // module banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color:
                  module.progress == 1.0 ? DColors.cardGreen : DColors.cardBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  module.progress == 1.0
                      ? Icons.emoji_events_rounded
                      : Icons.auto_stories_rounded,
                  color: module.progress == 1.0 ? DColors.green : DColors.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: DColors.ink,
                        ),
                      ),
                      if (module.description != null)
                        Text(
                          module.description!,
                          style: const TextStyle(
                              color: DColors.grey, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (module.progress == 1.0)
                  const Icon(Icons.check_circle_rounded, color: DColors.green),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _WindingPath(module: module, onOpen: (l) => _openLesson(context, l)),
        ],
      ),
    );
  }

  void _openLesson(BuildContext context, OnboardingLesson lesson) async {
    if (lesson.locked) {
      if (lesson.requiresPremium) {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _PremiumSheet(
            onSubscribe: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SubscriptionScreenRazorPay()),
              );
            },
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text('Finish the previous lesson first 🎯'),
          ),
        );
      }
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LessonDetailPage(lesson: lesson)),
    );
    if (changed == true) onChanged();
  }
}

/// Lays the lessons of a module out along the winding "S" curve and paints
/// the connecting line between each node and the next, based on each
/// node's actual computed center — so the line always meets the node
/// exactly, however the offsets/spacing are tuned.
class _WindingPath extends StatelessWidget {
  final OnboardingModule module;
  final void Function(OnboardingLesson lesson) onOpen;

  const _WindingPath({required this.module, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final lessons = module.lessons;
    if (lessons.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final centers = <Offset>[
          for (int i = 0; i < lessons.length; i++)
            Offset(
              width / 2 +
                  _kNodeOffsets[i % _kNodeOffsets.length] *
                      (width / 2 - _kNodeDiameter),
              _kPathTopPadding + i * _kNodeRowHeight + _kNodeDiameter / 2,
            ),
        ];
        final totalHeight = _kPathTopPadding +
            (lessons.length - 1) * _kNodeRowHeight +
            _kNodeDiameter +
            24;

        return SizedBox(
          height: totalHeight,
          width: width,
          child: Stack(
            children: [
              // connecting lines, drawn first so nodes sit on top
              Positioned.fill(
                child: CustomPaint(painter: _PathLinePainter(centers: centers)),
              ),
              for (int i = 0; i < lessons.length; i++) ...[
                if (!lessons[i].completed && !lessons[i].locked)
                  Positioned(
                    left: (centers[i].dx - 80).clamp(0.0, width - 160),
                    top: centers[i].dy - _kNodeDiameter / 2 - 44,
                    width: 160,
                    child: Center(child: _StartBubble(label: lessons[i].title)),
                  ),
                Positioned(
                  left: centers[i].dx - _kNodeDiameter / 2 - 3,
                  top: centers[i].dy - _kNodeDiameter / 2 - 3,
                  child: _PathNode(
                    lesson: lessons[i],
                    isCurrent: !lessons[i].completed && !lessons[i].locked,
                    onTap: () => onOpen(lessons[i]),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Draws a smooth curve through every node center — the "line connecting
/// the nodes" along the winding path.
class _PathLinePainter extends CustomPainter {
  final List<Offset> centers;
  const _PathLinePainter({required this.centers});

  @override
  void paint(Canvas canvas, Size size) {
    if (centers.length < 2) return;

    final linePaint = Paint()
      ..color = DColors.border
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(centers.first.dx, centers.first.dy);
    for (int i = 1; i < centers.length; i++) {
      final prev = centers[i - 1];
      final curr = centers[i];
      final midY = (prev.dy + curr.dy) / 2;
      // cubic bezier through a shared midpoint keeps the curve smooth
      // through the S-shape regardless of how far left/right each node sits.
      path.cubicTo(prev.dx, midY, curr.dx, midY, curr.dx, curr.dy);
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _PathLinePainter oldDelegate) =>
      oldDelegate.centers != centers;
}

// ─────────────────────────────────────────────────────────────
// Chunky 3D path node
// ─────────────────────────────────────────────────────────────

class _PathNode extends StatelessWidget {
  final OnboardingLesson lesson;
  final bool isCurrent;
  final VoidCallback onTap;

  const _PathNode({
    required this.lesson,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color edge;
    final IconData icon;
    final Color iconColor;

    if (lesson.completed) {
      fill = DColors.green;
      edge = DColors.greenDark;
      icon = Icons.star_rounded;
      iconColor = Colors.white;
    } else if (lesson.locked) {
      fill = DColors.lockedFill;
      edge = const Color(0xFFDADADA);
      icon = Icons.lock_rounded;
      iconColor = const Color(0xFFAFAFAF);
    } else {
      fill = DColors.blue;
      edge = DColors.blueDark;
      icon = Icons.star_rounded;
      iconColor = Colors.white;
    }

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _kNodeDiameter + 6,
        height: _kNodeDiameter + 6,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // bottom "3D" edge
            Container(
              width: _kNodeDiameter,
              height: _kNodeDiameter,
              decoration: BoxDecoration(color: edge, shape: BoxShape.circle),
            ),
            // top face
            Container(
              width: _kNodeDiameter,
              height: _kNodeDiameter - 6,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            if (isCurrent)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: DColors.blue.withOpacity(0.35),
                          blurRadius: 18,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StartBubble extends StatelessWidget {
  final String label;
  const _StartBubble({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DColors.border, width: 2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: const Text(
        'START',
        style: TextStyle(
          color: DColors.blue,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LESSON FLOW: read (+ video) → quiz (select only, no grading yet)
//              → Finish → server grades everything at once → result
// ─────────────────────────────────────────────────────────────

class LessonDetailPage extends StatefulWidget {
  final OnboardingLesson lesson;
  const LessonDetailPage({super.key, required this.lesson});

  @override
  State<LessonDetailPage> createState() => _LessonDetailPageState();
}

class _LessonDetailPageState extends State<LessonDetailPage> {
  bool _showQuiz = false;
  bool _submitting = false;
  LessonResult? _result;
  final Map<String, int> _answers = {};

  late Future<LessonContent> _content;

  @override
  void initState() {
    super.initState();
    _content = OnboardingClient.fetchLessonContent(widget.lesson.id);
  }

  /// Called only once, when the user taps Finish on the last question.
  /// Nothing is graded before this point — the client has no correct
  /// answers to grade against, by design (see fastapi_onboarding.dart).
  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final result =
          await OnboardingClient.submitLesson(widget.lesson.id, _answers);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Resets local quiz state so "Try again" replays the quiz instead of
  /// just leaving the page.
  void _retry() {
    setState(() {
      _result = null;
      _answers.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        // back button
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: DColors.ink, size: 26),
          onPressed: () => Navigator.pop(context, false),
        ),
        titleSpacing: 0,
        // heading
        title: Text(
          widget.lesson.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: DColors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _showQuiz ? 0.66 : 0.33,
                minHeight: 14,
                backgroundColor: DColors.border,
                valueColor: const AlwaysStoppedAnimation(DColors.green),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: FutureBuilder<LessonContent>(
            future: _content,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const _LessonBodySkeleton();
              }
              if (snap.hasError || !snap.hasData) {
                return Center(
                    child: Text(
                        'Could not load this lesson.\n${snap.error ?? ""}'));
              }
              final content = snap.data!;

              if (_result != null) {
                return _ResultView(
                  result: _result!,
                  questions: content.quiz,
                  answers: _answers,
                  onContinue: () => Navigator.pop(context, _result!.passed),
                  onRetry: _retry,
                );
              }
              if (_showQuiz) {
                return _QuizView(
                  questions: content.quiz,
                  answers: _answers,
                  onAnswer: (qid, i) => setState(() => _answers[qid] = i),
                  submitting: _submitting,
                  onFinish: _submit,
                );
              }
              return _BodyView(
                body: content.body,
                videoUrl: content.videoUrl,
                lesson: widget.lesson,
                onContinue: () => setState(() => _showQuiz = true),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Reading screen (+ optional YouTube reference video)
// ─────────────────────────────────────────────────────────────

class _BodyView extends StatelessWidget {
  final String body;
  final String? videoUrl;
  final OnboardingLesson lesson;
  final VoidCallback onContinue;
  const _BodyView({
    required this.body,
    required this.onContinue,
    required this.lesson,
    this.videoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lesson',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: DColors.ink,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (videoUrl != null && videoUrl!.isNotEmpty)
                  _YoutubeReferenceCard(videoUrl: videoUrl!),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: DColors.border),
                  ),
                  child: Text(
                    body,
                    style: const TextStyle(
                        fontSize: 16, height: 1.6, color: DColors.ink),
                  ),
                ),
                // NEW: action route button, shown right below the body
                if (lesson.actionRoute != null) ...[
                  const SizedBox(height: 16),
                  DButton(
                    text: lesson.actionLabel ?? 'Try it now',
                    color: DColors.purple,
                    shadow: const Color(0xFFA85CE0),
                    icon: Icons.rocket_launch_rounded,
                    onPressed: () => Get.toNamed(lesson.actionRoute!),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        DButton(
            text: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: onContinue),
      ],
    );
  }
}

/// A tappable thumbnail + "Watch on YouTube" card. Opens the video in the
/// YouTube app (or browser) via url_launcher rather than embedding a
/// player, so no extra native setup/webview dependency is required.
///
/// pubspec.yaml needs:
///   url_launcher: ^6.3.0
class _YoutubeReferenceCard extends StatelessWidget {
  final String videoUrl;
  const _YoutubeReferenceCard({required this.videoUrl});

  String? get _videoId {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null) return null;
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    if (uri.pathSegments.contains('shorts') ||
        uri.pathSegments.contains('embed')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
    }
    return uri.queryParameters['v'];
  }

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the video link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _videoId;
    final thumbnail =
        id != null ? 'https://img.youtube.com/vi/$id/hqdefault.jpg' : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => _open(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DColors.border),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: thumbnail != null
                      ? Image.network(
                          thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: DColors.lockedFill),
                        )
                      : Container(color: DColors.lockedFill),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 32),
                ),
                Positioned(
                  left: 12,
                  bottom: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.ondemand_video_rounded,
                            color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Watch on YouTube',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
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

// ─────────────────────────────────────────────────────────────
// Quiz — one question at a time, selection only. Nothing is marked
// right/wrong here; that only happens once Finish submits every
// answer and the server grades the whole set at once.
// ─────────────────────────────────────────────────────────────

class _QuizView extends StatefulWidget {
  final List<QuizQuestion> questions;
  final Map<String, int> answers;
  final void Function(String questionId, int index) onAnswer;
  final bool submitting;
  final VoidCallback onFinish;

  const _QuizView({
    required this.questions,
    required this.answers,
    required this.onAnswer,
    required this.submitting,
    required this.onFinish,
  });

  @override
  State<_QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<_QuizView> {
  int _index = 0;

  QuizQuestion get _q => widget.questions[_index];
  bool get _isLast => _index == widget.questions.length - 1;

  /// The answer already recorded for the *current* question, if any —
  /// so re-visiting a question (or rebuilding) keeps its selection.
  int? get _selected => widget.answers[_q.id];

  void _select(int i) {
    // Just records the choice and re-renders the highlight — no
    // correctness check happens client-side.
    widget.onAnswer(_q.id, i);
    setState(() {});
  }

  void _next() {
    if (_selected == null) return; // guard: button is disabled anyway
    if (_isLast) {
      widget.onFinish();
      return;
    }
    setState(() => _index++);
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // progress dots — filled once a question has a recorded answer
        Row(
          children: [
            for (int i = 0; i < widget.questions.length; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(
                      right: i == widget.questions.length - 1 ? 0 : 5),
                  decoration: BoxDecoration(
                    color: widget.answers.containsKey(widget.questions[i].id)
                        ? DColors.green
                        : (i == _index ? DColors.blue : DColors.border),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _q.prompt,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: DColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (int i = 0; i < _q.options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _QuizOption(
                      text: _q.options[i],
                      index: i,
                      selected: _selected == i,
                      onTap: () => _select(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            if (_index > 0) ...[
              SizedBox(
                width: 96,
                child: DButton(
                  text: 'Back',
                  color: Colors.white,
                  shadow: DColors.border,
                  textColor: DColors.ink,
                  onPressed: widget.submitting ? null : _back,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: DButton(
                text: _isLast ? 'Finish' : 'Continue',
                color: DColors.green,
                shadow: DColors.greenDark,
                icon:
                    _isLast ? Icons.flag_rounded : Icons.arrow_forward_rounded,
                onPressed:
                    (_selected == null || widget.submitting) ? null : _next,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuizOption extends StatelessWidget {
  final String text;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  const _QuizOption({
    required this.text,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected ? DColors.blue : DColors.border;
    final bg = selected ? DColors.cardBlue : Colors.white;
    final edge = selected ? DColors.blueDark : DColors.border;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Colors.white : const Color(0xFFF1F1F1),
                borderRadius: BorderRadius.circular(8),
                border: Border(bottom: BorderSide(color: edge, width: 2)),
              ),
              child: Text(
                String.fromCharCode(65 + index),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? DColors.blue : DColors.grey,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: DColors.ink),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: DColors.blue),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Result — celebration screen + per-question right/wrong breakdown,
// filled in only once the server has graded the submission.
// ─────────────────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  final LessonResult result;
  final List<QuizQuestion> questions;
  final Map<String, int> answers;

  final VoidCallback onContinue;
  final VoidCallback onRetry;

  const _ResultView({
    required this.result,
    required this.questions,
    required this.answers,
    required this.onContinue,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // NEW

            children: [
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.3, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: result.passed
                        ? DColors.cardGreen
                        : const Color(0xFFFFF1DC),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: result.passed ? DColors.green : DColors.orange,
                      width: 4,
                    ),
                  ),
                  child: Icon(
                    result.passed
                        ? Icons.emoji_events_rounded
                        : Icons.refresh_rounded,
                    size: 56,
                    color: result.passed ? DColors.green : DColors.orange,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                result.passed ? 'Lesson complete!' : 'So close!',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: DColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                result.passed
                    ? 'You scored ${result.score}%'
                    : 'You scored ${result.score}% — try once more',
                style: const TextStyle(color: DColors.grey, fontSize: 15),
              ),
              if (result.passed) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: DColors.cardBlue,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: DColors.blue.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded,
                          color: DColors.gold, size: 22),
                      const SizedBox(width: 6),
                      Text(
                        '+${result.xpAwarded} XP',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: DColors.blue,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (result.breakdown.isNotEmpty) ...[
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Answer review',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: DColors.ink),
                  ),
                ),
                const SizedBox(height: 10),
                for (final q in questions)
                  _ReviewRow(question: q, result: result),
              ],
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DButton(
                  text: result.passed ? 'Continue' : 'Try again',
                  color: result.passed ? DColors.green : DColors.orange,
                  shadow: result.passed
                      ? DColors.greenDark
                      : const Color(0xFFD97B00),
                  onPressed: result.passed ? onContinue : onRetry,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    });
  }
}

/// One row of the "Answer review" list — shows the question, the option
/// the user picked, and a right/wrong indicator sourced entirely from the
/// server's [QuestionResult] for that question id.
class _ReviewRow extends StatelessWidget {
  final QuizQuestion question;
  final LessonResult result;

  const _ReviewRow({required this.question, required this.result});

  @override
  Widget build(BuildContext context) {
    final qr = result.breakdown
        .where((r) => r.questionId == question.id)
        .cast<QuestionResult?>()
        .firstWhere((_) => true, orElse: () => null);
    if (qr == null) return const SizedBox.shrink();

    final pickedText =
        (qr.selectedIndex >= 0 && qr.selectedIndex < question.options.length)
            ? question.options[qr.selectedIndex]
            : '—';
    final correctText =
        (qr.correctIndex != null && qr.correctIndex! < question.options.length)
            ? question.options[qr.correctIndex!]
            : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: qr.correct ? DColors.cardGreen : const Color(0xFFFFE5E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: qr.correct ? DColors.green : DColors.red,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            qr.correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: qr.correct ? DColors.green : DColors.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.prompt,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: DColors.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your answer: $pickedText',
                  style: const TextStyle(fontSize: 13, color: DColors.grey),
                ),
                if (!qr.correct && correctText != null)
                  Text(
                    'Correct answer: $correctText',
                    style: const TextStyle(
                        fontSize: 13,
                        color: DColors.greenDark,
                        fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
