import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:optionxi/Auth_Service/auth_service.dart';
import 'package:optionxi/Main_Pages/AIStockPick/act_stock_pick.dart';
import 'package:optionxi/Main_Pages/BrokersConnect/connect_fyers_page.dart';
import 'package:optionxi/Main_Pages/BrokersConnect/connect_upstox_page.dart';
import 'package:optionxi/Main_Pages/BrokersConnect/connect_zerodha_page.dart';
import 'package:optionxi/Helpers/badge_service.dart';
import 'package:optionxi/Helpers/get_database.dart';
import 'package:optionxi/Login_Signup/login2.dart';
import 'package:optionxi/Main_Pages/Achivements/act_achievement_page.dart';
import 'package:optionxi/Main_Pages/Community/community_sync_gate.dart';
import 'package:optionxi/Main_Pages/IndicatorBacktest/indicator-backtest.dart';
import 'package:optionxi/Main_Pages/Leaderboard/act_leaderboard.dart';
import 'package:optionxi/Main_Pages/Learning/act_learn_optionxi.dart';
import 'package:optionxi/Main_Pages/Learning/act_route_not_found.dart';
import 'package:optionxi/Main_Pages/MarketSentiments/act_market_sentiments.dart';
import 'package:optionxi/Main_Pages/MarketSentiments/act_market_sentiments_chart.dart';
import 'package:optionxi/Main_Pages/News/act_news.dart';
import 'package:optionxi/Main_Pages/ScreenerPro/act_custom_screener_pro.dart';
import 'package:optionxi/Main_Pages/DeployedAlgos/Act_DeployedAlgos.dart';
import 'package:optionxi/Main_Pages/AccuracyNiftyStocks/act_nifty_accuracy.dart';
import 'package:optionxi/Main_Pages/AccuracyNiftyStocks/act_stocks_accuracy.dart';
import 'package:optionxi/Main_Pages/StockPages/act_alert_stocks.dart';
import 'package:optionxi/Main_Pages/Notification/act_notifications.dart';
import 'package:optionxi/Main_Pages/PracticeTrading/act_prevday_trading.dart';
import 'package:optionxi/Main_Pages/Scanner/act_scanner_result.dart';
import 'package:optionxi/Main_Pages/Screener/act_screener_history.dart';
import 'package:optionxi/Main_Pages/Search/act_search_stocks_meili.dart';
import 'package:optionxi/Main_Pages/StockPages/act_setalert_page_all.dart';
import 'package:optionxi/Main_Pages/StockPages/act_stock_detail.dart';
import 'package:optionxi/Main_Pages/SubscriptionsRazorpay/act_subscription_razorpay.dart';
import 'package:optionxi/PushNotification/notifcation_service.dart';
import 'package:optionxi/PushNotification/notifcation_service_firebase.dart';
import 'package:optionxi/Theme/theme_controller.dart';
import 'package:optionxi/VirtualTradeJournal/act_basket_fullpage.dart';
import 'package:optionxi/homepage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:optionxi/Main_Pages/TopGainers-Recommended/act_top_recommended_stock_page.dart';
import 'package:optionxi/Main_Pages/TopGainers-Recommended/act_topgainers_losers.dart';
import 'package:optionxi/Main_Pages/Scanner/act_scanner_page.dart';
import 'package:optionxi/Main_Pages/OptionCalculator/act_optionchain_master.dart';
import 'package:optionxi/Main_Pages/OptionCalculator/act_option_calculator.dart';
import 'package:optionxi/Main_Pages/OptionCalculator/act_oi_analyser.dart';
import 'package:optionxi/Main_Pages/AIIndexPick/act_index_pick.dart';
import 'package:optionxi/Main_Pages/BollingerBreakouts/act_breakout_page.dart';
import 'package:optionxi/Main_Pages/Sectorwise/act_sectorwise_page.dart';
import 'package:optionxi/Main_Pages/AISummary/act_nifty_ai_summary.dart';
import 'package:optionxi/Main_Pages/AISummary/act_stock_ai_summary.dart';
import 'package:optionxi/StrategyBuilder/strategy_builder.dart';
import 'package:optionxi/VirtualTradeJournal/act_journal_analytics.dart';
import 'package:optionxi/Main_Pages/News/act_news.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeApp();
  final themeController = Get.put(ThemeController());
  await themeController.initTheme();

  runApp(const MyApp());
}

Future<void> _initializeApp() async {
  try {
    // Step 1: Load environment variables
    await dotenv.load();

    // Step 2: Initialize Firebase (required for FCM)
    await Firebase.initializeApp();
    debugPrint("Firebase initialized");

    // Step 2.5: Initialize Crashlytics
    await _initializeCrashlytics();

    // Step 3: Initialize Supabase
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
    debugPrint("Supabase initialized");

    // Step 4: Initialize database
    await Get.put(Database()).initStorage();
    debugPrint("Database initialized");

    // Step 5: Initialize services in parallel
    await Future.wait([
      _requestNotificationPermission(),
      _initializeNotificationServices(),
      _initializeRemoteConfig(),
    ]);

    // Step 6: Initialize timezone data
    _initializeTimezones();

    // Initialize badge service
    await BadgeService
        .initializeBadgeStreams(); // For StreamController approach

    debugPrint("App initialization completed successfully");
  } catch (e) {
    debugPrint('App initialization error: $e');
  }
}

Future<void> _initializeCrashlytics() async {
  try {
    // Enable Crashlytics collection
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

    // Set up custom keys for better error tracking
    FirebaseCrashlytics.instance.setCustomKey('app_name', 'OptionXi');
    FirebaseCrashlytics.instance
        .setCustomKey('environment', kDebugMode ? 'debug' : 'production');

    debugPrint("Crashlytics initialized");
  } catch (e) {
    debugPrint('Crashlytics initialization error: $e');
  }
}

Future<void> _requestNotificationPermission() async {
  try {
    final status = await Permission.notification.status.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint("Permission check timeout");
        return PermissionStatus.denied;
      },
    );

    if (status.isDenied) {
      final result = await Permission.notification.request().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint("Permission request timeout");
          return PermissionStatus.denied;
        },
      );
      debugPrint("Notification permission status: $result");
    }
  } catch (e) {
    debugPrint('Permission error: $e');
  }
}

Future<void> _initializeNotificationServices() async {
  try {
    await Future.wait([
      NotificationService().initNotification().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint("NotificationService timeout");
          return null; // Return null instead of throwing
        },
      ).catchError((e) {
        debugPrint("NotificationService error: $e");
        return null;
      }),
      NotificationServiceFirebase().initNotificationFirebase().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint("NotificationServiceFirebase timeout");
          return null;
        },
      ).catchError((e) {
        debugPrint("NotificationServiceFirebase error: $e");
        return null;
      }),
    ]);
    debugPrint("Notification services initialized");
  } catch (e) {
    debugPrint('Notification services error: $e');
    // Don't rethrow - allow app to continue
  }
}

Future<void> _initializeRemoteConfig() async {
  try {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));

    await remoteConfig.fetchAndActivate().timeout(
          const Duration(seconds: 10),
        );

    debugPrint("Remote Config initialized");
  } catch (e) {
    debugPrint('Remote Config error: $e');
  }
}

void _initializeTimezones() {
  tz_data.initializeTimeZones();
  debugPrint("Timezones initialized");
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetX<ThemeController>(
      builder: (themeController) {
        return GetMaterialApp(
          title: 'Option Xi',
          debugShowCheckedModeBanner: false,
          theme: themeController.lightTheme,
          darkTheme: themeController.darkTheme,
          initialRoute: '/',
          themeMode:
              themeController.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          getPages: _buildRoutes(),
          unknownRoute: GetPage(
            name: '/not-found',
            page: () => RouteNotFoundPage(),
          ),
        );
      },
    );
  }

  List<GetPage> _buildRoutes() {
    return [
      GetPage(name: '/', page: () => AuthService().handleAuthState()),
      GetPage(name: '/home', page: () => Homepage()),
      GetPage(name: '/login', page: () => ModernLoginPage()),
      // GetPage(
      //     name: '/subscription-google', page: () => SubscriptionScreenModern()),
      GetPage(
          name: '/subscription-razorpay',
          page: () => SubscriptionScreenRazorPay()),

      GetPage(name: '/alerts', page: () => MyAlertsPage()),
      GetPage(name: '/notifications', page: () => NotificationPage()),
      GetPage(
          name: '/premium-notifications',
          page: () => NotificationPage(initialTabIndex: 1)),
      GetPage(name: '/achievements', page: () => AchievementsPage()),
      GetPage(name: '/virtual-basket', page: () => BasketFullPage()),
      GetPage(name: '/stocks', page: () => AllSearchPageMeili()),
      GetPage(name: '/leaderboard', page: () => LeaderboardPage()),
      GetPage(name: '/screenerpro', page: () => StockScreenerPagePro()),
      GetPage(name: '/community', page: () => const CommunitySyncGate()),
      GetPage(
        name: '/stocks/:stockName',
        page: () {
          final stockName = Get.parameters['stockName'] ?? '';
          return StockDetailPage(stockname: stockName);
        },
        transition: Transition.rightToLeft,
      ),
      GetPage(
        name: '/alerts/:stockName',
        page: () {
          final stockName = Get.parameters['stockName'];
          return StockAlertsPage(stockName);
        },
        transition: Transition.rightToLeft,
      ),
      GetPage(
        name: '/scanners/:scanName',
        page: () {
          final scanName = Get.parameters['scanName'] ?? '';
          final arguments = Get.arguments as Map<String, dynamic>?;
          final category = arguments?['category'] as String?;

          return ScannerDetailPage(
            scanName: scanName,
            category: category,
          );
        },
      ),

      GetPage(
        name: '/virtual-trading/orders',
        page: () => PreviousDayTrading(initialFragIndex: 1),
        transition: Transition.fade,
      ),
      GetPage(name: '/connect/zerodha', page: () => ZerodhaConnectPage()),
      GetPage(name: '/connect/upstox', page: () => UpstoxConnectPage()),
      GetPage(name: '/connect/fyers', page: () => FyersConnectPage()),

      //Market Sentiments routes
      GetPage(
        name: '/market-sentiments',
        page: () => MarketSentimentPage(),
        transition: Transition.fade,
      ),
      GetPage(
        name: '/market-sentiments-chart',
        page: () => MarketSentimentChartPage(),
        transition: Transition.fade,
      ),

      //Market Sentiments Stocks
      GetPage(
        name: '/ai-picked-stocks',
        page: () => AIPickedStocksPage(),
        transition: Transition.fade,
      ),

      //Saved backtest nifty
      GetPage(
        name: '/saved-backtest',
        page: () => SavedBacktestsPage(),
        transition: Transition.fade,
      ),

      // Learning routes
      GetPage(
        name: '/learn-optionxi',
        page: () => LearnOptionXIPage(),
        transition: Transition.fade,
      ),

      // ═══════════ TOOLS TAB ROUTES (grouped like ToolsRegistry) ═══════════

      // ── Find stocks ──
      // top_picks
      GetPage(
        name: '/top-picks',
        page: () => const TopRecommendedStockPage(),
        transition: Transition.rightToLeft,
      ),
      // screeners  (predefined filters)
      GetPage(
        name: '/screeners',
        page: () => const StockScreenerPage(),
        transition: Transition.fade,
      ),
      // top_movers
      GetPage(
        name: '/top-movers',
        page: () => const TopGainersLosersPage(),
        transition: Transition.fade,
      ),
      // custom_screeners -> already exists: '/screenerpro'

      // ── Options ──
      // option_chain
      GetPage(
        name: '/option-chain',
        page: () => const OptionChainPage(),
        transition: Transition.fade,
      ),
      // option_budget  (FNO Budget)
      GetPage(
        name: '/option-budget',
        page: () => const OptionCalculatorPage(),
        transition: Transition.fade,
      ),
      // option_oi  (OI Activity)
      GetPage(
        name: '/option-oi',
        page: () => const OiActivityPage(),
        transition: Transition.fade,
      ),

      // ── Index ──
      // index_breakout  (Nifty / Bank Nifty day high-low breaks)
      GetPage(
        name: '/index-breakout',
        page: () => const AIPickedIndexPage(),
        transition: Transition.fade,
      ),
      // bollinger_alerts
      GetPage(
        name: '/bollinger-breakouts',
        page: () => const BreakoutSignalsPage(),
        transition: Transition.fade,
      ),

      // ── Backtest ──
      // strategy_backtest -> already exists: '/saved-backtest'

      // option_testing  (virtual option buy + replay)
      GetPage(
        name: '/option-testing',
        page: () => const StrategyBuilderPage(),
        transition: Transition.fade,
      ),

      // ── Sector ──
      // sector_pulse
      GetPage(
        name: '/sector-pulse',
        page: () => const SectorAnalysisPage(),
        transition: Transition.fade,
      ),

      // ── Practice trade ──
      // practice_trade -> already exists: '/virtual-trading'
      GetPage(
        name: '/virtual-trading',
        page: () => PreviousDayTrading(),
        transition: Transition.fade,
      ),

      // ── AI tools ──
      // ai_stock -> already exists: '/stocks' (search page; opens AI analysis per stock)
      // direct link to one stock's AI analysis
      GetPage(
        name: '/ai-stock/:symbol',
        page: () => StockAiAnalysisPage(symbol: Get.parameters['symbol'] ?? ''),
        transition: Transition.rightToLeft,
      ),
      // ai_index
      GetPage(
        name: '/ai-index',
        page: () => const NiftyAiSummaryPage(),
        transition: Transition.fade,
      ),

      // ── My tools ──
      // trade_journal
      GetPage(
        name: '/journal',
        page: () => const JournalAnalyticsPage(),
        transition: Transition.fade,
      ),
      // my_alerts -> already exists: '/alerts'

      // ── Performance ──
      // ai_picks_accuracy    -> already exists: '/backtest/ai-picks'
      // nifty_picks_accuracy -> already exists: '/backtest/nifty'
      // scanner_picks        -> already exists: '/backtest/screener'
      //Backtesting routes
      GetPage(
        name: '/backtest/nifty',
        page: () => NiftyDashboardShell(),
        transition: Transition.fade,
      ),
      GetPage(
        name: '/backtest/ai-picks',
        page: () => StockDashboardShell(),
        transition: Transition.fade,
      ),
      GetPage(
        name: '/backtest/screener',
        page: () => ScreenerHistoryPage(),
        transition: Transition.fade,
      ),

      // ── Get notified ──
      // alerts  (stock high/low breakouts). Not '/alerts/:stockName', that needs a name.
      GetPage(
        name: '/breakout-alerts',
        page: () => StockAlertsPage(null),
        transition: Transition.fade,
      ),

      // ── News ──
      // market_news
      GetPage(
        name: '/news',
        page: () => const NewsFeedPage(),
        transition: Transition.fade,
      ),

      // ── Deploy Algo ──
      // custom_algo -> already exists: '/deploy-algo'
      GetPage(name: '/deploy-algo', page: () => DeployedAlgosScreen()),
    ];
  }
}
