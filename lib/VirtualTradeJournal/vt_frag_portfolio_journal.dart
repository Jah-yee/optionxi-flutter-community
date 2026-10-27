import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:optionxi/Main_Pages/Leaderboard/act_leaderboard.dart';
import 'package:optionxi/VirtualTradeJournal/act_journal_analytics.dart';
import 'package:optionxi/VirtualTradeJournal/bottom_exit_position_dialog.dart';
import 'package:optionxi/VirtualTradeJournal/edit_basket_page.dart';
import 'package:optionxi/VirtualTradeJournal/edit_journal_page.dart';
import 'package:optionxi/VirtualTradeJournal/journal_stats_sheet.dart';
import 'package:optionxi/VirtualTradeJournal/journal_ui_kit.dart';
import 'package:optionxi/VirtualTradeJournal/portfolio_journal_controller.dart';
import 'package:optionxi/VirtualTrading/VComponents/cust_pulsating_effect.dart';
import 'package:optionxi/VirtualTrading/VDataModel/v_holdings_journal.dart';
import 'package:optionxi/VirtualTrading/VDataModel/v_tradehistory.dart';
import 'package:timeago/timeago.dart' as timeago;

// ═════════════════════════════════════════════════════════════════════════
//  Journal screen:  [ Open trades ]  [ Closed trades ]
//
//  Words used on screen (plain language):
//    Bought            = a normal buy ("long")
//    Sold first        = a short sell
//    Running P&L       = profit/loss on trades that are still open
//    Booked P&L        = profit/loss you locked in by closing trades
//    Safety exit       = your stop-loss
//    Goal              = your target
// ═════════════════════════════════════════════════════════════════════════

class PortfolioFragmentJournal extends StatefulWidget {
  final LeaderboardEntry? user;
  const PortfolioFragmentJournal(this.user, {Key? key}) : super(key: key);

  @override
  State<PortfolioFragmentJournal> createState() =>
      _PortfolioFragmentJournalState();
}

class _PortfolioFragmentJournalState extends State<PortfolioFragmentJournal>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final PortfolioJournalController controller;

  /// Every screen instance gets its OWN controller.
  ///
  /// Before, all instances shared one un-tagged controller and the first one
  /// to be disposed deleted it for everybody. That happens whenever this
  /// screen is mounted twice at once (the tab switch cross-fade, or the Basket
  /// full page opened over the Live tab) and it left the visible screen
  /// holding a dead controller – i.e. positions that "sometimes" don't show.
  late final String _tag;

  bool get _isOwner {
    final target = widget.user?.suid;
    if (target == null || target.isEmpty) return true;
    return target == FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  void initState() {
    super.initState();
    _tag = 'journal_${widget.user?.suid ?? 'me'}_${identityHashCode(this)}';
    controller = Get.put(
      PortfolioJournalController(suid: widget.user?.suid),
      tag: _tag,
    );
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    Get.delete<PortfolioJournalController>(tag: _tag);
    super.dispose();
  }

  // ── Navigation / sheets ────────────────────────────────────────────────

  void _showScorecard() => showJournalStatsSheet(context, controller);

  void _openAnalytics() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => JournalAnalyticsPage(suid: widget.user?.suid),
        ),
      );

  void _closeTrade(BasketUserHolding h, bool isShort) {
    showExitPositionDialog(context, h, controller.getLtp(h.symbol), isShort);
  }

  void _editTrade(BasketUserHolding h) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditBasketPage(basket: h)),
      );

  void _editJournal(JournalTradeHistory t) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditJournalPage(journal: t)),
      );

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _Hero(controller: controller, onTap: _showScorecard),
        _SyncBanner(controller: controller),
        _Segmented(
          controller: _tabController,
          items: [
            _SegItem(
              label: 'Open trades',
              icon: Icons.show_chart_rounded,
              count: () =>
                  controller.holdings.length + controller.shortPositions.length,
            ),
            _SegItem(
              label: 'Closed trades',
              icon: Icons.task_alt_rounded,
              count: () => controller.tradeHistory.length,
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _OpenTradesTab(
                controller: controller,
                canManage: _isOwner,
                onClose: _closeTrade,
                onEdit: _editTrade,
              ),
              _ClosedTradesTab(
                controller: controller,
                canManage: _isOwner,
                onEdit: _editJournal,
                onOpenAnalytics: _openAnalytics,
                // onOpenAnalytics: () => (),
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: JT.bg(context),
      body: widget.user != null ? content : SafeArea(child: content),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Header
// ═════════════════════════════════════════════════════════════════════════

class _Hero extends StatelessWidget {
  final PortfolioJournalController controller;
  final VoidCallback onTap;
  const _Hero({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final loading = controller.isLoading.value;
      final total = controller.totalProfit.value;
      final running = controller.unrealisedPnl.value;
      final booked = controller.realisedPnl.value;
      final invested = controller.totalInvestment.value;
      final color = loading ? JT.text3(context) : JT.pnl(total);

      return JtPressable(
        onTap: loading ? null : onTap,
        haptic: true,
        pressedScale: 0.985,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                JT.tint(context, color, 0.15),
                JT.surface(context),
              ],
            ),
            border: Border.all(color: color.withOpacity(0.22)),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black.withOpacity(JT.isDark(context) ? 0.25 : 0.06),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: loading
              ? const _HeroSkeleton()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Overall profit / loss',
                                  style: JT.caption(context, size: 12)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: PulsatingEffect(
                                        value: total,
                                        child: JtCount(
                                          value: total,
                                          format: (v) =>
                                              jtMoney(v, signed: true),
                                          style: JT.number(context,
                                              size: 30, color: color),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    child: Icon(
                                      total >= 0
                                          ? Icons.arrow_upward_rounded
                                          : Icons.arrow_downward_rounded,
                                      key: ValueKey(total >= 0),
                                      size: 20,
                                      color: color,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('In the market',
                                style: JT.caption(context, size: 12)),
                            const SizedBox(height: 6),
                            JtCount(
                              value: invested,
                              format: (v) => jtMoney(v),
                              style: JT.number(context, size: 16),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _MiniStat(label: 'Running', value: running),
                              _MiniStat(label: 'Booked', value: booked),
                            ],
                          ),
                        ),
                        Text('Details',
                            style:
                                JT.caption(context, size: 12, color: JT.blue)),
                        const Icon(Icons.chevron_right_rounded,
                            size: 18, color: JT.blue),
                      ],
                    ),
                  ],
                ),
        ),
      );
    });
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JtSkeleton(width: 120, height: 12),
          SizedBox(height: 10),
          JtSkeleton(width: 190, height: 30, radius: 10),
          SizedBox(height: 14),
          Row(
            children: [
              JtSkeleton(width: 96, height: 24, radius: 10),
              SizedBox(width: 8),
              JtSkeleton(width: 96, height: 24, radius: 10),
            ],
          ),
        ],
      );
}

class _MiniStat extends StatelessWidget {
  final String label;
  final double value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = JT.pnl(value);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: JT.tint(context, color, 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label  ', style: JT.caption(context, size: 11)),
          Text(jtMoney(value, signed: true),
              style: JT.number(context, size: 12, color: color)),
        ],
      ),
    );
  }
}

/// Slim banner shown when a refresh failed but we still have data to show.
class _SyncBanner extends StatelessWidget {
  final PortfolioJournalController controller;
  const _SyncBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hasData = controller.holdings.isNotEmpty ||
          controller.shortPositions.isNotEmpty ||
          controller.tradeHistory.isNotEmpty;
      final show =
          controller.hasError.value && !controller.isLoading.value && hasData;
      return AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: !show
            ? const SizedBox(width: double.infinity)
            : Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
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
                      loading: controller.isRefreshing.value,
                      onTap: controller.fetchAllData,
                    ),
                  ],
                ),
              ),
      );
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Animated segmented tab switch
// ═════════════════════════════════════════════════════════════════════════

class _SegItem {
  final String label;
  final IconData icon;
  final int Function() count;
  const _SegItem(
      {required this.label, required this.icon, required this.count});
}

class _Segmented extends StatelessWidget {
  final TabController controller;
  final List<_SegItem> items;
  const _Segmented({required this.controller, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.all(4),
      height: 54,
      decoration: BoxDecoration(
        color: JT.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JT.border(context)),
      ),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth / items.length;
          final anim = controller.animation!;
          return Stack(
            children: [
              // Sliding pill that follows the swipe.
              AnimatedBuilder(
                animation: anim,
                builder: (_, __) => Positioned(
                  left: anim.value * w,
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
              ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          controller.animateTo(i);
                        },
                        child: _SegLabel(
                          item: items[i],
                          index: i,
                          animation: anim,
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

class _SegLabel extends StatelessWidget {
  final _SegItem item;
  final int index;
  final Animation<double> animation;
  const _SegLabel(
      {required this.item, required this.index, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t =
            (1 - (animation.value - index).abs()).clamp(0.0, 1.0).toDouble();
        final color = Color.lerp(JT.text2(context), Colors.white, t)!;
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Obx(() {
                final n = item.count();
                if (n <= 0) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Color.lerp(JT.tint(context, JT.text2(context), 0.15),
                        Colors.white.withOpacity(0.25), t),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$n',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color)),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Shared small pieces
// ═════════════════════════════════════════════════════════════════════════

/// Cards slide + fade in, staggered (only the first screenful is delayed).
Widget _enter(Widget child, int index) => child
    .animate(delay: Duration(milliseconds: index < 8 ? index * 45 : 0))
    .fadeIn(duration: const Duration(milliseconds: 320), curve: Curves.easeOut)
    .slideY(
      begin: 0.05,
      end: 0,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );

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
            ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(
                  begin: -3,
                  end: 3,
                  duration: const Duration(milliseconds: 1700),
                  curve: Curves.easeInOut,
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

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: JT.card(context),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                JtSkeleton(width: 44, height: 44, radius: 12),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      JtSkeleton(width: 110, height: 14),
                      SizedBox(height: 8),
                      JtSkeleton(width: 70, height: 11),
                    ],
                  ),
                ),
                JtSkeleton(width: 70, height: 18),
              ],
            ),
            SizedBox(height: 16),
            JtSkeleton(height: 56, radius: 14),
            SizedBox(height: 12),
            JtSkeleton(height: 40, radius: 12),
          ],
        ),
      );
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: const [
          _SkeletonCard(),
          SizedBox(height: 12),
          _SkeletonCard(),
          SizedBox(height: 12),
          _SkeletonCard(),
        ],
      );
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) => _EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'We couldn\'t load your trades',
        subtitle: 'Please check your internet connection and try again.',
        action: JtButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          filled: true,
          onTap: onRetry,
        ),
      );
}

/// A little "Label / value" pair used inside cards.
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

class _VDivider extends StatelessWidget {
  const _VDivider();
  @override
  Widget build(BuildContext context) => Container(
      height: 28,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: JT.border(context));
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

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

class _NoteBlock extends StatelessWidget {
  final String text;
  const _NoteBlock({required this.text});

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

class _ExpandHint extends StatelessWidget {
  final bool expanded;
  const _ExpandHint({required this.expanded});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(expanded ? 'Less' : 'Details',
              style: JT.caption(context, size: 12, color: JT.text2(context))),
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 220),
            child: Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: JT.text2(context)),
          ),
        ],
      );
}

// ═════════════════════════════════════════════════════════════════════════
//  OPEN TRADES TAB
// ═════════════════════════════════════════════════════════════════════════

class _OpenTradesTab extends StatefulWidget {
  final PortfolioJournalController controller;
  final bool canManage;
  final void Function(BasketUserHolding, bool isShort) onClose;
  final void Function(BasketUserHolding) onEdit;
  const _OpenTradesTab({
    required this.controller,
    required this.canManage,
    required this.onClose,
    required this.onEdit,
  });

  @override
  State<_OpenTradesTab> createState() => _OpenTradesTabState();
}

class _OpenTradesTabState extends State<_OpenTradesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  PortfolioJournalController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: c.fetchAllData,
      child: Obx(() {
        // Copy to plain lists so the lazily-built rows below read a stable
        // snapshot and this Obx is the one that reacts to changes.
        final longs = c.holdings.toList();
        final shorts = c.shortPositions.toList();

        if (c.isLoading.value && longs.isEmpty && shorts.isEmpty) {
          return const _LoadingList();
        }
        if (longs.isEmpty && shorts.isEmpty) {
          return _ScrollableMessage(
            child: c.hasError.value
                ? _ErrorState(onRetry: c.fetchAllData)
                : const _EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No open trades yet',
                    subtitle:
                        'When you add a stock to your basket it shows up here '
                        'with live prices.',
                  ),
          );
        }

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            if (longs.isNotEmpty)
              ..._section(
                title: 'Bought stocks',
                subtitle: 'You make money when the price goes up',
                icon: Icons.trending_up_rounded,
                color: JT.profit,
                items: longs,
                isShort: false,
              ),
            if (shorts.isNotEmpty)
              ..._section(
                title: 'Sold-first trades',
                subtitle: 'You make money when the price goes down',
                icon: Icons.trending_down_rounded,
                color: JT.amber,
                items: shorts,
                isShort: true,
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
                child: Text(
                  'Prices update live. Tap a card to see more.',
                  textAlign: TextAlign.center,
                  style:
                      JT.caption(context, size: 12, color: JT.text3(context)),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  List<Widget> _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<BasketUserHolding> items,
    required bool isShort,
  }) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: JtSectionTitle(
            title: title,
            subtitle: subtitle,
            icon: icon,
            color: color,
            count: items.length,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final h = items[i];
              return KeyedSubtree(
                key: ValueKey('${isShort ? 'S' : 'L'}-${h.id ?? h.symbol}'),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _enter(
                    JournalPositionCard(
                      holding: h,
                      controller: c,
                      isShort: isShort,
                      canManage: widget.canManage,
                      onClose: () => widget.onClose(h, isShort),
                      onEdit: () => widget.onEdit(h),
                    ),
                    i,
                  ),
                ),
              );
            },
            childCount: items.length,
          ),
        ),
      ),
    ];
  }
}

/// One open trade.
class JournalPositionCard extends StatefulWidget {
  final BasketUserHolding holding;
  final PortfolioJournalController controller;
  final bool isShort;
  final bool canManage;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  const JournalPositionCard({
    Key? key,
    required this.holding,
    required this.controller,
    required this.isShort,
    required this.canManage,
    required this.onClose,
    required this.onEdit,
  }) : super(key: key);

  @override
  State<JournalPositionCard> createState() => _JournalPositionCardState();
}

class _JournalPositionCardState extends State<JournalPositionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.holding;
    final isShort = widget.isShort;
    final name = jtDisplaySymbol(h.symbol);
    final invested = h.averagePrice * h.quantity;
    final sharesText = '${h.quantity} ${h.quantity == 1 ? 'share' : 'shares'}';
    final hasPlan = (h.stopLossPrice ?? 0) > 0 && (h.targetPrice ?? 0) > 0;

    return Obx(() {
      final hasPrice = widget.controller.hasPrice(h.symbol);
      final ltp = widget.controller.getLtp(h.symbol);
      final dir = isShort ? -1 : 1;
      final pnl = hasPrice ? (ltp - h.averagePrice) * h.quantity * dir : 0.0;
      final pct = (hasPrice && h.averagePrice > 0)
          ? (ltp - h.averagePrice) / h.averagePrice * 100 * dir
          : 0.0;
      final color = hasPrice ? JT.pnl(pnl) : JT.text3(context);
      final worthNow = hasPrice ? ltp * h.quantity : null;
      final headline = !hasPrice
          ? 'Getting live price…'
          : (pnl > 0
              ? 'You\'re up'
              : (pnl < 0 ? 'You\'re down' : 'No change yet'));

      return JtPressable(
        onTap: () => setState(() => _expanded = !_expanded),
        pressedScale: 0.985,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          decoration: JT.card(
            context,
            borderColor: hasPrice ? color.withOpacity(0.28) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Who + price now ──
                Row(
                  children: [
                    JtLogo(symbolKey: jtLogoKey(h.symbol), accent: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: JT.heading(context, size: 16)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              JtDirectionChip(isShort: isShort),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(sharesText,
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
                        Text('Price now', style: JT.caption(context, size: 11)),
                        const SizedBox(height: 2),
                        if (hasPrice)
                          PulsatingEffect(
                            value: ltp,
                            child: Text(jtPrice(ltp),
                                style: JT.number(context, size: 16)),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: JtSkeleton(width: 74, height: 16),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Profit / loss ──
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: JT.tint(context, color, 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(headline,
                                style: JT.caption(context,
                                    size: 12, color: color)),
                            const SizedBox(height: 2),
                            if (hasPrice)
                              JtCount(
                                value: pnl,
                                format: (v) => jtMoney(v.abs()),
                                style:
                                    JT.number(context, size: 24, color: color),
                              )
                            else
                              Text('—',
                                  style: JT.number(context,
                                      size: 24, color: color)),
                          ],
                        ),
                      ),
                      if (hasPrice) JtPctTag(pct: pct),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Numbers ──
                Row(
                  children: [
                    _Metric(label: 'You put in', value: jtMoney(invested)),
                    const _VDivider(),
                    _Metric(
                      label: isShort ? 'Sold at' : 'Bought at',
                      value: jtPrice(h.averagePrice),
                    ),
                    const _VDivider(),
                    _Metric(
                      label: isShort ? 'Cost to buy back' : 'Worth now',
                      value: worthNow == null ? '—' : jtMoney(worthNow),
                      align: CrossAxisAlignment.end,
                    ),
                  ],
                ),

                // ── Plan: safety exit & goal ──
                if (hasPlan) ...[
                  const SizedBox(height: 14),
                  _PlanBar(
                    safetyExit: h.stopLossPrice!,
                    goal: h.targetPrice!,
                    ltp: hasPrice ? ltp : null,
                    isShort: isShort,
                  ),
                ],

                // ── Actions ──
                if (widget.canManage) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: JtButton(
                          label: 'Edit',
                          icon: Icons.edit_outlined,
                          expand: true,
                          height: 42,
                          onTap: widget.onEdit,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: JtButton(
                          label: 'Close trade',
                          icon: Icons.logout_rounded,
                          filled: true,
                          expand: true,
                          height: 42,
                          onTap: widget.onClose,
                        ),
                      ),
                    ],
                  ),
                ],

                // ── Footer ──
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 13, color: JT.text3(context)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text('Opened ${timeago.format(h.entryDate)}',
                          style: JT.caption(context, size: 12)),
                    ),
                    _ExpandHint(expanded: _expanded),
                  ],
                ),

                // ── Details ──
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !_expanded
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
                                    child: _InfoTile(
                                      icon: Icons.event_rounded,
                                      label: isShort ? 'Sold on' : 'Bought on',
                                      value: DateFormat('d MMM yyyy, h:mm a')
                                          .format(h.entryDate.toLocal()),
                                    ),
                                  ),
                                  if (h.timeframe.isNotEmpty) ...[
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _InfoTile(
                                        icon: Icons.schedule_rounded,
                                        label: 'Planned for',
                                        value: h.timeframe,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (h.reason != null &&
                                  h.reason!.trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _NoteBlock(text: h.reason!),
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
    });
  }
}

/// "Your plan": a bar from your safety exit (left) to your goal (right) with
/// a marker showing where the price is now. Same direction for bought and
/// sold-first trades, so left is always "bad" and right is always "good".
class _PlanBar extends StatelessWidget {
  final double safetyExit;
  final double goal;
  final double? ltp;
  final bool isShort;
  const _PlanBar({
    required this.safetyExit,
    required this.goal,
    required this.ltp,
    required this.isShort,
  });

  @override
  Widget build(BuildContext context) {
    final span = isShort ? (safetyExit - goal) : (goal - safetyExit);
    if (span <= 0) return const SizedBox.shrink();

    double? pos;
    String status;
    Color color;
    final price = ltp;
    if (price == null) {
      status = 'Waiting for live price';
      color = JT.text3(context);
    } else {
      final raw =
          isShort ? (safetyExit - price) / span : (price - safetyExit) / span;
      pos = raw.clamp(0.0, 1.0).toDouble();
      final hitSafety = isShort ? price >= safetyExit : price <= safetyExit;
      final hitGoal = isShort ? price <= goal : price >= goal;
      if (hitSafety) {
        status = 'Safety exit reached';
        color = JT.loss;
      } else if (hitGoal) {
        status = 'Goal reached';
        color = JT.profit;
      } else if (pos >= 0.75) {
        status = 'Close to your goal';
        color = JT.profit;
      } else if (pos <= 0.25) {
        status = 'Close to your safety exit';
        color = JT.loss;
      } else {
        status = 'On track';
        color = JT.blue;
      }
    }

    final markerPos = pos; // final copy: safe to use inside the builder below
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: JT.surface2(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JT.border(context)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('Your plan', style: JT.caption(context, size: 12)),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: JT.tint(context, color, 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 18,
            child: LayoutBuilder(
              builder: (ctx, c) {
                final w = c.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: LinearGradient(
                          colors: [
                            JT.lossBright.withOpacity(0.55),
                            JT.amber.withOpacity(0.45),
                            JT.profitBright.withOpacity(0.55),
                          ],
                        ),
                      ),
                    ),
                    if (markerPos != null)
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: markerPos),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (_, t, __) => Positioned(
                          left: (w - 16) * t,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: JT.surface(context),
                              shape: BoxShape.circle,
                              border: Border.all(color: color, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.35),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Safety exit',
                      style: JT.caption(context, size: 11, color: JT.loss)),
                  Text(jtPrice(safetyExit),
                      style: JT.number(context, size: 12)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Goal',
                      style: JT.caption(context, size: 11, color: JT.profit)),
                  Text(jtPrice(goal), style: JT.number(context, size: 12)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  CLOSED TRADES TAB
// ═════════════════════════════════════════════════════════════════════════

class _DayHeader {
  final DateTime day;
  final double total;
  final int count;
  const _DayHeader(this.day, this.total, this.count);
}

class _ClosedTradesTab extends StatefulWidget {
  final PortfolioJournalController controller;
  final bool canManage;
  final void Function(JournalTradeHistory) onEdit;
  final VoidCallback onOpenAnalytics;
  const _ClosedTradesTab({
    required this.controller,
    required this.canManage,
    required this.onEdit,
    required this.onOpenAnalytics,
  });

  @override
  State<_ClosedTradesTab> createState() => _ClosedTradesTabState();
}

class _ClosedTradesTabState extends State<_ClosedTradesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  PortfolioJournalController get c => widget.controller;

  /// Which cards are open. Keyed by trade id (not hashCode, which changed on
  /// every refetch and collapsed everything).
  final Set<int> _expanded = {};

  /// One flat list of day headers + trades. Because headers and trades live
  /// in the same list, index maths can never skip a trade (the old version
  /// hid the newest closed trade behind the "analytics" banner slot).
  List<Object> _flatten(List<JournalTradeHistory> trades) {
    final byDay = <DateTime, List<JournalTradeHistory>>{};
    for (final t in trades) {
      final d = t.exitDate.toLocal();
      final day = DateTime(d.year, d.month, d.day);
      byDay.putIfAbsent(day, () => []).add(t);
    }
    final out = <Object>[];
    byDay.forEach((day, list) {
      final total = list.fold<double>(0, (s, t) => s + t.profitLoss);
      out.add(_DayHeader(day, total, list.length));
      out.addAll(list);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: c.fetchAllData,
      child: Obx(() {
        final trades = c.tradeHistory.toList();
        final loadingFirst = c.isLoading.value && trades.isEmpty;
        final items = _flatten(trades);

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _PeriodSummary(controller: c)),
            SliverToBoxAdapter(child: _PeriodChips(controller: c)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _AnalyticsBanner(onTap: widget.onOpenAnalytics),
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: c.isHistoryLoading.value
                    ? const Padding(
                        key: ValueKey('bar'),
                        padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(4)),
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                      )
                    : const SizedBox(key: ValueKey('none'), height: 3),
              ),
            ),
            if (loadingFirst)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _SkeletonCard(),
                ),
              )
            else if (items.isEmpty)
              SliverToBoxAdapter(
                child: c.hasError.value
                    ? _ErrorState(onRetry: c.fetchAllData)
                    : _EmptyState(
                        icon: Icons.history_toggle_off_rounded,
                        title: 'No closed trades in this period',
                        subtitle:
                            'When you close a trade it\'s saved here so you '
                            'can look back on what worked. Try a longer '
                            'period above.',
                      ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final item = items[i];
                      if (item is _DayHeader) {
                        return _DayHeaderRow(header: item);
                      }
                      final t = item as JournalTradeHistory;
                      return KeyedSubtree(
                        key: ValueKey('T-${t.id}-${t.orderId}'),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _enter(
                            JournalTradeCard(
                              trade: t,
                              canEdit: widget.canManage,
                              isExpanded: _expanded.contains(t.id),
                              onToggle: () => setState(() {
                                if (!_expanded.add(t.id))
                                  _expanded.remove(t.id);
                              }),
                              onEdit: () => widget.onEdit(t),
                            ),
                            i,
                          ),
                        ),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _DayHeaderRow extends StatelessWidget {
  final _DayHeader header;
  const _DayHeaderRow({required this.header});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(header.day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return header.day.year == now.year
        ? DateFormat('EEE, d MMM').format(header.day)
        : DateFormat('EEE, d MMM yyyy').format(header.day);
  }

  @override
  Widget build(BuildContext context) {
    final color = JT.pnl(header.total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
      child: Row(
        children: [
          Text(_label(), style: JT.heading(context, size: 14)),
          const SizedBox(width: 8),
          Text(
            '${header.count} ${header.count == 1 ? 'trade' : 'trades'}',
            style: JT.caption(context, size: 12),
          ),
          const Spacer(),
          Text(jtMoney(header.total, signed: true),
              style: JT.number(context, size: 13, color: color)),
        ],
      ),
    );
  }
}

/// Booked profit/loss for the chosen period + how many trades made money.
class _PeriodSummary extends StatelessWidget {
  final PortfolioJournalController controller;
  const _PeriodSummary({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final booked = controller.realisedPnl.value;
      final wins = controller.totalWins.value;
      final losses = controller.totalLosses.value;
      final decided = wins + losses;
      final color = JT.pnl(booked);

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: JT.card(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Booked profit / loss · ${controller.periodText}',
                style: JT.caption(context, size: 12)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PulsatingEffect(
                  value: booked,
                  child: JtCount(
                    value: booked,
                    format: (v) => jtMoney(v, signed: true),
                    style: JT.number(context, size: 26, color: color),
                  ),
                ),
                const Spacer(),
                Text(
                  controller.totalTrades.value == 0
                      ? 'No trades'
                      : '${controller.totalTrades.value} '
                          '${controller.totalTrades.value == 1 ? 'trade' : 'trades'}',
                  style: JT.caption(context, size: 12),
                ),
              ],
            ),
            if (decided > 0) ...[
              const SizedBox(height: 12),
              _WinLossBar(wins: wins, losses: losses),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Dot(color: JT.profit),
                  const SizedBox(width: 6),
                  Text('$wins made money',
                      style: JT.caption(context, size: 12)),
                  const SizedBox(width: 14),
                  _Dot(color: JT.loss),
                  const SizedBox(width: 6),
                  Text('$losses lost money',
                      style: JT.caption(context, size: 12)),
                ],
              ),
            ],
          ],
        ),
      );
    });
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
  final PortfolioJournalController controller;
  const _PeriodChips({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = controller.selectedDays.value;
      return SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          physics: const BouncingScrollPhysics(),
          itemCount: PortfolioJournalController.filterOptions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final opt = PortfolioJournalController.filterOptions[i];
            final active = selected == opt.days;
            return JtPressable(
              pressedScale: 0.95,
              onTap: () {
                HapticFeedback.selectionClick();
                controller.onFilterChanged(opt.days);
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

class _AnalyticsBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _AnalyticsBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = JT.isDark(context);
    return JtPressable(
      onTap: onTap,
      haptic: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: dark
                ? const [Color(0xFF172554), Color(0xFF1E3A5F)]
                : const [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JT.blue.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: JT.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.insights_rounded, color: JT.blue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('See your trading report',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: JT.blue)),
                  const SizedBox(height: 2),
                  Text('Calendar, charts and weekly summary',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: JT.blue.withOpacity(0.75))),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, size: 18, color: JT.blue),
          ],
        ),
      ),
    );
  }
}

/// One closed trade.
class JournalTradeCard extends StatelessWidget {
  final JournalTradeHistory trade;
  final bool isExpanded;
  final bool canEdit;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const JournalTradeCard({
    Key? key,
    required this.trade,
    required this.isExpanded,
    required this.canEdit,
    required this.onToggle,
    required this.onEdit,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = trade;
    final isShort = t.isShortSell;
    final pnl = t.profitLoss;
    final color = JT.pnl(pnl);
    final cost = t.entryPrice * t.quantity;
    final pct = cost > 0 ? pnl / cost * 100 : 0.0;
    final name = jtDisplaySymbol(t.symbol);
    final entry = t.entryDate.toLocal();
    final exit = t.exitDate.toLocal();
    final sharesText = '${t.quantity} ${t.quantity == 1 ? 'share' : 'shares'}';
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
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: JT.heading(context, size: 16)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            JtDirectionChip(isShort: isShort),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(sharesText,
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

              // Entry → exit
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
                  _ExpandHint(expanded: isExpanded),
                ],
              ),

              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !isExpanded
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
                                  child: _InfoTile(
                                    icon: Icons.login_rounded,
                                    label: isShort ? 'Sold on' : 'Bought on',
                                    value: fmt.format(entry),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _InfoTile(
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
                                      child: _InfoTile(
                                        icon: Icons.shield_outlined,
                                        label: 'Safety exit',
                                        value: jtPrice(t.stopLossPrice!),
                                      ),
                                    ),
                                  if (hasSafety && hasGoal)
                                    const SizedBox(width: 10),
                                  if (hasGoal)
                                    Expanded(
                                      child: _InfoTile(
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
                                      child: _InfoTile(
                                        icon: Icons.schedule_rounded,
                                        label: 'Planned for',
                                        value: t.timeframe,
                                      ),
                                    ),
                                  if (t.timeframe.isNotEmpty && t.charges > 0)
                                    const SizedBox(width: 10),
                                  if (t.charges > 0)
                                    Expanded(
                                      child: _InfoTile(
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
                              _NoteBlock(text: t.reason!),
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
