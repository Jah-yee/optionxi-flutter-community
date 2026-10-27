import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:optionxi/VirtualTradeJournal/journal_ui_kit.dart';
import 'package:optionxi/VirtualTradeJournal/portfolio_journal_controller.dart';

/// Opens "Your scorecard". It reads the controller live, so the numbers keep
/// moving while the sheet is open.
Future<void> showJournalStatsSheet(
        BuildContext context, PortfolioJournalController controller) =>
    showJtSheet<void>(
      context,
      (_) => JournalStatsSheet(controller: controller),
    );

class JournalStatsSheet extends StatelessWidget {
  final PortfolioJournalController controller;
  const JournalStatsSheet({Key? key, required this.controller})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return JtSheet(
      title: 'Your scorecard',
      subtitle: 'A simple summary of how your trades are doing.',
      child: Obx(() {
        final c = controller;
        final total = c.totalProfit.value;
        final booked = c.realisedPnl.value;
        final running = c.unrealisedPnl.value;
        final wins = c.totalWins.value;
        final losses = c.totalLosses.value;
        final decided = wins + losses;
        final period = c.periodText;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Overall ──
            _ResultCard(total: total),
            const SizedBox(height: 12),

            // ── Booked vs running ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ExplainTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'Booked',
                    value: booked,
                    caption:
                        'Profit or loss you\'ve already locked in by closing '
                        'trades ($period).',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ExplainTile(
                    icon: Icons.hourglass_bottom_rounded,
                    title: 'Running',
                    value: running,
                    caption:
                        'Profit or loss on trades still open. It moves with '
                        'the market until you close them.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Money in the market ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: JT.card(context),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: JT.tint(context, JT.blue, 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined,
                        size: 20, color: JT.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Money in the market',
                            style: JT.heading(context, size: 14)),
                        const SizedBox(height: 2),
                        Text(
                          'What you put into your open trades.',
                          style: JT.caption(context, size: 12),
                        ),
                      ],
                    ),
                  ),
                  JtCount(
                    value: c.totalInvestment.value,
                    format: (v) => jtMoney(v),
                    style: JT.number(context, size: 17),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Hit rate ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: JT.card(context),
              child: Row(
                children: [
                  _WinRing(
                    percent: decided == 0 ? 0 : c.winRate,
                    hasData: decided > 0,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Trades that made money',
                            style: JT.heading(context, size: 14)),
                        const SizedBox(height: 4),
                        Text(
                          decided == 0
                              ? 'Close a trade and your success rate will '
                                  'show up here.'
                              : '$wins of $decided closed trades ended in '
                                  'profit ($period).',
                          style: JT.caption(context, size: 12),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _CountBox(
                                label: 'Profit',
                                value: wins,
                                color: JT.profit,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _CountBox(
                                label: 'Loss',
                                value: losses,
                                color: JT.loss,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final double total;
  const _ResultCard({required this.total});

  @override
  Widget build(BuildContext context) {
    final color = JT.pnl(total);
    final word = total > 0
        ? 'You\'re up overall'
        : (total < 0 ? 'You\'re down overall' : 'You\'re even overall');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JT.tint(context, color, 0.16),
            JT.tint(context, color, 0.05),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                total >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(word, style: JT.caption(context, size: 13, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          JtCount(
            value: total,
            format: (v) => jtMoney(v, signed: true),
            style: JT.number(context, size: 34, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            'Booked and running results added together.',
            style: JT.caption(context, size: 12),
          ),
        ],
      ),
    );
  }
}

class _ExplainTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final double value;
  final String caption;
  const _ExplainTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final color = JT.pnl(value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: JT.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: JT.text2(context)),
              const SizedBox(width: 6),
              Text(title, style: JT.heading(context, size: 13)),
            ],
          ),
          const SizedBox(height: 8),
          JtCount(
            value: value,
            format: (v) => jtMoney(v, signed: true),
            style: JT.number(context, size: 20, color: color),
          ),
          const SizedBox(height: 6),
          Text(caption, style: JT.caption(context, size: 11)),
        ],
      ),
    );
  }
}

class _CountBox extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _CountBox(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: JT.tint(context, color, 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            JtCount(
              value: value.toDouble(),
              format: (v) => v.round().toString(),
              style: JT.number(context, size: 20, color: color),
            ),
            const SizedBox(height: 2),
            Text(label, style: JT.caption(context, size: 11)),
          ],
        ),
      );
}

/// Ring that fills to the win-rate percentage.
class _WinRing extends StatelessWidget {
  final double percent;
  final bool hasData;
  const _WinRing({required this.percent, required this.hasData});

  @override
  Widget build(BuildContext context) {
    final color =
        !hasData ? JT.text3(context) : (percent >= 50 ? JT.profit : JT.amber);
    return SizedBox(
      width: 92,
      height: 92,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: percent.clamp(0, 100) / 100),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => CustomPaint(
          painter: _RingPainter(
            progress: t,
            color: color,
            track: JT.border(context),
          ),
          child: Center(
            child: Text(
              hasData ? '${(t * 100).round()}%' : '—',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: JT.text(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  _RingPainter(
      {required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base);
    if (progress <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * progress, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
