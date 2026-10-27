import 'dart:async';
import 'package:flutter/material.dart';

class StockItem {
  final String symbol;
  final String name;
  final String exchange;
  const StockItem(this.symbol, this.name, [this.exchange = 'NSE']);
}

/// Replace with API/Supabase-backed list.
const List<StockItem> kPopularStocks = [
  StockItem('RELIANCE', 'Reliance Industries'),
  StockItem('TCS', 'Tata Consultancy Services'),
  StockItem('HDFCBANK', 'HDFC Bank'),
  StockItem('INFY', 'Infosys'),
  StockItem('ICICIBANK', 'ICICI Bank'),
  StockItem('SBIN', 'State Bank of India'),
  StockItem('ITC', 'ITC Ltd'),
  StockItem('TATAMOTORS', 'Tata Motors'),
  StockItem('ADANIENT', 'Adani Enterprises'),
  StockItem('ABAN', 'Aban Offshore'),
  StockItem('BHARTIARTL', 'Bharti Airtel'),
  StockItem('WIPRO', 'Wipro'),
];

/// Flat, neutral palette with one accent. No gradients.
class _Palette {
  _Palette(this.dark);
  final bool dark;

  Color get surface => dark ? const Color(0xFF1C1F26) : Colors.white;
  Color get ink => dark ? const Color(0xFFECEAE4) : const Color(0xFF16181D);
  Color get onInk => dark ? const Color(0xFF16181D) : Colors.white;
  Color get muted => dark ? const Color(0xFF9A9DA5) : const Color(0xFF6B6F76);
  Color get border => dark ? const Color(0xFF2C303A) : const Color(0xFFE4E1D8);
  Color get tint => dark ? const Color(0xFF262A33) : const Color(0xFFF3F1EA);
  Color get accent => dark ? const Color(0xFF3FBF94) : const Color(0xFF0F7B5F);
}

class ModernSearchBar extends StatefulWidget {
  const ModernSearchBar({
    super.key,
    this.stocks = kPopularStocks,
    this.onSelected,
    this.onSubmitted,
    this.hintInterval = const Duration(milliseconds: 2000),
  });

  final List<StockItem> stocks;
  final ValueChanged<StockItem>? onSelected;
  final ValueChanged<String>? onSubmitted;
  final Duration hintInterval;

  @override
  State<ModernSearchBar> createState() => _ModernSearchBarState();
}

class _ModernSearchBarState extends State<ModernSearchBar>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _stagger;
  Timer? _timer;
  int _hint = 0;
  bool _wasEmpty = true;

  String get _q => _ctrl.text.trim();

  @override
  void initState() {
    super.initState();
    _stagger = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _ctrl.addListener(() {
      final empty = _ctrl.text.isEmpty;
      if (empty != _wasEmpty) {
        _wasEmpty = empty;
        _stagger.forward(from: 0);
      }
      setState(() {});
    });
    _focus.addListener(() {
      setState(() {});
      if (_focus.hasFocus) _stagger.forward(from: 0);
    });
    _timer = Timer.periodic(widget.hintInterval, (_) {
      if (!mounted || _ctrl.text.isNotEmpty || widget.stocks.isEmpty) return;
      setState(() => _hint = (_hint + 1) % widget.stocks.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stagger.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<StockItem> get _matches {
    final q = _q.toLowerCase();
    if (q.isEmpty) return const [];
    bool starts(StockItem s) =>
        s.symbol.toLowerCase().startsWith(q) ||
        s.name.toLowerCase().startsWith(q);
    bool has(StockItem s) =>
        s.symbol.toLowerCase().contains(q) || s.name.toLowerCase().contains(q);
    final a = widget.stocks.where(starts);
    final b = widget.stocks.where((s) => !starts(s) && has(s));
    return [...a, ...b].take(8).toList();
  }

  void _select(StockItem s) {
    _ctrl.clear();
    _focus.unfocus();
    widget.onSelected?.call(s);
  }

  void _submit() {
    if (_q.isEmpty) return;
    widget.onSubmitted?.call(_q);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette(Theme.of(context).brightness == Brightness.dark);
    final showPanel = _focus.hasFocus || _q.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(p),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: showPanel
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _q.isEmpty ? _popular(p) : _results(p),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  // ───────────────────────── Field ─────────────────────────

  Widget _field(_Palette p) {
    final focused = _focus.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: focused ? p.accent : p.border,
          width: focused ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? 0.35 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Icon(Icons.search_rounded,
              color: focused ? p.accent : p.muted, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 54,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  if (_ctrl.text.isEmpty && widget.stocks.isNotEmpty)
                    IgnorePointer(
                      child: Row(
                        children: [
                          Text('Search ',
                              style: TextStyle(color: p.muted, fontSize: 16)),
                          Flexible(
                            child: ClipRect(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 450),
                                layoutBuilder: (current, previous) => Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    ...previous,
                                    if (current != null) current,
                                  ],
                                ),
                                transitionBuilder: (child, anim) {
                                  final incoming = child.key == ValueKey(_hint);
                                  return FadeTransition(
                                    opacity: anim,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: Offset(0, incoming ? 0.8 : -0.8),
                                        end: Offset.zero,
                                      ).animate(anim),
                                      child: child,
                                    ),
                                  );
                                },
                                child: Text(
                                  widget.stocks[_hint].symbol,
                                  key: ValueKey(_hint),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: p.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _submit(),
                    cursorColor: p.accent,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                _ctrl.clear();
                _focus.requestFocus();
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration:
                    BoxDecoration(color: p.tint, shape: BoxShape.circle),
                child: Icon(Icons.close_rounded, size: 16, color: p.muted),
              ),
            ),
          GestureDetector(
            onTap: _submit,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
              child:
                  Icon(Icons.arrow_forward_rounded, color: p.onInk, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Popular chips ─────────────────────────

  Widget _popular(_Palette p) {
    final stocks = widget.stocks.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 10),
          child: Text(
            'POPULAR',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: p.muted,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < stocks.length; i++)
              _Stagger(
                  animation: _stagger, index: i, child: _chip(p, stocks[i])),
          ],
        ),
      ],
    );
  }

  Widget _chip(_Palette p, StockItem s) {
    return Material(
      color: p.surface,
      shape: StadiumBorder(side: BorderSide(color: p.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        splashColor: p.accent.withValues(alpha: 0.12),
        onTap: () => _select(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            s.symbol,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Results ─────────────────────────

  Widget _results(_Palette p) {
    final list = _matches;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: list.isEmpty
          ? InkWell(
              onTap: _submit,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.search_off_rounded, color: p.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No match. Tap to search "$_q" anyway',
                        style: TextStyle(color: p.ink, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  _Stagger(
                      animation: _stagger, index: i, child: _tile(p, list[i])),
                  if (i != list.length - 1)
                    Divider(height: 1, indent: 64, color: p.border),
                ],
              ],
            ),
    );
  }

  Widget _tile(_Palette p, StockItem s) {
    return InkWell(
      splashColor: p.accent.withValues(alpha: 0.10),
      onTap: () => _select(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.tint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                s.symbol[0],
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.symbol,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.muted),
                  ),
                ],
              ),
            ),
            Text(
              s.exchange,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: p.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fade + slide-up, delayed per index so items appear one by one.
class _Stagger extends StatelessWidget {
  const _Stagger({
    required this.animation,
    required this.index,
    required this.child,
  });

  final Animation<double> animation;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.07).clamp(0.0, 0.6);
    final a = animation.drive(
      CurveTween(
          curve: Interval(start, start + 0.4, curve: Curves.easeOutCubic)),
    );
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
            .animate(a),
        child: child,
      ),
    );
  }
}
