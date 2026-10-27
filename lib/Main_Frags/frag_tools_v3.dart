import 'package:flutter/material.dart';
import 'package:optionxi/Main_Frags/frag_tools_v3_animations.dart';

// ───────────── Models ─────────────
/// One tool card (e.g. "Screeners").
class ToolItem {
  const ToolItem({
    required this.id,
    required this.title,
    required this.description,
    required this.accent,
    required this.animationBuilder,
    this.keywords = const [],
  });

  /// Unique id. Use it in your router / switch to open the right page.
  final String id;

  final String title;

  /// Keep it short and in plain words (max ~100 characters fits 3 lines).
  final String description;

  /// Tint behind the animation tile.
  final Color accent;

  /// Builds the small looping animation shown on the card.
  /// Every animation lives in its own file under /animations.
  final WidgetBuilder animationBuilder;

  /// Extra words people might type (e.g. "losers", "rsi", "volume").
  final List<String> keywords;

  /// Search: every word typed must appear in title, description or keywords.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = '$title $description ${keywords.join(' ')}'.toLowerCase();
    return q.split(RegExp(r'\s+')).every(haystack.contains);
  }
}

/// A group of tools under one heading (e.g. "Find stocks").
class ToolSection {
  const ToolSection({
    required this.title,
    required this.tools,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<ToolItem> tools;
}

// ───────────── Registry: add / remove / reorder tools here ─────────────
/// THE one place to add / remove / reorder tools.
///
/// To add a new tool:
///  1. Create `animations/my_tool_animation.dart` (copy any existing one).
///  2. Add a `ToolItem(...)` below, inside an existing section
///     or inside a brand new `ToolSection(...)`.
///  3. Handle its `id` in your `onToolSelected` callback.
class ToolsRegistry {
  ToolsRegistry._();

  static List<ToolSection> get sections => [
        ToolSection(
          title: 'Find stocks',
          subtitle: 'Scan the market for ideas',
          tools: [
            ToolItem(
              id: 'top_picks',
              title: 'Top Picks',
              description:
                  'Stocks picked by more than one screener get a stronger signal and rank higher.',
              accent: ToolPalette.pink,
              keywords: const [
                'top picks',
                'best',
                'strong',
                'signal',
                'confluence',
                'overlap',
                'multiple screeners',
                'ranked',
                'score'
              ],
              animationBuilder: (_) => const TopPicksAnimation(),
            ),
            ToolItem(
              id: 'screeners',
              title: 'Screeners',
              description:
                  'Find stocks fast with ready-made filters like high volume and day-high breaks. No setup needed.',
              accent: ToolPalette.green,
              keywords: const [
                'volume',
                'day high',
                'day break',
                'filter',
                'scan',
                'predefined'
              ],
              animationBuilder: (_) => const ScreenerAnimation(),
            ),
            ToolItem(
              id: 'top_movers',
              title: 'Top Gainers & Losers',
              description:
                  'See which stocks are rising or falling the most today, so you know where the action is.',
              accent: ToolPalette.blue,
              keywords: const [
                'gainers',
                'losers',
                'movers',
                'rising',
                'falling',
                'top'
              ],
              animationBuilder: (_) => const MoversAnimation(),
            ),
            ToolItem(
              id: 'custom_screeners',
              title: 'Custom Screeners',
              description:
                  'Make your own filter with simple rules, like SMA above EMA, and get alerted when stocks match.',
              accent: ToolPalette.amber,
              keywords: const [
                'sma',
                'ema',
                'rsi',
                'conditions',
                'rules',
                'indicator',
                'build',
                'create',
                'algo'
              ],
              animationBuilder: (_) => const CustomScreenerAnimation(),
            ),
          ],
        ),
        ToolSection(
          title: 'Options',
          subtitle: 'Chain, budget picks and open interest',
          tools: [
            ToolItem(
              id: 'option_chain',
              title: 'Option Chain',
              description:
                  'See all strikes with calls and puts side by side, with price, OI and volume in one view.',
              accent: ToolPalette.blue,
              keywords: const [
                'option chain',
                'chain',
                'strike',
                'call',
                'put',
                'ce',
                'pe',
                'nifty',
                'banknifty',
                'expiry'
              ],
              animationBuilder: (_) => const OptionChainAnimation(),
            ),
            ToolItem(
              id: 'option_budget',
              title: 'Option Budget',
              description:
                  'Set how much you want to spend and see only the options that fit your budget.',
              accent: ToolPalette.amber,
              keywords: const [
                'budget',
                'premium',
                'cheap',
                'affordable',
                'price',
                'filter',
                'capital',
                'lot'
              ],
              animationBuilder: (_) => const OptionBudgetAnimation(),
            ),
            ToolItem(
              id: 'option_oi',
              title: 'Option OI Analysis',
              description:
                  'Spot long buildup, short buildup, short covering and long unwinding from OI and price change.',
              accent: ToolPalette.violet,
              keywords: const [
                'oi',
                'open interest',
                'long buildup',
                'short buildup',
                'short covering',
                'long unwinding',
                'buildup',
                'unwinding'
              ],
              animationBuilder: (_) => const OptionOiAnimation(),
            ),
          ],
        ),
        ToolSection(
          title: 'Index',
          subtitle: 'Track Nifty and Bank Nifty levels',
          tools: [
            ToolItem(
              id: 'index_breakout',
              title: 'Index Breakout',
              description:
                  'Know the moment Nifty or Bank Nifty breaks its day high or day low.',
              accent: ToolPalette.blue,
              keywords: const [
                'index',
                'nifty',
                'banknifty',
                'bank nifty',
                'breakout',
                'high',
                'low',
                'day high',
                'day low',
                'alert'
              ],
              animationBuilder: (_) => const IndexBreakoutAnimation(),
            ),
            ToolItem(
              id: 'bollinger_alerts',
              title: 'Bollinger Breakouts',
              description:
                  'Know when a price steps outside its usual range. It often signals a big move is starting.',
              accent: ToolPalette.violet,
              keywords: const [
                'bollinger',
                'bands',
                'breakout',
                'volatility',
                'range'
              ],
              animationBuilder: (_) => const BollingerAnimation(),
            ),
          ],
        ),
        ToolSection(
          title: 'Backtest',
          subtitle: 'Test ideas before risking real money',
          tools: [
            ToolItem(
              id: 'strategy_backtest',
              title: 'Strategy Backtest',
              description:
                  'Set rules like SMA above 4 EMA on the 5 min chart. See how often price followed through in the next 5 min.',
              accent: ToolPalette.green,
              keywords: const [
                'backtest',
                'accuracy',
                'sma',
                'ema',
                'rules',
                'conditions',
                '5 min',
                'hit rate',
                'win rate',
                'notify',
                'premium',
                'pro'
              ],
              animationBuilder: (_) => const StrategyBacktestAnimation(),
            ),
            ToolItem(
              id: 'option_testing',
              title: 'Option Testing',
              description:
                  'Buy a Nifty or Bank Nifty option virtually, move the chart forward, and see your P&L.',
              accent: ToolPalette.violet,
              keywords: const [
                'option',
                'testing',
                'practice',
                'virtual',
                'paper',
                'replay',
                'pnl',
                'profit',
                'loss',
                'nifty',
                'banknifty',
                'buy'
              ],
              animationBuilder: (_) => const OptionTestingAnimation(),
            ),
          ],
        ),
        ToolSection(
          title: 'Sector',
          subtitle: 'See where the money is flowing',
          tools: [
            ToolItem(
              id: 'sector_pulse',
              title: 'Sector Pulse',
              description:
                  'See which sectors are moving up and which are moving down today, at a glance.',
              accent: ToolPalette.violet,
              keywords: const [
                'sector',
                'sectors',
                'pulse',
                'heatmap',
                'rotation',
                'banking',
                'it',
                'pharma',
                'auto',
                'metal',
                'fmcg',
                'energy',
                'up',
                'down',
                'strong',
                'weak'
              ],
              animationBuilder: (_) => const SectorPulseAnimation(),
            ),
          ],
        ),
        ToolSection(
          title: 'Practice trade',
          subtitle: 'Trade with virtual money, risk nothing',
          tools: [
            ToolItem(
              id: 'practice_trade',
              title: 'Practice Trade',
              description:
                  'Buy and sell stocks and options with virtual money. Learn by doing, and climb the leaderboard.',
              accent: ToolPalette.violet,
              keywords: const [
                'practice',
                'practise',
                'virtual',
                'paper',
                'paper trading',
                'simulator',
                'demo',
                'learn',
                'trade',
                'stocks',
                'options',
                'buy',
                'sell',
                'pnl',
                'profit',
                'loss',
                'portfolio',
                'leaderboard',
                'rank',
                'compete'
              ],
              animationBuilder: (_) => const PracticeTradeAnimation(),
            ),
          ],
        ),
        ToolSection(
          title: 'AI tools',
          subtitle: 'Let AI read the market for you',
          tools: [
            ToolItem(
              id: 'ai_stock',
              title: 'AI Stock Analysis',
              description:
                  'Search any stock and get a simple AI summary of its trend, strength and key levels.',
              accent: ToolPalette.violet,
              keywords: const [
                'ai',
                'stock',
                'analysis',
                'analyse',
                'analyze',
                'search',
                'summary',
                'trend',
                'insight',
                'research',
                'bullish',
                'bearish'
              ],
              animationBuilder: (_) => const AiStockAnimation(),
            ),
            ToolItem(
              id: 'ai_index',
              title: 'AI Index Status',
              description:
                  'Know how Nifty is doing right now. AI reads trend, momentum and OI and tells you the mood.',
              accent: ToolPalette.blue,
              keywords: const [
                'ai',
                'index',
                'nifty',
                'banknifty',
                'bank nifty',
                'status',
                'mood',
                'sentiment',
                'trend',
                'momentum',
                'oi',
                'bullish',
                'bearish',
                'analysis'
              ],
              animationBuilder: (_) => const AiIndexAnimation(),
            ),
          ],
        ),

        ToolSection(
          title: 'My tools',
          subtitle: 'Your trades and your alerts, in one place',
          tools: [
            ToolItem(
              id: 'trade_journal',
              title: 'Trade Journal',
              description:
                  'Log your buys and sells and see your daily P&L on a calendar, just like GitHub. Learn from every trade.',
              accent: ToolPalette.green,
              keywords: const [
                'journal',
                'trade journal',
                'diary',
                'log',
                'track',
                'tracking',
                'buy',
                'sell',
                'pnl',
                'p&l',
                'profit',
                'loss',
                'calendar',
                'heatmap',
                'github',
                'streak',
                'learn',
                'review',
                'history'
              ],
              animationBuilder: (_) => const JournalAnimation(),
            ),
            ToolItem(
              id: 'my_alerts',
              title: 'My Alerts',
              description:
                  'Set your own high or low price for any stock and get notified in real time the moment it hits.',
              accent: ToolPalette.amber,
              keywords: const [
                'my alerts',
                'alert',
                'alerts',
                'price alert',
                'target',
                'stop loss',
                'high',
                'low',
                'custom',
                'customise',
                'customize',
                'notify',
                'notification',
                'realtime',
                'real time',
                'live',
                'bell'
              ],
              animationBuilder: (_) => const MyAlertsAnimation(),
            ),
          ],
        ),
        // ────────────────────────────────────────────────────────────
// PASTE inside ToolsRegistry.sections (frag_tools_v3.dart),
// e.g. right after the 'Backtest' section.
// Nifty + Stock picks share one animation (DailyAccuracyAnimation),
// only the label and colour differ.
// ────────────────────────────────────────────────────────────

        ToolSection(
          title: 'Performance',
          subtitle: 'See how past picks actually performed',
          tools: [
            ToolItem(
              id: 'ai_picks_accuracy',
              title: 'Stock Picks Accuracy',
              description:
                  'See how AI stock picks did each day, and how often they were right in the next 15 minutes.',
              accent: ToolPalette.violet,
              keywords: const [
                'stock picks',
                'ai picks',
                'ai',
                'accuracy',
                'hit rate',
                'win rate',
                'right',
                'wrong',
                '15 min',
                'daily',
                'history',
                'performance',
                'portfolio',
                'track record'
              ],
              animationBuilder: (_) => const DailyAccuracyAnimation(
                label: 'AI',
                color: ToolPalette.violet,
              ),
            ),
            ToolItem(
              id: 'nifty_picks_accuracy',
              title: 'Nifty Picks Accuracy',
              description:
                  'See how Nifty picks did each day, and how often they were right in the next 15 minutes.',
              accent: ToolPalette.blue,
              keywords: const [
                'nifty',
                'nifty picks',
                'index',
                'accuracy',
                'hit rate',
                'win rate',
                'bullish',
                'bearish',
                '15 min',
                'daily',
                'history',
                'performance',
                'track record'
              ],
              animationBuilder: (_) => const DailyAccuracyAnimation(
                label: 'NIFTY',
                color: ToolPalette.blue,
              ),
            ),
            ToolItem(
              id: 'scanner_picks',
              title: 'Scanner Picks',
              description:
                  'See every stock the scanners found, newest first, and whether each one turned out right.',
              accent: ToolPalette.amber,
              keywords: const [
                'scanner',
                'scanners',
                'screener',
                'screeners',
                'picks',
                'scanned',
                'right',
                'wrong',
                'history',
                'sorted',
                'performance',
                'portfolio'
              ],
              animationBuilder: (_) => const ScannerPicksAnimation(),
            ),
          ],
        ),
        ToolSection(
          title: 'Get notified',
          subtitle: 'Let the app watch the market for you',
          tools: [
            ToolItem(
              id: 'alerts',
              title: 'Alerts',
              description:
                  'Spot stocks that just broke above their high or below their low. Never miss a breakout.',
              accent: ToolPalette.sky,
              keywords: const [
                'breakout',
                'high breakout',
                'low breakout',
                'notification',
                'high',
                'low'
              ],
              animationBuilder: (_) => const AlertsAnimation(),
            ),
          ],
        ),
        ToolSection(
          title: 'News',
          subtitle: 'Stay on top of what moves the market',
          tools: [
            ToolItem(
              id: 'market_news',
              title: 'Market News',
              description:
                  'Read the latest market and stock headlines in one place, so you know why prices are moving.',
              accent: ToolPalette.sky,
              keywords: const [
                'news',
                'market news',
                'headlines',
                'latest',
                'updates',
                'events',
                'stocks',
                'nifty',
                'sentiment'
              ],
              animationBuilder: (_) => const NewsAnimation(),
            ),
          ],
        ),
        ToolSection(
          title: 'Deploy Algo',
          subtitle: 'Premium algos that notify you automatically',
          tools: [
            ToolItem(
              id: 'custom_algo',
              title: 'Custom Algo',
              description:
                  'Premium at ₹1500/Month. Deploy index, F&O or your own algo and get notified the moment it triggers.',
              accent: ToolPalette.amber,
              keywords: const [
                'algo',
                'deploy',
                'custom algo',
                'premium',
                'pro',
                'subscription',
                '1500',
                'index',
                'fno',
                'f&o',
                'notify',
                'notification',
                'alert',
                'automation',
                'strategy',
                'live'
              ],
              animationBuilder: (_) => const DeployAlgoAnimation(),
            ),
          ],
        ),
      ];
}

// ───────────── The Tools fragment ─────────────
/// Tools tab content. It is a fragment: no AppBar, no back button.
/// Drop it inside any Scaffold body / tab / bottom-nav page.
///
/// ```dart
/// ToolsSection(
///   onToolSelected: (tool) {
///     switch (tool.id) {
///       case 'screeners': Get.to(() => const ScreenersPage()); break;
///       case 'top_movers': ...
///     }
///   },
/// )
/// ```
class ToolsSection extends StatefulWidget {
  const ToolsSection({
    super.key,
    required this.onToolSelected,
    this.sections,
  });

  /// Called when the user taps a tool card.
  final ValueChanged<ToolItem> onToolSelected;

  /// Optional override. Defaults to [ToolsRegistry.sections].
  final List<ToolSection>? sections;

  @override
  State<ToolsSection> createState() => _ToolsSectionState();
}

class _ToolsSectionState extends State<ToolsSection> {
  final _controller = TextEditingController();
  String _query = '';

  late final List<ToolSection> _all = widget.sections ?? ToolsRegistry.sections;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String value) => setState(() => _query = value);

  void _clear() {
    _controller.clear();
    _setQuery('');
  }

  List<ToolSection> get _filtered => [
        for (final section in _all)
          if (section.tools.any((t) => t.matches(_query)))
            ToolSection(
              title: section.title,
              subtitle: section.subtitle,
              tools: [
                for (final tool in section.tools)
                  if (tool.matches(_query)) tool,
              ],
            ),
      ];

  @override
  Widget build(BuildContext context) {
    final sections = _filtered;
    final found = sections.fold<int>(0, (sum, s) => sum + s.tools.length);

    return Material(
      type: MaterialType.transparency,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            sliver: SliverToBoxAdapter(
              child: _SearchBar(
                controller: _controller,
                showClear: _query.isNotEmpty,
                onChanged: _setQuery,
                onClear: _clear,
              ),
            ),
          ),
          if (_query.trim().isNotEmpty && found > 0)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  found == 1 ? '1 tool found' : '$found tools found',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          if (sections.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(query: _query.trim(), onClear: _clear),
            )
          else
            for (final section in sections)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(child: _SectionHeader(section: section)),
                    SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 560,
                        mainAxisExtent: 140,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        childCount: section.tools.length,
                        (context, i) {
                          final tool = section.tools[i];
                          return _FadeSlideIn(
                            key: ValueKey(tool.id),
                            delay: i,
                            child: _ToolCard(
                              tool: tool,
                              onTap: () => widget.onToolSelected(tool),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

// ───────────────────────── Search bar ─────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.showClear,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool showClear;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: 'Search tools, e.g. gainers, alert, volume',
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIcon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
        suffixIcon: showClear
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: onClear,
              )
            : null,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: border(Colors.transparent),
        border: border(Colors.transparent),
        focusedBorder: border(const Color(0xFF22A06B), 1.5),
      ),
    );
  }
}

// ───────────────────────── Section header ─────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final ToolSection section;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (section.subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              section.subtitle!,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── Tool card ─────────────────────────

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool, required this.onTap});

  final ToolItem tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: '${tool.title}. ${tool.description}',
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _AnimationTile(tool: tool),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tool.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tool.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                          fontSize: 13,
                        ),
                      ),
                    ],
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

class _AnimationTile extends StatelessWidget {
  const _AnimationTile({required this.tool});

  final ToolItem tool;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: tool.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: tool.animationBuilder(context),
        ),
      ),
    );
  }
}

// ───────────────────────── Entrance animation ─────────────────────────

class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({super.key, required this.delay, required this.child});

  final int delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delay * 70),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child:
            Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

// ───────────────────────── Empty state ─────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.search_off_rounded,
                size: 30, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            'No tools match "$query"',
            textAlign: TextAlign.center,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Try simpler words like screener, alert or gainers.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onClear, child: const Text('Clear search')),
        ],
      ),
    );
  }
}
