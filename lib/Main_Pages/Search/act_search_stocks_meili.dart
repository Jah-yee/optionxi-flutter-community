import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:meilisearch/meilisearch.dart' as meili;
import 'package:optionxi/Components/cust_ai_analyse_btn.dart';
import 'package:optionxi/DataModels/dm_watchlist_stock.dart';
import 'package:optionxi/DB_Services/database_read.dart';
import 'package:optionxi/DB_Services/database_write.dart';
import 'package:optionxi/Helpers/badge_service_obx.dart';
import 'package:optionxi/Helpers/constants.dart';
import 'package:optionxi/Main_Pages/StockPages/act_set_alert.dart';
import 'package:optionxi/PushNotification/notifcation_service.dart';
import 'package:optionxi/Main_Pages/AISummary/act_stock_ai_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

/* ════════════════════════════════════════════════════════════
   DESIGN NOTES
   • One goal per screen: Find → Understand → Add to basket.
   • Every number has a plain-English sentence next to it.
   • Adding to the basket writes the SAME record as AddToBasketPage
     (Firebase `virtualbasket_toadd/{uid}`), including the pre-filled
     profit goal / loss limit / timeframe / reason — all visible and
     editable in the sheet, nothing is saved blindly.
   • The basket badge count and "In basket" tags update live from Firebase.
   • INTEGRATION: optionally pass `onOpenBasket`; otherwise the page does
     Get.toNamed(_kBasketRoute) — set that constant to your basket route.

   EMBEDDED MODE
   • Pass `embedded: true` (or use `FragSearchMeili`) to run as a
     bottom-nav tab. In that mode:
       – No `Scaffold` (the host owns it)
       – No `SafeArea` (the host owns it — otherwise top gap doubles)
       – No back button in the header
       – State is kept alive across tab switches via
         `AutomaticKeepAliveClientMixin`
       – System back clears the search instead of popping the app
   ════════════════════════════════════════════════════════════ */

// ───────────────────────── Theme ─────────────────────────
class _C {
  static bool _dk(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  static Color bg(BuildContext c) =>
      _dk(c) ? const Color(0xFF0C0E14) : const Color(0xFFF4F5F9);
  static Color card(BuildContext c) =>
      _dk(c) ? const Color(0xFF161A24) : Colors.white;
  static Color soft(BuildContext c) =>
      _dk(c) ? const Color(0xFF1D2230) : const Color(0xFFEEF0F6);
  static Color line(BuildContext c) =>
      _dk(c) ? const Color(0xFF262C3E) : const Color(0xFFE3E6EF);
  static Color ink(BuildContext c) =>
      _dk(c) ? const Color(0xFFF1F3FF) : const Color(0xFF12141F);
  static Color ink2(BuildContext c) =>
      _dk(c) ? const Color(0xFF8D97B5) : const Color(0xFF666F8C);
  static Color ink3(BuildContext c) =>
      _dk(c) ? const Color(0xFF4C5576) : const Color(0xFF9CA4BE);

  static const accent = Color(0xFF3B72F6);
  static const up = Color(0xFF00C896);
  static const down = Color(0xFFEF4565);
  static const bell = Color(0xFF4EA8DE);
  static const mark = Color(0xFFFF6B35);

  static Color tint(Color c, BuildContext ctx) =>
      c.withOpacity(_dk(ctx) ? 0.14 : 0.10);
}

// ───────────────────────── Helpers ─────────────────────────
double _d(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0.0;
}

bool _has(dynamic v) =>
    v != null && (v is num || double.tryParse('$v') != null);

/// ₹1,23,456.70 (Indian grouping)
String _money(double v) {
  final neg = v < 0;
  final p = v.abs().toStringAsFixed(2).split('.');
  var i = p[0];
  if (i.length > 3) {
    final last3 = i.substring(i.length - 3);
    var rest = i.substring(0, i.length - 3);
    final g = <String>[];
    while (rest.length > 2) {
      g.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) g.insert(0, rest);
    i = '${g.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$i.${p[1]}';
}

String _moneyOrDash(dynamic v) => _has(v) ? _money(_d(v)) : '–';

String _shares(dynamic volume) {
  if (!_has(volume)) return '–';
  final v = _d(volume);
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)} L';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)} K';
  return v.toStringAsFixed(0);
}

String _symOf(dynamic raw) => (raw ?? '')
    .toString()
    .replaceAll('NSE:', '')
    .replaceAll('-EQ', '')
    .replaceAll('-BE', '')
    .replaceAll('-BZ', '')
    .trim();

// ───────────────────────── Virtual basket (Firebase) ─────────────────────────
class BasketEntry {
  final String key;
  final String symbol;
  final bool isBuy;
  final int qty;
  final double entryPrice;
  final double target;
  final double stopLoss;
  final String timeframe;
  final String reason;

  const BasketEntry({
    required this.key,
    required this.symbol,
    required this.isBuy,
    required this.qty,
    required this.entryPrice,
    required this.target,
    required this.stopLoss,
    required this.timeframe,
    required this.reason,
  });
}

class VirtualBasketStore extends ChangeNotifier {
  static final VirtualBasketStore instance = VirtualBasketStore._();
  VirtualBasketStore._();

  static const _node = 'virtualbasket_toadd';
  StreamSubscription<DatabaseEvent>? _sub;
  String? _uid;
  List<BasketEntry> _entries = [];

  List<BasketEntry> get entries => _entries;
  int get count => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  void start() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_uid == user.uid && _sub != null) return;
    _sub?.cancel();
    _uid = user.uid;
    _sub = FirebaseDatabase.instance
        .ref()
        .child(_node)
        .child(user.uid)
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      final list = <BasketEntry>[];
      if (v is Map) {
        v.forEach((k, raw) {
          if (raw is! Map) return;
          final m = Map<String, dynamic>.from(raw);
          list.add(BasketEntry(
            key: '$k',
            symbol: '${m['symbol'] ?? ''}',
            isBuy: '${m['transaction_type']}'.toUpperCase() != 'SELL',
            qty: _d(m['quantity']).toInt(),
            entryPrice: _d(m['entry_price']),
            target: _d(m['target_price']),
            stopLoss: _d(m['stop_loss_price']),
            timeframe: '${m['timeframe'] ?? 'Short Term'}',
            reason: '${m['reason'] ?? ''}',
          ));
        });
      }
      _entries = list;
      notifyListeners();
    }, onError: (_) {});
  }

  BasketEntry? find(String symbol) {
    final s = _symOf(symbol);
    for (final e in _entries) {
      if (_symOf(e.symbol) == s) return e;
    }
    return null;
  }

  Future<void> save({
    required String symbol,
    required bool isBuy,
    required int qty,
    required double entryPrice,
    required double target,
    required double stopLoss,
    required String timeframe,
    required String reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');
    final root = FirebaseDatabase.instance.ref().child(_node).child(user.uid);

    final data = <String, dynamic>{
      'symbol': symbol,
      'segment': 'EQ',
      'transaction_type': isBuy ? 'BUY' : 'SELL',
      'entry_price': entryPrice,
      'quantity': qty,
      'target_price': target,
      'stop_loss_price': stopLoss,
      'timeframe': timeframe,
      'reason': reason,
      'entry_date': DateTime.now().toUtc().toIso8601String(),
    };

    final existing = find(symbol);
    if (existing != null) {
      await root.child(existing.key).update(data);
    } else {
      await root.push().set({...data, 'created_at': ServerValue.timestamp});
      await BasketBadgeServiceObx.incrementBasketBadge();
    }
  }
}

const _kBasketRoute = '/virtual-basket';

// ───────────────────────── Page ─────────────────────────
class AllSearchPageMeili extends StatefulWidget {
  final VoidCallback? onOpenBasket;

  /// true when used as a bottom-nav tab (no back button, keeps state alive)
  final bool embedded;

  const AllSearchPageMeili({
    Key? key,
    this.onOpenBasket,
    this.embedded = false,
  }) : super(key: key);

  @override
  State<AllSearchPageMeili> createState() => _AllSearchPageMeiliState();
}

class _Mover {
  final String label;
  final IconData icon;
  final Color color;
  final String hint;
  const _Mover(this.label, this.icon, this.color, this.hint);
}

class _AllSearchPageMeiliState extends State<AllSearchPageMeili>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late meili.MeiliSearchClient _client;
  final _read = DatabaseReadService();
  final _write = DatabaseWriteService();
  final _auth = FirebaseAuth.instance;
  final _basket = VirtualBasketStore.instance;

  final _search = TextEditingController();
  final _focus = FocusNode();
  late AnimationController _shimmer;
  Timer? _debounce;
  int _reqId = 0;

  List<Map<String, dynamic>> _results = [];
  final Map<int, List<Map<String, dynamic>>> _cache = {};
  List<String> _recent = [];
  Set<String> _favs = {};

  int _tab = 0;
  bool _loading = false;
  bool _loadingTab = false;
  bool _focused = false;
  bool _showTip = false;
  String? _error;

  static const _movers = [
    _Mover('Rising', Icons.north_east_rounded, _C.up,
        'Stocks trading higher than yesterday — biggest gainers first.'),
    _Mover('Falling', Icons.south_east_rounded, _C.down,
        'Stocks trading lower than yesterday — biggest drops first.'),
    _Mover('Busiest', Icons.bolt_rounded, _C.accent,
        'Stocks with the most shares bought and sold today.'),
  ];

  @override
  bool get wantKeepAlive => widget.embedded;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
    _client = meili.MeiliSearchClient(
      dotenv.env['MELIESEARCH_URL']!,
      dotenv.env['MELIE_API_KEY']!,
    );
    _basket.start();
    _loadRecent();
    _loadFavs();
    _loadTip();
    _loadTab(0);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  // ── storage ──
  Future<void> _loadTip() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _showTip = !(p.getBool('search_tip_seen') ?? false));
  }

  Future<void> _dismissTip() async {
    setState(() => _showTip = false);
    final p = await SharedPreferences.getInstance();
    await p.setBool('search_tip_seen', true);
  }

  Future<void> _loadRecent() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _recent = p.getStringList('recent_searches') ?? []);
  }

  Future<void> _saveRecent(String s) async {
    if (s.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList('recent_searches') ?? [];
    l.remove(s);
    l.insert(0, s);
    final t = l.take(6).toList();
    await p.setStringList('recent_searches', t);
    if (mounted) setState(() => _recent = t);
  }

  Future<void> _removeRecent(String s) async {
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList('recent_searches') ?? [];
    l.remove(s);
    await p.setStringList('recent_searches', l);
    if (mounted) setState(() => _recent = l);
  }

  Future<void> _clearRecent() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('recent_searches');
    if (mounted) setState(() => _recent = []);
  }

  Future<void> _loadFavs() async {
    final u = _auth.currentUser;
    if (u == null) return;
    try {
      final f = await _read.getFavoriteStocks(u.uid);
      if (!mounted) return;
      setState(() => _favs = f.map((s) => s.stockName).toSet());
    } catch (_) {}
  }

  // ── data ──
  Future<void> _loadTab(int tab, {bool force = false}) async {
    setState(() {
      _tab = tab;
      _loadingTab = force || !_cache.containsKey(tab);
    });
    if (!force && _cache.containsKey(tab)) return;

    const base = 'type = "stock" AND volume > 1000000';
    final filter = tab == 0
        ? 'percent_change > 0 AND $base'
        : tab == 1
            ? 'percent_change < 0 AND $base'
            : 'type = "stock"';
    final sort = tab == 0
        ? ['percent_change:desc']
        : tab == 1
            ? ['percent_change:asc']
            : ['volume:desc'];

    List<Map<String, dynamic>>? hits;
    try {
      final r = await _client.index('stocks').search(
          '', meili.SearchQuery(hitsPerPage: 15, sort: sort, filter: filter));
      hits = r.hits.cast<Map<String, dynamic>>();
    } catch (_) {
      try {
        final r = await _client
            .index('stocks')
            .search('', meili.SearchQuery(hitsPerPage: 60, filter: filter));
        final l = r.hits.cast<Map<String, dynamic>>().toList();
        l.sort((a, b) {
          if (tab == 0) {
            return _d(b['percent_change']).compareTo(_d(a['percent_change']));
          }
          if (tab == 1) {
            return _d(a['percent_change']).compareTo(_d(b['percent_change']));
          }
          return _d(b['volume']).compareTo(_d(a['volume']));
        });
        hits = l.take(15).toList();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      if (hits != null) _cache[tab] = hits;
      if (_tab == tab) _loadingTab = false;
    });
  }

  void _onChanged(String v) {
    setState(() {});
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      _reqId++;
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 280), () => _doSearch(v));
  }

  Future<void> _doSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final id = ++_reqId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _client
          .index('stocks')
          .search(q, meili.SearchQuery(filter: 'type = "stock"'));
      if (!mounted || id != _reqId) return;
      final hits = r.hits.cast<Map<String, dynamic>>().toList();
      final ql = q.toLowerCase();
      hits.sort((a, b) {
        final an = _symOf(a['symbol']).toLowerCase();
        final bn = _symOf(b['symbol']).toLowerCase();
        if (an == ql && bn != ql) return -1;
        if (bn == ql && an != ql) return 1;
        if (an.startsWith(ql) && !bn.startsWith(ql)) return -1;
        if (bn.startsWith(ql) && !an.startsWith(ql)) return 1;
        return 0;
      });
      setState(() {
        _results = hits;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _reqId) return;
      setState(() {
        _error =
            "We couldn't reach the market data. Check your internet and try again.";
        _loading = false;
        _results = [];
      });
    }
  }

  void _runSearch(String t) {
    _search.text = t;
    _search.selection = TextSelection.collapsed(offset: t.length);
    setState(() {});
    _doSearch(t);
  }

  // ── watchlist ──
  bool _isFav(Map<String, dynamic> s) => _favs.contains(s['symbol'] ?? '');

  Future<void> _toggleFav(Map<String, dynamic> s) async {
    final u = _auth.currentUser;
    if (u == null) {
      _snack('Sign in to use your watchlist', error: true);
      return;
    }
    final sym = s['symbol'] ?? '';
    final name = s['name'] ?? '';
    final added = !_favs.contains(sym);
    HapticFeedback.selectionClick();
    setState(() => added ? _favs.add(sym) : _favs.remove(sym));
    _snack(added ? 'Added to your watchlist' : 'Removed from your watchlist');
    try {
      await _write.toggleFavorite(
          u.uid, dm_stock(stockName: sym, fullStockName: name));
    } catch (_) {
      if (!mounted) return;
      setState(() => added ? _favs.remove(sym) : _favs.add(sym));
      _snack('Something went wrong. Try again.', error: true);
    }
  }

  // ── basket ──
  void _openBasket() {
    final cb = widget.onOpenBasket;
    if (cb != null) {
      cb();
    } else {
      Get.toNamed(_kBasketRoute);
    }
  }

  void _snack(String msg,
      {bool error = false, String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    // Embedded mode: the host bottom nav sits below us. Add its height so
    // the snackbar isn't hidden behind the nav bar.
    final bottom = _basket.isEmpty ? 16.0 : 84.0;
    final extra = widget.embedded ? 72.0 : 0.0;
    m.showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
      backgroundColor: error ? _C.down : const Color(0xFF1A1F2E),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottom + extra),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(milliseconds: 2200),
      action: actionLabel == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: const Color(0xFF8FB2FF),
              onPressed: onAction ?? () {}),
    ));
  }

  // ── sheets ──
  void _showStock(Map<String, dynamic> stock) {
    _focus.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => _StockSheet(
        stock: stock,
        isFavorite: _isFav(stock),
        onToggleFav: () => _toggleFav(stock),
        onSetAlert: () {
          Navigator.pop(sheetCtx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SetAlertPage(
                stockName: stock['symbol'],
                segment: stock['type'],
              ),
            ),
          );
        },
        onOpenBasket: () {
          Navigator.pop(sheetCtx);
          _openBasket();
        },
        onOpenDetails: () => Get.toNamed(
            '/stocks/${'NSE:' + _symOf(stock['symbol']).toUpperCase() + '-EQ'}'),
      ),
    );
  }

  // ── embedded back handling ──
  Future<bool> _handleEmbeddedBack() async {
    if (_search.text.isNotEmpty) {
      _search.clear();
      _onChanged('');
      return false; // consumed: don't pop
    }
    return true; // let the host decide (e.g. switch to first tab)
  }

  // ───────────────── build ─────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    final content = Column(
      children: [
        _header(),
        _searchBar(),
        const SizedBox(height: 6),
        Expanded(
          child: ListenableBuilder(
            listenable: _basket,
            builder: (_, __) => _body(),
          ),
        ),
      ],
    );

    // ── Pushed-route mode: keep the original Scaffold ──
    if (!widget.embedded) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: _C.bg(context),
          body: SafeArea(
            child: Stack(
              children: [
                content,
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: _BasketBar(
                    basket: _basket,
                    visible: !_focused,
                    onTap: _openBasket,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Embedded-tab mode: no Scaffold, no SafeArea, no back button ──
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleEmbeddedBack();
      },
      child: ColoredBox(
        color: _C.bg(context),
        child: Stack(
          children: [
            content,
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: _BasketBar(
                basket: _basket,
                visible: !_focused,
                onTap: _openBasket,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            if (!widget.embedded) ...[
              _IconBtn(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Find a stock',
                      style: TextStyle(
                          color: _C.ink(context),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                  Text('Search, learn, then add to your virtual basket',
                      style:
                          TextStyle(color: _C.ink2(context), fontSize: 11.5)),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: _basket,
              builder: (_, __) => _IconBtn(
                icon: Icons.shopping_basket_outlined,
                badge: _basket.count,
                onTap: _openBasket,
              ),
            ),
          ],
        ),
      );

  Widget _searchBar() => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        decoration: BoxDecoration(
          color: _C.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _focused ? _C.accent.withOpacity(0.65) : _C.line(context),
              width: 1.5),
          boxShadow: _focused
              ? [BoxShadow(color: _C.accent.withOpacity(0.14), blurRadius: 18)]
              : [],
        ),
        child: TextField(
          controller: _search,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(
              color: _C.ink(context),
              fontSize: 15,
              fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Company name — e.g. Reliance, TCS',
            hintStyle: TextStyle(
                color: _C.ink3(context),
                fontSize: 14,
                fontWeight: FontWeight.w400),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: Icon(Icons.search_rounded,
                  color: _focused ? _C.accent : _C.ink2(context), size: 21),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 46),
            suffixIcon: _search.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: _C.ink2(context)),
                    onPressed: () {
                      _search.clear();
                      _onChanged('');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: _onChanged,
          onSubmitted: (v) {
            _debounce?.cancel();
            _doSearch(v);
          },
        ),
      );

  Widget _body() {
    final searching = _search.text.trim().isNotEmpty;
    Widget child;
    if (searching && _loading) {
      child = ListView.builder(
        key: const ValueKey('shimmer'),
        padding: const EdgeInsets.only(top: 10),
        itemCount: 7,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (_, __) => _Skeleton(controller: _shimmer),
      );
    } else if (searching && _error != null) {
      child = _errorView(key: const ValueKey('error'));
    } else if (searching) {
      child = _resultsView(key: const ValueKey('results'));
    } else {
      child = _homeView(key: const ValueKey('home'));
    }
    return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220), child: child);
  }

  Widget _errorView({Key? key}) => Center(
        key: key,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, color: _C.ink3(context), size: 40),
              const SizedBox(height: 14),
              Text('No connection',
                  style: TextStyle(
                      color: _C.ink(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _C.ink2(context), fontSize: 13, height: 1.4)),
              const SizedBox(height: 20),
              _Primary(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  expand: false,
                  onTap: () => _doSearch(_search.text)),
            ],
          ),
        ),
      );

  Widget _resultsView({Key? key}) {
    if (_results.isEmpty) {
      return ListView(
        key: key,
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
        children: [
          Icon(Icons.search_off_rounded, color: _C.ink3(context), size: 42),
          const SizedBox(height: 14),
          Text('Nothing found for "${_search.text.trim()}"',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _C.ink(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Check the spelling or try a shorter name. Popular picks:',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _C.ink2(context), fontSize: 13, height: 1.4)),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: ['RELIANCE', 'TCS', 'HDFCBANK', 'INFY', 'SBIN']
                .map((s) => _Pill(label: s, onTap: () => _runSearch(s)))
                .toList(),
          ),
        ],
      );
    }
    return ListView.builder(
      key: key,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: _results.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 2),
            child: Text(
                '${_results.length} ${_results.length == 1 ? 'match' : 'matches'} — tap a stock to see details and add it to your basket',
                style: TextStyle(color: _C.ink2(context), fontSize: 12)),
          );
        }
        return _tile(_results[i - 1], i - 1);
      },
    );
  }

  Widget _homeView({Key? key}) {
    final list = _cache[_tab] ?? const <Map<String, dynamic>>[];
    return CustomScrollView(
      key: key,
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: _showTip
                ? _Guide(onClose: _dismissTip)
                : const SizedBox(width: double.infinity),
          ),
        ),
        if (_recent.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _Label(
              'Recently viewed',
              trailing: GestureDetector(
                onTap: _clearRecent,
                child: const Text('Clear',
                    style: TextStyle(
                        color: _C.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recent
                    .map((s) => _Pill(
                        label: s,
                        icon: Icons.history_rounded,
                        onTap: () => _runSearch(s),
                        onRemove: () => _removeRecent(s)))
                    .toList(),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
            child: _Label("What's moving today",
                topPad: _recent.isNotEmpty ? 22 : 8)),
        SliverToBoxAdapter(
          child: _MoverTabs(
            tabs: _movers,
            selected: _tab,
            onSelect: (i) {
              HapticFeedback.selectionClick();
              _loadTab(i);
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(_movers[_tab].hint,
                  key: ValueKey(_tab),
                  style: TextStyle(
                      color: _C.ink2(context), fontSize: 12, height: 1.4)),
            ),
          ),
        ),
        if (_loadingTab)
          SliverList(
            delegate: SliverChildBuilderDelegate(
                (_, __) => _Skeleton(controller: _shimmer),
                childCount: 6),
          )
        else if (list.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text('Nothing to show right now',
                      style: TextStyle(color: _C.ink2(context), fontSize: 13)),
                  const SizedBox(height: 12),
                  _Pill(
                      label: 'Refresh',
                      icon: Icons.refresh_rounded,
                      onTap: () => _loadTab(_tab, force: true)),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _tile(list[i], i, showVolume: _tab == 2),
                childCount: list.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _tile(Map<String, dynamic> s, int i, {bool showVolume = false}) {
    final sym = '${s['symbol'] ?? ''}';
    return _Reveal(
      index: i,
      child: _StockTile(
        stock: s,
        isFav: _isFav(s),
        inBasket: _basket.find(sym) != null,
        showVolume: showVolume,
        onTap: () {
          HapticFeedback.selectionClick();
          _saveRecent(_symOf(sym));
          _showStock(s);
        },
        onFav: () => _toggleFav(s),
      ),
    );
  }
}

// ───────────────────────── Stock tile ─────────────────────────
class _StockTile extends StatelessWidget {
  final Map<String, dynamic> stock;
  final bool isFav, inBasket, showVolume;
  final VoidCallback onTap, onFav;

  const _StockTile({
    required this.stock,
    required this.isFav,
    required this.inBasket,
    required this.showVolume,
    required this.onTap,
    required this.onFav,
  });

  @override
  Widget build(BuildContext context) {
    final name = _symOf(stock['symbol']);
    final company = '${stock['name'] ?? ''}'.trim();
    final ltp = _d(stock['ltp']);
    final pct = _d(stock['percent_change']);
    final pos = pct >= 0;
    final color = pct == 0 ? _C.ink2(context) : (pos ? _C.up : _C.down);
    final sub = showVolume
        ? '${_shares(stock['volume'])} shares traded'
        : (company.isNotEmpty && company.toUpperCase() != name.toUpperCase()
            ? company
            : '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _C.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.line(context)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onFav,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                _Logo(symbol: name, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: _C.ink(context),
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2)),
                        ),
                        if (isFav) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.bookmark_rounded,
                              size: 13, color: _C.mark),
                        ],
                        if (inBasket) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _C.tint(_C.accent, context),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text('IN BASKET',
                                style: TextStyle(
                                    color: _C.accent,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ),
                        ],
                      ]),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: _C.ink2(context), fontSize: 11.5)),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_money(ltp),
                        style: TextStyle(
                            color: _C.ink(context),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: pct == 0
                            ? _C.soft(context)
                            : _C.tint(color, context),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            pct == 0
                                ? Icons.remove_rounded
                                : (pos
                                    ? Icons.arrow_drop_up_rounded
                                    : Icons.arrow_drop_down_rounded),
                            size: 16,
                            color: color),
                        Text('${pct.abs().toStringAsFixed(2)}%',
                            style: TextStyle(
                                color: color,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800)),
                      ]),
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
}

// ───────────────────────── Stock sheet ─────────────────────────
const _timeframes = ['Intraday', 'Swing', 'Short Term', 'Long Term'];
const _reasons = [
  'Technical Breakout',
  'Strong Fundamentals',
  'Volume Surge',
  'Support Level',
  'News Based',
  'FOMO Entry',
  'Social Media Hype',
];

class _StockSheet extends StatefulWidget {
  final Map<String, dynamic> stock;
  final bool isFavorite;
  final VoidCallback onToggleFav, onSetAlert, onOpenBasket, onOpenDetails;

  const _StockSheet({
    required this.stock,
    required this.isFavorite,
    required this.onToggleFav,
    required this.onSetAlert,
    required this.onOpenBasket,
    required this.onOpenDetails,
  });

  @override
  State<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends State<_StockSheet> {
  final _basket = VirtualBasketStore.instance;
  final _targetC = TextEditingController();
  final _stopC = TextEditingController();
  final _reasonC = TextEditingController();

  late bool _fav;
  bool _isBuy = true;
  int _qty = 1;
  String _timeframe = 'Short Term';
  bool _moreOpen = false;
  bool _factsOpen = false;
  bool _saving = false;
  bool _saved = false;
  String? _saveError;

  String get _raw => '${widget.stock['symbol'] ?? ''}';
  String get _name => _symOf(_raw);
  double get _ltp => _d(widget.stock['ltp']);

  @override
  void initState() {
    super.initState();
    _fav = widget.isFavorite;
    final e = _basket.find(_raw);
    if (e != null) {
      _isBuy = e.isBuy;
      _qty = e.qty;
      _timeframe = e.timeframe;
      _targetC.text = e.target.toStringAsFixed(2);
      _stopC.text = e.stopLoss.toStringAsFixed(2);
      _reasonC.text = e.reason;
    } else {
      _reasonC.text = 'Technical Breakout';
      _applyDefaults();
    }
    _targetC.addListener(_onEdit);
    _stopC.addListener(_onEdit);
    _reasonC.addListener(_onEdit);
  }

  @override
  void dispose() {
    _targetC.dispose();
    _stopC.dispose();
    _reasonC.dispose();
    super.dispose();
  }

  void _onEdit() {
    if (!mounted) return;
    setState(() {
      _saved = false;
      _saveError = null;
    });
  }

  void _applyDefaults() {
    final p = _ltp;
    if (p <= 0) return;
    _targetC.text = (_isBuy ? p * 1.05 : p * 0.95).toStringAsFixed(2);
    _stopC.text = (_isBuy ? p * 0.98 : p * 1.02).toStringAsFixed(2);
  }

  void _setSide(bool buy) {
    if (_isBuy == buy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isBuy = buy;
      _saved = false;
    });
    _applyDefaults();
  }

  double? get _target => double.tryParse(_targetC.text);
  double? get _stop => double.tryParse(_stopC.text);

  double? _pct(double? v) =>
      (v != null && _ltp > 0) ? (v - _ltp) / _ltp * 100 : null;

  String? get _problem {
    final p = _ltp;
    final t = _target, s = _stop;
    if (p <= 0)
      return 'The price isn’t available right now, so this can’t be added.';
    if (t == null || t <= 0 || s == null || s <= 0) {
      return 'Enter both a profit goal and a loss limit.';
    }
    if (_isBuy) {
      if (t <= p)
        return 'For a Buy, the profit goal must be above the current price.';
      if (s >= p)
        return 'For a Buy, the loss limit must be below the current price.';
    } else {
      if (t >= p)
        return 'For a Sell, the profit goal must be below the current price.';
      if (s <= p)
        return 'For a Sell, the loss limit must be above the current price.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_problem != null) {
      HapticFeedback.heavyImpact();
      setState(() => _moreOpen = true);
      return;
    }
    if (FirebaseAuth.instance.currentUser == null) {
      setState(() => _saveError = 'Please sign in to use the virtual basket.');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final isNew = _basket.find(_raw) == null;
      final reason = _reasonC.text.trim().isEmpty
          ? 'Technical Breakout'
          : _reasonC.text.trim();
      await _basket.save(
        symbol: _raw,
        isBuy: _isBuy,
        qty: _qty,
        entryPrice: _ltp,
        target: _target!,
        stopLoss: _stop!,
        timeframe: _timeframe,
        reason: reason,
      );
      HapticFeedback.mediumImpact();
      if (isNew) {
        NotificationService().showNotificationBasic(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title: 'Added to Basket',
          body: '$_name added as ${_isBuy ? 'BUY' : 'SELL'} position.',
        );
      }
      if (mounted) setState(() => _saved = true);
    } catch (_) {
      if (mounted) {
        setState(() => _saveError =
            'Couldn’t save to your basket. Check your internet and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stock;
    final ltp = _ltp;
    final prev = _d(s['prev_close']);
    final pct = _d(s['percent_change']);
    final diff = prev > 0 ? ltp - prev : 0.0;
    final pos = pct >= 0;
    final color = pct == 0 ? _C.ink2(context) : (pos ? _C.up : _C.down);
    final company = '${s['name'] ?? ''}'.trim();
    final mood =
        pct > 0 ? 'Rising today' : (pct < 0 ? 'Falling today' : 'Flat today');
    final change = prev > 0
        ? '${diff >= 0 ? 'Up' : 'Down'} ${_money(diff.abs())} (${pct.abs().toStringAsFixed(2)}%) since yesterday’s close'
        : 'Yesterday’s price isn’t available yet';

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: _C.bg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: _C.line(context))),
          ),
          child: Column(children: [
            Expanded(
              child: ListView(
                controller: controller,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                          color: _C.line(context),
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Row(children: [
                    _Logo(symbol: _name, size: 50),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_name,
                              style: TextStyle(
                                  color: _C.ink(context),
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5)),
                          if (company.isNotEmpty &&
                              company.toUpperCase() != _name.toUpperCase())
                            Text(company,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: _C.ink2(context), fontSize: 12.5)),
                        ],
                      ),
                    ),
                    _IconBtn(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.pop(context)),
                  ]),
                  const SizedBox(height: 16),
                  _Reveal(
                    index: 0,
                    child: _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('Price right now',
                                style: TextStyle(
                                    color: _C.ink2(context),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: pct == 0
                                    ? _C.soft(context)
                                    : _C.tint(color, context),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                        pct == 0
                                            ? Icons.remove_rounded
                                            : (pos
                                                ? Icons.trending_up_rounded
                                                : Icons.trending_down_rounded),
                                        size: 14,
                                        color: color),
                                    const SizedBox(width: 4),
                                    Text(mood,
                                        style: TextStyle(
                                            color: color,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800)),
                                  ]),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: ltp * 0.97, end: ltp),
                            duration: const Duration(milliseconds: 650),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, __) => Text(_money(v),
                                style: TextStyle(
                                    color: _C.ink(context),
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1,
                                    height: 1.1)),
                          ),
                          const SizedBox(height: 6),
                          Text(change,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 12.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600)),
                          if (_has(s['low']) && _has(s['high'])) ...[
                            const SizedBox(height: 18),
                            _DayRange(
                                low: _d(s['low']),
                                high: _d(s['high']),
                                price: ltp),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Reveal(index: 2, child: _basketCard(context, ltp)),
                  const SizedBox(height: 14),
                  _Reveal(
                    index: 3,
                    child: Row(children: [
                      Expanded(
                        child: _Action(
                          icon: _fav
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          label: _fav ? 'Watchlisted' : 'Watchlist',
                          color: _C.mark,
                          active: _fav,
                          onTap: () {
                            setState(() => _fav = !_fav);
                            widget.onToggleFav();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Action(
                          icon: Icons.notifications_active_outlined,
                          label: 'Alert me',
                          color: _C.bell,
                          onTap: widget.onSetAlert,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  _Reveal(
                    index: 4,
                    child: AiAnalyseButton(
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (_, a, __) =>
                                StockAiAnalysisPage(symbol: _name),
                            transitionsBuilder: (_, anim, __, child) =>
                                SlideTransition(
                              position: Tween(
                                      begin: const Offset(0, 1),
                                      end: Offset.zero)
                                  .animate(CurvedAnimation(
                                      parent: anim,
                                      curve: Curves.easeOutCubic)),
                              child:
                                  FadeTransition(opacity: anim, child: child),
                            ),
                            transitionDuration:
                                const Duration(milliseconds: 400),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Reveal(index: 5, child: _facts(context)),
                ],
              ),
            ),
            _actionBar(context, ltp),
          ]),
        );
      },
    );
  }

  Widget _basketCard(BuildContext context, double ltp) {
    final total = ltp * _qty;
    final onePct = total * 0.01;
    final tp = _pct(_target), sp = _pct(_stop);
    String sgn(double? v) =>
        v == null ? '–' : '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)}%';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: _C.tint(_C.accent, context),
                  borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.shopping_basket_rounded,
                  size: 16, color: _C.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add to virtual basket',
                      style: TextStyle(
                          color: _C.ink(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  Text('Practice only · no real money',
                      style:
                          TextStyle(color: _C.ink2(context), fontSize: 11.5)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Text('1. What do you expect?',
              style: TextStyle(
                  color: _C.ink(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _SideCard(
                title: 'Buy',
                sub: 'I think the price will go up',
                icon: Icons.trending_up_rounded,
                color: _C.up,
                selected: _isBuy,
                onTap: () => _setSide(true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SideCard(
                title: 'Sell',
                sub: 'I think the price will go down',
                icon: Icons.trending_down_rounded,
                color: _C.down,
                selected: !_isBuy,
                onTap: () => _setSide(false),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('2. How many shares?',
                      style: TextStyle(
                          color: _C.ink(context),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('A share is one small piece of the company',
                      style:
                          TextStyle(color: _C.ink3(context), fontSize: 10.5)),
                ],
              ),
            ),
            _Stepper(
                value: _qty,
                onChanged: (v) => setState(() {
                      _qty = v;
                      _saved = false;
                    })),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [1, 5, 10, 50, 100]
                .map((q) => _Pill(
                    label: '$q',
                    selected: _qty == q,
                    onTap: () => setState(() {
                          _qty = q;
                          _saved = false;
                        })))
                .toList(),
          ),
          const SizedBox(height: 16),
          Text('3. Your plan (pre-filled — change if you like)',
              style: TextStyle(
                  color: _C.ink(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _moreOpen = !_moreOpen),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _C.soft(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _problem != null && _moreOpen
                        ? _C.down.withOpacity(0.6)
                        : Colors.transparent),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Profit goal ${_moneyOrDash(_target)} (${sgn(tp)})',
                          style: const TextStyle(
                              color: _C.up,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('Loss limit ${_moneyOrDash(_stop)} (${sgn(sp)})',
                          style: const TextStyle(
                              color: _C.down,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          '$_timeframe · ${_reasonC.text.trim().isEmpty ? 'No reason' : _reasonC.text.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _C.ink2(context), fontSize: 11.5)),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _moreOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: _C.ink2(context)),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _moreOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: _MoneyField(
                              label: 'Loss limit (stop-loss)',
                              hint: 'You’d exit here to stop losing more',
                              controller: _stopC,
                              percent: sp,
                              color: _C.down,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MoneyField(
                              label: 'Profit goal (target)',
                              hint: 'You’d exit here to lock in profit',
                              controller: _targetC,
                              percent: tp,
                              color: _C.up,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        Text('How long do you plan to hold it?',
                            style: TextStyle(
                                color: _C.ink(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _timeframes
                              .map((t) => _Pill(
                                  label: t,
                                  selected: _timeframe == t,
                                  onTap: () => setState(() {
                                        _timeframe = t;
                                        _saved = false;
                                      })))
                              .toList(),
                        ),
                        const SizedBox(height: 14),
                        Text('Why this trade?',
                            style: TextStyle(
                                color: _C.ink(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: _C.soft(context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: _reasonC,
                            maxLines: 2,
                            minLines: 1,
                            style: TextStyle(
                                color: _C.ink(context),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              hintText: 'Write your reason…',
                              hintStyle: TextStyle(
                                  color: _C.ink3(context), fontSize: 13),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _reasons
                              .map((r) => _Pill(
                                  label: r,
                                  selected: _reasonC.text.trim() == r,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    _reasonC.text = r;
                                  }))
                              .toList(),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Container(
              key: ValueKey('$_isBuy$_qty'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _C.soft(context),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      size: 16, color: _C.ink2(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isBuy
                          ? 'If the price rises 1%, you’d gain about ${_money(onePct)}. If it drops 1%, you’d lose about ${_money(onePct)}.'
                          : 'If the price drops 1%, you’d gain about ${_money(onePct)}. If it rises 1%, you’d lose about ${_money(onePct)}.',
                      style: TextStyle(
                          color: _C.ink2(context), fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context, double ltp) {
    final total = ltp * _qty;
    final sideColor = _isBuy ? _C.up : _C.down;
    final inBasket = _basket.find(_raw) != null;
    final msg = _saveError;
    final problem = _moreOpen ? _problem : null;

    return Container(
      padding: EdgeInsets.fromLTRB(
          18, 12, 18, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: _C.card(context),
        border: Border(top: BorderSide(color: _C.line(context))),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: (msg ?? problem) != null
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 16, color: _C.down),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text((msg ?? problem)!,
                          style: const TextStyle(
                              color: _C.down, fontSize: 12, height: 1.3)),
                    ),
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
        Row(children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _saved
                  ? Row(
                      key: const ValueKey('saved'),
                      children: const [
                        Icon(Icons.check_circle_rounded,
                            size: 15, color: _C.up),
                        SizedBox(width: 6),
                        Text('Saved to your virtual basket',
                            style: TextStyle(
                                color: _C.up,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ],
                    )
                  : Text('${_isBuy ? 'Buy' : 'Sell'} $_qty × ${_money(ltp)}',
                      key: const ValueKey('sum'),
                      style: TextStyle(color: _C.ink2(context), fontSize: 12)),
            ),
          ),
          Text(_money(total),
              style: TextStyle(
                  color: sideColor, fontSize: 17, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _Secondary(
              label: 'Details',
              icon: Icons.candlestick_chart_rounded,
              onTap: widget.onOpenDetails),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(
                    scale: Tween(begin: 0.96, end: 1.0).animate(a), child: c),
              ),
              child: _saved
                  ? _Primary(
                      key: const ValueKey('open'),
                      label: 'Open basket',
                      icon: Icons.shopping_basket_rounded,
                      color: _C.up,
                      onTap: widget.onOpenBasket)
                  : _Primary(
                      key: ValueKey('add$_saving'),
                      label: _saving
                          ? 'Saving…'
                          : (inBasket
                              ? 'Update virtual basket'
                              : 'Add to virtual basket'),
                      icon: _saving
                          ? null
                          : (inBasket
                              ? Icons.sync_rounded
                              : Icons.add_shopping_cart_rounded),
                      onTap: _saving ? null : _save),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _facts(BuildContext context) {
    final s = widget.stock;
    return Container(
      decoration: BoxDecoration(
        color: _C.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.line(context)),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _factsOpen = !_factsOpen),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: _C.ink2(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text("Today's numbers, explained",
                    style: TextStyle(
                        color: _C.ink(context),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
              ),
              AnimatedRotation(
                turns: _factsOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    color: _C.ink2(context)),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _factsOpen
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Column(children: [
                    _Fact('Opened at', 'Price when the market opened today',
                        _moneyOrDash(s['open'])),
                    _Fact(
                        'Yesterday closed at',
                        'Price at the end of the last trading day',
                        _moneyOrDash(s['prev_close'])),
                    _Fact("Today's lowest", 'Cheapest price so far today',
                        _moneyOrDash(s['low']),
                        color: _C.down),
                    _Fact(
                        "Today's highest",
                        'Most expensive price so far today',
                        _moneyOrDash(s['high']),
                        color: _C.up),
                    _Fact(
                        'Shares traded',
                        'How many shares changed hands today (L = lakh, Cr = crore)',
                        _shares(s['volume']),
                        last: true),
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

// ───────────────────────── Floating basket bar ─────────────────────────
class _BasketBar extends StatelessWidget {
  final VirtualBasketStore basket;
  final bool visible;
  final VoidCallback onTap;
  const _BasketBar(
      {required this.basket, required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: basket,
      builder: (context, _) {
        final show = visible && !basket.isEmpty;
        return IgnorePointer(
          ignoring: !show,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            offset: show ? Offset.zero : const Offset(0, 1.5),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: show ? 1 : 0,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(basket.count),
                tween: Tween(begin: 1.06, end: 1.0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (_, s, child) =>
                    Transform.scale(scale: s, child: child),
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: _C.accent,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                            color: _C.accent.withOpacity(0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Row(children: [
                      const Icon(Icons.shopping_basket_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            '${basket.count} ${basket.count == 1 ? 'stock' : 'stocks'} in virtual basket',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5)),
                      ),
                      const Text('Open',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 16),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────── Reusable widgets ─────────────────────────
class _Reveal extends StatelessWidget {
  final int index;
  final Widget child;
  const _Reveal({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final ms = 280 + math.min(index, 8) * 70;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: c),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _C.card(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _C.line(context)),
        ),
        child: child,
      );
}

class _Logo extends StatelessWidget {
  final String symbol;
  final double size;
  const _Logo({required this.symbol, required this.size});

  @override
  Widget build(BuildContext context) {
    Widget letter() => Center(
          child: Text(symbol.isNotEmpty ? symbol[0] : '?',
              style: TextStyle(
                  color: _C.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.42)),
        );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _C.soft(context),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: _C.line(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: CachedNetworkImage(
          imageUrl: '${Constants.OptionXiS3Loc}$symbol.png',
          fit: BoxFit.cover,
          placeholder: (_, __) => letter(),
          errorWidget: (_, __, ___) => letter(),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badge;
  const _IconBtn({required this.icon, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _C.card(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.line(context)),
            ),
            child: Icon(icon, size: 18, color: _C.ink(context)),
          ),
          Positioned(
            right: -4,
            top: -4,
            child: AnimatedScale(
              scale: badge > 0 ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                    color: _C.accent,
                    borderRadius: BorderRadius.all(Radius.circular(9))),
                alignment: Alignment.center,
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ]),
      );
}

class _Primary extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool expand;
  final Color color;
  const _Primary({
    Key? key,
    required this.label,
    required this.onTap,
    this.icon,
    this.expand = true,
    this.color = _C.accent,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: onTap != null ? 1 : 0.6,
          child: Container(
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Secondary extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _Secondary(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _C.accent.withOpacity(0.5), width: 1.4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: _C.accent),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: _C.accent,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  const _Pill({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _C.tint(_C.accent, context) : _C.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? _C.accent : _C.line(context)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: _C.ink3(context)),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    color: selected ? _C.accent : _C.ink2(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
            if (onRemove != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onRemove,
                child: Icon(Icons.close_rounded,
                    size: 13, color: _C.ink3(context)),
              ),
            ],
          ]),
        ),
      );
}

class _MoverTabs extends StatelessWidget {
  final List<_Mover> tabs;
  final int selected;
  final ValueChanged<int> onSelect;
  const _MoverTabs(
      {required this.tabs, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final n = tabs.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _C.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.line(context)),
      ),
      child: LayoutBuilder(builder: (_, box) {
        final w = box.maxWidth / n;
        final c = tabs[selected].color;
        return SizedBox(
          height: 40,
          child: Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              left: w * selected,
              top: 0,
              bottom: 0,
              width: w,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Row(
              children: List.generate(n, (i) {
                final sel = i == selected;
                final col = tabs[i].color;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(i),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(tabs[i].icon,
                            size: 14, color: sel ? col : _C.ink3(context)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(tabs[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: sel ? col : _C.ink2(context),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ]),
        );
      }),
    );
  }
}

class _Guide extends StatelessWidget {
  final VoidCallback onClose;
  const _Guide({required this.onClose});

  @override
  Widget build(BuildContext context) {
    Widget step(IconData i, String t, String d) => Expanded(
          child: Column(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: _C.tint(_C.accent, context),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(i, size: 19, color: _C.accent),
            ),
            const SizedBox(height: 8),
            Text(t,
                style: TextStyle(
                    color: _C.ink(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(d,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _C.ink2(context), fontSize: 10.5, height: 1.3)),
          ]),
        );

    return _Reveal(
      index: 0,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        decoration: BoxDecoration(
          color: _C.card(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _C.line(context)),
        ),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Text('New here? It takes 3 steps',
                  style: TextStyle(
                      color: _C.ink(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon:
                  Icon(Icons.close_rounded, size: 18, color: _C.ink3(context)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                step(Icons.search_rounded, 'Search', 'Type a company name'),
                step(Icons.touch_app_rounded, 'Tap it', "See today's price"),
                step(Icons.add_shopping_cart_rounded, 'Add it',
                    'Choose Buy or Sell, then add to basket'),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _DayRange extends StatelessWidget {
  final double low, high, price;
  const _DayRange({required this.low, required this.high, required this.price});

  @override
  Widget build(BuildContext context) {
    final span = high - low;
    final pos = span <= 0 ? 0.5 : ((price - low) / span).clamp(0.0, 1.0);

    Widget end(String l, String v, CrossAxisAlignment a) => Column(
          crossAxisAlignment: a,
          children: [
            Text(l, style: TextStyle(color: _C.ink3(context), fontSize: 10.5)),
            Text(v,
                style: TextStyle(
                    color: _C.ink(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ],
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Today's price range",
          style: TextStyle(
              color: _C.ink2(context),
              fontSize: 11.5,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: pos.toDouble()),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, p, __) => LayoutBuilder(builder: (_, box) {
          final w = box.maxWidth;
          return SizedBox(
            height: 16,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(
                    height: 6,
                    decoration: BoxDecoration(
                        color: _C.soft(context),
                        borderRadius: BorderRadius.circular(3))),
                Container(
                    height: 6,
                    width: w * p,
                    decoration: BoxDecoration(
                        color: _C.accent.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(3))),
                Positioned(
                  left: (w - 16) * p,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _C.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: _C.card(context), width: 2.5),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
      const SizedBox(height: 8),
      Row(children: [
        end('Lowest', _money(low), CrossAxisAlignment.start),
        const Spacer(),
        end('Highest', _money(high), CrossAxisAlignment.end),
      ]),
    ]);
  }
}

class _SideCard extends StatelessWidget {
  final String title, sub;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _SideCard({
    required this.title,
    required this.sub,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.12) : _C.soft(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? color : Colors.transparent, width: 1.5),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: selected ? color : _C.ink3(context)),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      color: selected ? color : _C.ink2(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 4),
            Text(sub,
                style: TextStyle(
                    color: _C.ink2(context), fontSize: 11, height: 1.3)),
          ]),
        ),
      );
}

class _Stepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _Stepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, VoidCallback? onTap) => GestureDetector(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: _C.soft(context),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(i,
                size: 18,
                color: onTap == null ? _C.ink3(context) : _C.ink(context)),
          ),
        );

    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.remove_rounded, value > 1 ? () => onChanged(value - 1) : null),
      SizedBox(
        width: 52,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Text('$value',
              key: ValueKey(value),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _C.ink(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ),
      ),
      btn(Icons.add_rounded, value < 10000 ? () => onChanged(value + 1) : null),
    ]);
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _Action({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: color.withOpacity(active ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: color.withOpacity(active ? 0.55 : 0.28)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _Fact extends StatelessWidget {
  final String label, caption, value;
  final Color? color;
  final bool last;
  const _Fact(this.label, this.caption, this.value,
      {this.color, this.last = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border:
              last ? null : Border(bottom: BorderSide(color: _C.line(context))),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: _C.ink(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(caption,
                    style: TextStyle(
                        color: _C.ink3(context), fontSize: 10.5, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(value,
              style: TextStyle(
                  color: color ?? _C.ink(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800)),
        ]),
      );
}

class _Label extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final double topPad;
  const _Label(this.text, {this.trailing, this.topPad = 16});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(18, topPad, 18, 10),
        child: Row(children: [
          Text(text,
              style: TextStyle(
                  color: _C.ink(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2)),
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
      );
}

class _Skeleton extends StatelessWidget {
  final AnimationController controller;
  const _Skeleton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = (math.sin(controller.value * math.pi * 2) + 1) / 2;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final base = dark ? const Color(0xFF1D2230) : const Color(0xFFEEF0F6);
        final hi = dark ? const Color(0xFF262D42) : const Color(0xFFD8DCE8);
        final c = Color.lerp(base, hi, t)!;

        Widget box(double w, double h, [double r = 4]) => Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(r)));

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _C.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.line(context)),
          ),
          child: Row(children: [
            box(44, 44, 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [box(100, 12), const SizedBox(height: 6), box(60, 9)],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [box(64, 12), const SizedBox(height: 6), box(44, 16)],
            ),
            const SizedBox(width: 10),
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          ]),
        );
      },
    );
  }
}

class _MoneyField extends StatelessWidget {
  final String label, hint;
  final TextEditingController controller;
  final double? percent;
  final Color color;
  const _MoneyField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _C.soft(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Row(children: [
          Text('₹',
              style: TextStyle(
                  color: _C.ink2(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 3),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,6}\.?\d{0,2}')),
              ],
              style: TextStyle(
                  color: _C.ink(context),
                  fontSize: 17,
                  fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero),
            ),
          ),
        ]),
        const SizedBox(height: 2),
        Text(
            percent == null
                ? hint
                : '${percent! >= 0 ? '+' : '−'}${percent!.abs().toStringAsFixed(1)}% · $hint',
            style:
                TextStyle(color: _C.ink3(context), fontSize: 10, height: 1.3)),
      ]),
    );
  }
}
