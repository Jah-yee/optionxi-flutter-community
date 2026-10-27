import 'dart:io';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:optionxi/Components/cust_ai_chooser_component.dart';
import 'package:optionxi/Components/cust_nav_bar.dart';
import 'package:optionxi/Dialogs/custom_dialog.dart';
import 'package:optionxi/Helpers/open_url.dart';
import 'package:optionxi/Helpers/update_helper.dart';
import 'package:optionxi/Main_Frags/frag_home.dart';
import 'package:optionxi/Main_Frags/frag_profile.dart';
import 'package:optionxi/Main_Frags/frag_live.dart';
import 'package:optionxi/Main_Frags/frag_search.dart';
import 'package:optionxi/Main_Frags/frag_tools_v3.dart';
import 'package:optionxi/Main_Pages/AIPages/act_ai_optionxi.dart';
import 'package:optionxi/Main_Pages/AISummary/act_stock_ai_summary.dart';
import 'package:optionxi/Main_Pages/Search/act_search_stocks_meili.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tool id → route map. Kept here so the Tools tab can open every page with
// a single lookup. Routes themselves are registered in main.dart.
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, String> kToolRoutes = {
  // Find stocks
  'top_picks': '/top-picks',
  'screeners': '/screeners',
  'top_movers': '/top-movers',
  'custom_screeners': '/screenerpro',
  // Options
  'option_chain': '/option-chain',
  'option_budget': '/option-budget',
  'option_oi': '/option-oi',
  // Index
  'index_breakout': '/index-breakout',
  'bollinger_alerts': '/bollinger-breakouts',
  // Backtest
  'strategy_backtest': '/saved-backtest',
  'option_testing': '/option-testing',
  // Sector
  'sector_pulse': '/sector-pulse',
  // Practice trade
  'practice_trade': '/virtual-trading',
  // AI tools
  'ai_stock': '/ai-stock',
  'ai_index': '/ai-index',
  // My tools
  'trade_journal': '/journal',
  'my_alerts': '/alerts',
  // Performance
  'ai_picks_accuracy': '/backtest/ai-picks',
  'nifty_picks_accuracy': '/backtest/nifty',
  'scanner_picks': '/backtest/screener',
  // Get notified
  'alerts': '/breakout-alerts',
  // News
  'market_news': '/news',
  // Deploy Algo
  'custom_algo': '/deploy-algo',
};

class Homepage extends StatefulWidget {
  const Homepage({
    Key? key,
  }) : super(key: key);

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  bool compulsory = false;
  String androidurl =
      "https://play.google.com/store/apps/details?id=com.optionxi.app";
  String iosurl = "https://apps.apple.com/in/app/optionxi/id6447514602";

  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // currentIndex = widget.initialIndex;
    fetchRemoteConfig();

    // // ✅ Handle notification tap when app was killed or in background
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   NotificationServiceFirebase().handlePendingNavigation();
    // });
  }

  void onTap(int index) {
    setState(() => currentIndex = index);
  }

  Widget getPage(int index) {
    switch (index) {
      case 0:
        return TradingHomeScreen();
      case 1:
        return AllSearchPageMeili(embedded: true);
      case 2:
        return WatchlistFragmentMain();
      case 3:
        return ToolsSection(
          onToolSelected: (tool) {
            // Bottom sheets, not routes
            if (tool.id == 'ai_stock') {
              showAIActionSheet(
                context,
                startOnSearch:
                    true, // skip the "Chat / Analyse" step, go to search
                onChat: () => Get.to(() => ChatScreen()),
                onAnalyse: (symbol) =>
                    Get.to(() => StockAiAnalysisPage(symbol: symbol)),
              );
              return;
            }

            final route = kToolRoutes[tool.id];
            if (route != null) Get.toNamed(route);
          },
        );
      case 4:
        return TradingProfilePage();
      default:
        return TradingHomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: 400.ms,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: getPage(currentIndex),
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: currentIndex,
        onTap: onTap,
      ),
    );
  }

  Future<void> fetchRemoteConfig() async {
    final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig.instance;

    try {
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(seconds: 120),
        ),
      );
      await remoteConfig.activate();
      await remoteConfig.fetch();

      iosurl = remoteConfig.getString('ioslink');
      androidurl = remoteConfig.getString('androidlink');
      String message = remoteConfig.getString('Message');
      int latestVersion = remoteConfig.getInt('latest_version');
      int minVersion = remoteConfig.getInt('min_version');
      int buildNumber = await getBuildNumber();

      if (buildNumber < minVersion) compulsory = true;
      if (buildNumber < latestVersion) {
        DialogUtils().showCustomDialogUpdate(
          context: context,
          title: "Update Available",
          description: message,
          confirmButtonText: "Update",
          cancelButtonText: "Cancel",
          onConfirm: updateFunction,
          onCancel: cancelFunction,
          isDismissible: compulsory,
        );
      }
    } catch (e) {
      debugPrint('Error fetching remote config: $e');
    }
  }

  void updateFunction() {
    OpenHelper.open_url(Platform.isIOS ? iosurl : androidurl);
  }

  void cancelFunction() {
    if (!compulsory) Navigator.pop(context);
  }
}
