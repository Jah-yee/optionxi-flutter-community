import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import 'package:optionxi/VirtualTradeJournal/db_read_supabase_journal_portfolio.dart';
import 'package:optionxi/VirtualTrading/VDataModel/v_holdings_journal.dart';
import 'package:optionxi/VirtualTrading/VDataModel/v_tradehistory.dart';

/// Drives the "Open trades / Closed trades" screen.
///
/// What changed vs. the previous version (all of these could make positions
/// vanish or look wrong):
///  * Fetch errors no longer wipe the lists (the service now rethrows and we
///    keep the last good data + raise [hasError]).
///  * Pull-to-refresh no longer flips [isLoading] (which used to tear down the
///    whole TabBarView). Only the very first load uses [isLoading].
///  * A slow one-off fetch can no longer overwrite fresher realtime data
///    (version guards), and out-of-order trade-history responses are ignored.
///  * The user id is resolved safely (waits for Firebase auth if needed)
///    instead of silently querying with an empty id.
///  * Live prices are only tracked for symbols you actually hold, so we don't
///    rebuild the UI 5,000 times per tick. Missing prices fall back to your
///    buy price (P&L 0) instead of showing a fake 100% loss.
///  * Timers / subscriptions are all cancelled on close.
class PortfolioJournalController extends GetxController {
  final String? suid;

  PortfolioJournalController({this.suid});

  String userSuid = '';

  final PortfolioJournalService _portfolioService = PortfolioJournalService();

  // ── UI state ───────────────────────────────────────────────────────────
  /// True only until the first successful load.
  final RxBool isLoading = true.obs;

  /// True while a manual / background refresh runs (data stays on screen).
  final RxBool isRefreshing = false.obs;

  /// True while the closed-trades list is being re-fetched for a new period.
  final RxBool isHistoryLoading = false.obs;

  /// True when the last fetch failed. Old data (if any) is kept on screen.
  final RxBool hasError = false.obs;

  /// Currently selected period for closed trades, in days. Default = 30.
  final RxInt selectedDays = 30.obs;

  /// Period chips. [label] is what people read, [days] drives the query.
  static const List<({String label, int days})> filterOptions = [
    (label: '7 days', days: 7),
    (label: '30 days', days: 30),
    (label: '3 months', days: 90),
    (label: '6 months', days: 180),
    (label: '1 year', days: 365),
    (label: 'All time', days: 3650),
  ];

  /// "last 30 days" / "all time" – for captions.
  String get periodText {
    final opt = filterOptions.firstWhere(
      (o) => o.days == selectedDays.value,
      orElse: () => filterOptions[1],
    );
    return opt.days == 3650 ? 'all time' : 'last ${opt.label}';
  }

  // ── Data ───────────────────────────────────────────────────────────────
  final RxList<BasketUserHolding> holdings = <BasketUserHolding>[].obs;
  final RxList<BasketUserHolding> shortPositions = <BasketUserHolding>[].obs;
  final RxList<JournalTradeHistory> tradeHistory = <JournalTradeHistory>[].obs;

  /// Live prices for symbols we hold (symbol -> last traded price).
  final RxMap<String, double> livePrices = <String, double>{}.obs;

  // ── Stats ──────────────────────────────────────────────────────────────
  final RxDouble totalProfit = 0.0.obs;
  final RxDouble totalInvestment = 0.0.obs;
  final RxDouble realisedPnl = 0.0.obs;
  final RxDouble unrealisedPnl = 0.0.obs;
  final RxInt totalWins = 0.obs;
  final RxInt totalLosses = 0.obs;
  final RxInt totalTrades = 0.obs;

  /// % of closed trades (that weren't break-even) that made money.
  double get winRate {
    final decided = totalWins.value + totalLosses.value;
    return decided == 0 ? 0.0 : totalWins.value / decided * 100;
  }

  // ── Internals ──────────────────────────────────────────────────────────
  bool _closed = false;
  bool _hasLoadedOnce = false;

  /// Bumped every time a realtime event replaces a list. A one-off fetch that
  /// started before the bump is stale and must not overwrite it.
  int _holdingsVer = 0;
  int _shortsVer = 0;

  /// Only the newest trade-history request may apply its result.
  int _historyReq = 0;

  /// Every price we've seen (all symbols, plain map – no UI rebuilds).
  final Map<String, double> _allPrices = {};

  StreamSubscription? _holdingsSubscription;
  StreamSubscription? _shortsSubscription;
  StreamSubscription? _historySubscription;
  StreamSubscription? _nifty50Subscription;
  StreamSubscription? _fnoSubscription;
  Timer? _retryTimer;
  Timer? _historyDebounce;

  @override
  void onInit() {
    super.onInit();
    _bootstrap();
  }

  @override
  void onClose() {
    _closed = true;
    _retryTimer?.cancel();
    _historyDebounce?.cancel();
    _cancelSubscriptions();
    super.onClose();
  }

  Future<void> _bootstrap() async {
    userSuid = await _resolveUid();
    if (_closed) return;
    if (userSuid.isEmpty) {
      // Not signed in (yet). Show the error state instead of a fake
      // "no positions" screen.
      hasError(true);
      isLoading(false);
      return;
    }
    // Start listening first, then do a one-off fetch as a safety net.
    _setupSubscriptions();
    await fetchAllData();
  }

  Future<String> _resolveUid() async {
    final given = suid;
    if (given != null && given.isNotEmpty) return given;
    final current = FirebaseAuth.instance.currentUser?.uid;
    if (current != null && current.isNotEmpty) return current;
    try {
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 8));
      return user?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────

  /// User tapped a period chip (7 days / 30 days / …).
  void onFilterChanged(int days) {
    if (selectedDays.value == days) return;
    selectedDays.value = days;
    _fetchTradeHistoryWithFilter();
  }

  /// Pull-to-refresh / retry. Safe to call any time.
  Future<void> fetchAllData() async {
    if (userSuid.isEmpty) {
      userSuid = await _resolveUid();
      if (_closed) return;
      if (userSuid.isEmpty) {
        hasError(true);
        isLoading(false);
        return;
      }
      if (_holdingsSubscription == null) _setupSubscriptions();
    }

    hasError(false);
    if (_hasLoadedOnce) {
      isRefreshing(true);
    } else {
      isLoading(true);
    }

    final hv = _holdingsVer;
    final sv = _shortsVer;
    final req = ++_historyReq;

    try {
      final results = await Future.wait([
        _portfolioService.fetchHoldings(userSuid),
        _portfolioService.fetchShortPositions(userSuid),
        _portfolioService.fetchTradeHistory(userSuid, days: selectedDays.value),
      ]);
      if (_closed) return;

      // Only apply if realtime hasn't already delivered something fresher.
      if (hv == _holdingsVer) {
        _setHoldings(results[0] as List<BasketUserHolding>);
      }
      if (sv == _shortsVer) {
        _setShorts(results[1] as List<BasketUserHolding>);
      }
      if (req == _historyReq) {
        _setHistory(results[2] as List<JournalTradeHistory>);
      }

      _hasLoadedOnce = true;
      _calculateStats();
    } catch (e) {
      if (_closed) return;
      // Keep whatever is on screen; just tell the UI something went wrong.
      hasError(true);
      debugPrint('Portfolio fetch error: $e');
    } finally {
      if (!_closed) {
        isLoading(false);
        isRefreshing(false);
      }
    }
  }

  Future<void> refreshData() => fetchAllData();

  /// Last known price, or 0.0 if we haven't received one yet.
  double getLtp(String symbol) => livePrices[symbol] ?? 0.0;

  /// Do we have a real live price for this symbol?
  bool hasPrice(String symbol) => (livePrices[symbol] ?? 0.0) > 0;

  // ── Setters (keep newest first) ────────────────────────────────────────

  void _setHoldings(List<BasketUserHolding> data) {
    holdings.assignAll(_newestFirst(data));
    _syncHeldPrices();
  }

  void _setShorts(List<BasketUserHolding> data) {
    shortPositions.assignAll(_newestFirst(data));
    _syncHeldPrices();
  }

  void _setHistory(List<JournalTradeHistory> data) {
    final sorted = List<JournalTradeHistory>.from(data)
      ..sort((a, b) => b.exitDate.compareTo(a.exitDate));
    tradeHistory.assignAll(sorted);
  }

  List<BasketUserHolding> _newestFirst(List<BasketUserHolding> data) {
    final sorted = List<BasketUserHolding>.from(data)
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
    return sorted;
  }

  // ── Realtime ───────────────────────────────────────────────────────────

  Future<void> _fetchTradeHistoryWithFilter() async {
    final req = ++_historyReq;
    isHistoryLoading(true);
    try {
      final history = await _portfolioService.fetchTradeHistory(
        userSuid,
        days: selectedDays.value,
      );
      if (_closed || req != _historyReq) return; // a newer request won
      _setHistory(history);
      _calculateStats();
      hasError(false);
    } catch (e) {
      if (_closed || req != _historyReq) return;
      debugPrint('Trade history fetch error: $e');
      hasError(true);
    } finally {
      if (!_closed && req == _historyReq) isHistoryLoading(false);
    }
  }

  void _setupSubscriptions() {
    _cancelSubscriptions();

    _holdingsSubscription =
        _portfolioService.subscribeToHoldings(userSuid).listen(
      (data) {
        _holdingsVer++;
        _setHoldings(data);
        _calculateStats();
      },
      onError: (e) => _handleSubscriptionError('Holdings', e),
    );

    _shortsSubscription =
        _portfolioService.subscribeToShortPositions(userSuid).listen(
      (data) {
        _shortsVer++;
        _setShorts(data);
        _calculateStats();
      },
      onError: (e) => _handleSubscriptionError('Short Positions', e),
    );

    _historySubscription =
        _portfolioService.subscribeToTradeHistoryChanges(userSuid).listen(
      (_) {
        // Several events can arrive back-to-back; refetch once.
        _historyDebounce?.cancel();
        _historyDebounce = Timer(
          const Duration(milliseconds: 350),
          _fetchTradeHistoryWithFilter,
        );
      },
      onError: (e) => _handleSubscriptionError('Trade History', e),
    );

    _nifty50Subscription = _portfolioService.subscribeToLiveNifty50().listen(
          _updateLivePrices,
          onError: (e) => _handleSubscriptionError('Live Nifty50', e),
        );

    _fnoSubscription = _portfolioService.subscribeToLiveFNO().listen(
          _updateLivePrices,
          onError: (e) => _handleSubscriptionError('Live FNO', e),
        );
  }

  void _handleSubscriptionError(String name, dynamic error) {
    debugPrint('$name subscription error: $error');
    if (_closed) return;
    _retryTimer?.cancel(); // never stack several retries
    _retryTimer = Timer(const Duration(seconds: 5), () {
      if (_closed) return;
      _setupSubscriptions();
    });
  }

  void _cancelSubscriptions() {
    _holdingsSubscription?.cancel();
    _shortsSubscription?.cancel();
    _historySubscription?.cancel();
    _nifty50Subscription?.cancel();
    _fnoSubscription?.cancel();
    _holdingsSubscription = null;
    _shortsSubscription = null;
    _historySubscription = null;
    _nifty50Subscription = null;
    _fnoSubscription = null;
  }

  // ── Live prices ────────────────────────────────────────────────────────

  Set<String> _heldSymbols() => {
        for (final h in holdings) h.symbol,
        for (final s in shortPositions) s.symbol,
      };

  void _updateLivePrices(List<Map<String, dynamic>> data) {
    final held = _heldSymbols();
    final changed = <String, double>{};

    for (final stock in data) {
      final symbol = stock['symbol'];
      if (symbol is! String) continue;
      final ltp = (stock['ltp'] as num?)?.toDouble() ??
          (stock['close'] as num?)?.toDouble();
      if (ltp == null || ltp <= 0) continue;
      _allPrices[symbol] = ltp;
      if (held.contains(symbol) && livePrices[symbol] != ltp) {
        changed[symbol] = ltp;
      }
    }

    if (changed.isNotEmpty) {
      livePrices.addAll(changed); // one notification for the whole batch
      _calculateStats();
    }
  }

  /// A position was just added: pick up its price from what we've already seen
  /// so it doesn't wait for the next tick.
  void _syncHeldPrices() {
    final missing = <String, double>{};
    for (final symbol in _heldSymbols()) {
      final seen = _allPrices[symbol];
      if (seen != null && livePrices[symbol] == null) missing[symbol] = seen;
    }
    if (missing.isNotEmpty) livePrices.addAll(missing);
  }

  // ── Stats ──────────────────────────────────────────────────────────────

  void _calculateStats() {
    // 1. Booked profit/loss (closed trades in the selected period)
    realisedPnl.value =
        tradeHistory.fold(0.0, (sum, item) => sum + item.profitLoss);

    // 2. Running profit/loss (open trades). No price yet -> assume no change.
    double running = 0.0;
    for (final h in holdings) {
      final ltp = hasPrice(h.symbol) ? getLtp(h.symbol) : h.averagePrice;
      running += (ltp - h.averagePrice) * h.quantity;
    }
    for (final s in shortPositions) {
      final ltp = hasPrice(s.symbol) ? getLtp(s.symbol) : s.averagePrice;
      running += (s.averagePrice - ltp) * s.quantity;
    }
    unrealisedPnl.value = running;

    // 3. Overall
    totalProfit.value = realisedPnl.value + unrealisedPnl.value;

    // 4. Money currently in the market (at the price you got in)
    double invested = 0.0;
    for (final h in holdings) {
      invested += h.averagePrice * h.quantity;
    }
    for (final s in shortPositions) {
      invested += s.averagePrice * s.quantity;
    }
    totalInvestment.value = invested;

    // 5. Win / loss counts
    totalTrades.value = tradeHistory.length;
    totalWins.value = tradeHistory.where((t) => t.profitLoss > 0).length;
    totalLosses.value = tradeHistory.where((t) => t.profitLoss < 0).length;
  }
}
