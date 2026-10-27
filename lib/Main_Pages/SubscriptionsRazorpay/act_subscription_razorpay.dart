// subscription_screen.dart
//
// Modern redesign: shimmer skeleton loading, staggered entrance animations,
// animated hero card with expiry progress, animated price count-up, press
// feedback on every tappable element. No extra packages required.
//
// Dependencies (already in your project):
//   supabase_flutter, url_launcher, firebase_auth, flutter_dotenv, http, intl
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show DateFormat;
import 'package:optionxi/Components/cust_contact_us.dart';
import 'package:optionxi/Main_Pages/SubscriptionsRazorpay/act_manage_subscription_screen.dart';
import 'package:optionxi/Main_Pages/SubscriptionsRazorpay/helper_razorpay.dart';
import 'package:optionxi/MobileLink/link_phone_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _Tokens {
  static const radius = 12.0;
  static const radiusLg = 18.0;
  static const radiusXl = 22.0;
  static const ease = Curves.easeOutCubic;
}

String get _kApiBase => dotenv.env['PHONELINK_URL']!;
String get _kRazorApiBase => dotenv.env['RAZORPAY_API_URL']!;

// ─────────────────────────────────────────────────────────────────────────────
//  Models
// ─────────────────────────────────────────────────────────────────────────────
class SubscriptionPlan {
  final String id;
  final String planKey;
  final String name;
  final String? tagline;
  final double price;
  final String currency;
  final String billingPeriod;
  final List<String> features;
  final String paymentLink;
  final bool isPopular;
  final int? screenerLimit;

  const SubscriptionPlan({
    required this.id,
    required this.planKey,
    required this.name,
    this.tagline,
    required this.price,
    required this.currency,
    required this.billingPeriod,
    required this.features,
    required this.paymentLink,
    required this.isPopular,
    this.screenerLimit,
  });

  factory SubscriptionPlan.fromMap(Map<String, dynamic> map) {
    return SubscriptionPlan(
      id: map['id'].toString(),
      planKey: map['plan_key'] as String? ?? '',
      name: map['name'] as String? ?? 'Plan',
      tagline: map['tagline'] as String?,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] as String? ?? 'INR',
      billingPeriod: map['billing_period'] as String? ?? 'month',
      features: ((map['features'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      paymentLink: map['payment_link'] as String? ?? '',
      isPopular: map['is_popular'] as bool? ?? false,
      screenerLimit: map['screener_limit'] as int?,
    );
  }

  String get currencySymbol => currency == 'INR' ? '₹' : currency;

  bool get _isWhole => price == price.roundToDouble();

  String formatValue(double v) =>
      _isWhole ? v.round().toString() : v.toStringAsFixed(2);

  String get formattedPrice => formatValue(price);

  /// Approximate length of one billing cycle in days (for the progress bar).
  int get periodDays {
    final p = billingPeriod.toLowerCase();
    if (p.contains('year') || p.contains('annual')) return 365;
    if (p.contains('quarter')) return 90;
    if (p.contains('week')) return 7;
    if (p.contains('day')) return 1;
    return 30;
  }
}

class WhatsAppStatus {
  final bool isVerified;
  final String? phone;
  const WhatsAppStatus({required this.isVerified, this.phone});
}

class ActiveSubscription {
  final String? planKey;
  final DateTime? expiresAt;
  const ActiveSubscription({this.planKey, this.expiresAt});

  bool get isActive =>
      planKey != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data services
// ─────────────────────────────────────────────────────────────────────────────
class SubscriptionApiException implements Exception {
  final String message;
  const SubscriptionApiException(this.message);
  @override
  String toString() => message;
}

class _PlansService {
  static Future<List<SubscriptionPlan>> fetchPlans() async {
    try {
      final rows = await Supabase.instance.client
          .from('subscription_plans')
          .select()
          .eq("is_enabled", true)
          .order('sort_order', ascending: true);
      return (rows as List)
          .map((row) => SubscriptionPlan.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const SubscriptionApiException(
          'Could not load subscription plans.');
    }
  }
}

class _WhatsAppStatusService {
  static Future<WhatsAppStatus> checkStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const SubscriptionApiException('You need to be signed in.');
    }
    try {
      final resp = await http
          .post(
            Uri.parse('$_kApiBase/otp/status'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'firebase_uid': user.uid}),
          )
          .timeout(const Duration(seconds: 15));
      final body = _parseBody(resp);
      if (resp.statusCode != 200) {
        throw SubscriptionApiException(
            body['detail'] as String? ?? 'Could not check WhatsApp status.');
      }
      return WhatsAppStatus(
        isVerified: body['is_verified'] as bool? ?? false,
        phone: body['phone'] as String?,
      );
    } on SubscriptionApiException {
      rethrow;
    } catch (_) {
      throw const SubscriptionApiException(
          'Could not reach the server. Check your connection.');
    }
  }

  static Map<String, dynamic> _parseBody(http.Response resp) {
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

class _SubscriptionStatusService {
  static Future<ActiveSubscription> fetchCurrent() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const SubscriptionApiException('You need to be signed in.');
    }
    try {
      final idToken = await user.getIdToken();
      final resp = await http.get(
        Uri.parse('$_kRazorApiBase/payments/current-subscription'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw const SubscriptionApiException(
            'Could not load your subscription.');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return ActiveSubscription(
        planKey: body['active_plan_key'] as String?,
        expiresAt: body['expires_at'] != null
            ? DateTime.tryParse(body['expires_at'] as String)
            : null,
      );
    } on SubscriptionApiException {
      rethrow;
    } catch (_) {
      throw const SubscriptionApiException('Could not reach the server.');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable animation primitives
// ─────────────────────────────────────────────────────────────────────────────

/// Fades + slides its child up after [delay] milliseconds.
class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int delay;
  final double dy;
  const _FadeSlideIn({required this.child, this.delay = 0, this.dy = 0.08});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 550));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: _Tokens.ease);
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: Offset(0, widget.dy), end: Offset.zero)
          .animate(CurvedAnimation(parent: _ctrl, curve: _Tokens.ease));

  @override
  void initState() {
    super.initState();
    if (widget.delay == 0) {
      _ctrl.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delay), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Scale-down press feedback + light haptic.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// One shared clock drives every skeleton bone, so the whole screen sweeps
/// in sync (no static pieces).
class _ShimmerScope extends StatefulWidget {
  final Widget child;
  const _ShimmerScope({required this.child});

  @override
  State<_ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<_ShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ShimmerClock(ctrl: _ctrl, child: widget.child);
}

class _ShimmerClock extends InheritedNotifier<AnimationController> {
  _ShimmerClock({required AnimationController ctrl, required super.child})
      : super(notifier: ctrl);

  static double of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<_ShimmerClock>();
    return w?.notifier?.value ?? 0;
  }
}

class _SlideGradient extends GradientTransform {
  final double slide;
  const _SlideGradient(this.slide);
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * slide, 0, 0);
}

/// Skeleton placeholder with its own animated highlight sweep.
class _Bone extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const _Bone({this.width, required this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    final t = _ShimmerClock.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF262633) : const Color(0xFFE4E6EE);
    final hi = isDark ? const Color(0xFF3A3A4D) : const Color(0xFFF5F6FA);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [base, hi, base],
          stops: const [0.2, 0.5, 0.8],
          transform: _SlideGradient(t * 3 - 1),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────
enum _LoadState { loading, error, ready }

class SubscriptionScreenRazorPay extends StatefulWidget {
  const SubscriptionScreenRazorPay({Key? key}) : super(key: key);

  @override
  State<SubscriptionScreenRazorPay> createState() =>
      _SubscriptionScreenRazorPayState();
}

class _SubscriptionScreenRazorPayState
    extends State<SubscriptionScreenRazorPay> {
  _LoadState _state = _LoadState.loading;
  String _errorMessage = '';

  List<SubscriptionPlan> _plans = [];
  bool _isVerified = false;
  String? _verifiedPhone;
  ActiveSubscription _activeSubscription = const ActiveSubscription();

  String? _launchingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [silent] keeps the current content on screen (pull-to-refresh).
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _state = _LoadState.loading;
        _errorMessage = '';
      });
    }
    try {
      final results = await Future.wait([
        _PlansService.fetchPlans(),
        _WhatsAppStatusService.checkStatus(),
        _SubscriptionStatusService.fetchCurrent(),
      ]);
      final plans = results[0] as List<SubscriptionPlan>;
      final status = results[1] as WhatsAppStatus;
      final activeSub = results[2] as ActiveSubscription;
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _isVerified = status.isVerified;
        _verifiedPhone = status.phone;
        _activeSubscription = activeSub;
        _state = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent) {
        _showSnack(e.toString(), isError: true);
        return;
      }
      setState(() {
        _errorMessage = e.toString();
        _state = _LoadState.error;
      });
    }
  }

  Future<void> _recheckVerification() async {
    try {
      final status = await _WhatsAppStatusService.checkStatus();
      if (!mounted) return;
      setState(() {
        _isVerified = status.isVerified;
        _verifiedPhone = status.phone;
      });
    } catch (_) {
      // Silently ignore — banner stays until next pull-to-refresh.
    }
  }

  Future<void> _goVerifyNumber() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LinkPhoneScreen()),
    );
    if (!mounted) return;
    _recheckVerification();
  }

  Future<void> _manageSubscription() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageSubscriptionScreen()),
    );
  }

  Future<void> _subscribe(SubscriptionPlan plan) async {
    if (!_isVerified) {
      _goVerifyNumber();
      return;
    }
    if (plan.paymentLink.isEmpty) {
      _showSnack('This plan isn\'t available for purchase right now.',
          isError: true);
      return;
    }
    setState(() => _launchingId = plan.id);
    try {
      // Create the payment link via helper_razorpay.dart
      var url = await createPaymentLink(
          phone: _verifiedPhone ?? '', planKey: plan.planKey);

      // Open in external browser, prefilling the contact number
      if (_verifiedPhone != null && _verifiedPhone!.isNotEmpty) {
        final sep = url.contains('?') ? '&' : '?';
        url =
            '$url${sep}prefill[contact]=${Uri.encodeComponent(_verifiedPhone!)}';
      }
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        _showSnack('Could not open the payment page.', isError: true);
      }
    } catch (_) {
      _showSnack('Could not open the payment page.', isError: true);
    } finally {
      if (mounted) setState(() => _launchingId = null);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_Tokens.radius)),
          backgroundColor:
              isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Subscription',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _buildBody(theme),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_state) {
      case _LoadState.loading:
        return _LoadingView(key: const ValueKey('loading'), theme: theme);
      case _LoadState.error:
        return _ErrorView(
          key: const ValueKey('error'),
          theme: theme,
          message: _errorMessage,
          onRetry: _load,
          onContactSupport: () => showContactOptions(context),
        );
      case _LoadState.ready:
        return RefreshIndicator(
          key: const ValueKey('ready'),
          onRefresh: () => _load(silent: true),
          child: _ReadyView(
            theme: theme,
            plans: _plans,
            isVerified: _isVerified,
            verifiedPhone: _verifiedPhone,
            activeSubscription: _activeSubscription,
            launchingId: _launchingId,
            onVerify: _goVerifyNumber,
            onSubscribe: _subscribe,
            onContactSupport: () => showContactOptions(context),
            onManageSubscription: _manageSubscription,
          ),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Loading state — fully animated skeleton that mirrors the real layout
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  final ThemeData theme;
  const _LoadingView({super.key, required this.theme});

  Widget _card({required bool popular}) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: isDark ? 0.35 : 0.5),
        borderRadius: BorderRadius.circular(_Tokens.radiusLg),
        border: Border.all(
          color: popular
              ? theme.colorScheme.primary.withValues(alpha: 0.35)
              : theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _Bone(width: 120, height: 20),
              const SizedBox(width: 10),
              if (popular) const _Bone(width: 88, height: 20, radius: 6),
            ],
          ),
          const SizedBox(height: 10),
          const _Bone(width: 170, height: 12),
          const SizedBox(height: 20),
          const _Bone(width: 130, height: 34),
          const SizedBox(height: 20),
          const _Bone(width: double.infinity, height: 1, radius: 1),
          const SizedBox(height: 16),
          for (int i = 0; i < 4; i++) ...[
            Row(
              children: [
                const _Bone(width: 28, height: 28, radius: 9),
                const SizedBox(width: 12),
                Expanded(
                  child:
                      _Bone(height: 13, width: i.isOdd ? 150 : double.infinity),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          const _Bone(
              width: double.infinity, height: 54, radius: _Tokens.radius),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerScope(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Bone(width: 210, height: 28),
            const SizedBox(height: 10),
            const _Bone(width: 150, height: 28),
            const SizedBox(height: 14),
            const _Bone(width: double.infinity, height: 13),
            const SizedBox(height: 8),
            const _Bone(width: 240, height: 13),
            const SizedBox(height: 14),
            const _Bone(width: 130, height: 30, radius: 20),
            const SizedBox(height: 26),
            _FadeSlideIn(delay: 0, child: _card(popular: false)),
            _FadeSlideIn(delay: 120, child: _card(popular: true)),
            const Center(child: _Bone(width: 190, height: 38, radius: 20)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Error state
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final ThemeData theme;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onContactSupport;

  const _ErrorView({
    super.key,
    required this.theme,
    required this.message,
    required this.onRetry,
    required this.onContactSupport,
  });

  @override
  Widget build(BuildContext context) {
    final err = theme.colorScheme.error;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 56),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutBack,
            builder: (_, v, child) =>
                Transform.scale(scale: v.clamp(0.0, 1.2), child: child),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  err.withValues(alpha: 0.22),
                  err.withValues(alpha: 0.04),
                ]),
              ),
              child: Center(
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: err.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.wifi_off_rounded, size: 36, color: err),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _FadeSlideIn(
            delay: 150,
            child: Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _FadeSlideIn(
            delay: 220,
            child: Text(
              message.isEmpty
                  ? 'We couldn\'t load subscription plans. Please try again.'
                  : message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 32),
          _FadeSlideIn(
            delay: 300,
            child: _Pressable(
              onTap: onRetry,
              child: Container(
                width: double.infinity,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(_Tokens.radius),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 19, color: theme.colorScheme.onPrimary),
                    const SizedBox(width: 8),
                    Text('Try Again',
                        style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _FadeSlideIn(
            delay: 380,
            child: _Pressable(
              onTap: onContactSupport,
              child: Container(
                width: double.infinity,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_Tokens.radius),
                  border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.headset_mic_rounded,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Contact Support',
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Ready state
// ─────────────────────────────────────────────────────────────────────────────
class _ReadyView extends StatelessWidget {
  final ThemeData theme;
  final List<SubscriptionPlan> plans;
  final bool isVerified;
  final String? verifiedPhone;
  final ActiveSubscription activeSubscription;
  final String? launchingId;
  final VoidCallback onVerify;
  final ValueChanged<SubscriptionPlan> onSubscribe;
  final VoidCallback onContactSupport;
  final VoidCallback onManageSubscription;

  const _ReadyView({
    required this.theme,
    required this.plans,
    required this.isVerified,
    required this.verifiedPhone,
    required this.activeSubscription,
    required this.launchingId,
    required this.onVerify,
    required this.onSubscribe,
    required this.onContactSupport,
    required this.onManageSubscription,
  });

  SubscriptionPlan? get _currentPlan {
    if (!activeSubscription.isActive) return null;
    for (final p in plans) {
      if (p.planKey == activeSubscription.planKey) return p;
    }
    return null;
  }

  void _openSwitchPlanSheet(BuildContext context, SubscriptionPlan plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SwitchPlanSheet(
        theme: theme,
        plan: plan,
        onContactSupport: () {
          Navigator.pop(sheetContext);
          onContactSupport();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentPlan;
    final hasActive = activeSubscription.isActive;
    final otherPlans = plans
        .where((p) => !hasActive || p.planKey != current?.planKey)
        .toList();

    int step = 0;
    int d() => 70 * step++;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        // ── Header ──
        _FadeSlideIn(
          delay: d(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasActive
                    ? 'Your subscription'
                    : 'Choose the plan\nthat fits you',
                style: TextStyle(
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasActive
                    ? 'You\'re all set. Manage your plan or explore other options below.'
                    : (isVerified
                        ? 'Your WhatsApp number is verified — pick a plan to get started.'
                        : 'Verify your WhatsApp number first, then pick a plan.'),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (isVerified &&
                  verifiedPhone != null &&
                  verifiedPhone!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _VerifiedChip(theme: theme, phone: verifiedPhone!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Active subscription hero ──
        if (hasActive && current != null) ...[
          _FadeSlideIn(
            delay: d(),
            child: _CurrentPlanHero(
              theme: theme,
              plan: current,
              expiresAt: activeSubscription.expiresAt!,
              onManage: onManageSubscription,
            ),
          ),
          const SizedBox(height: 28),
        ],

        if (!hasActive && !isVerified) ...[
          _FadeSlideIn(
            delay: d(),
            child: _VerifyBanner(theme: theme, onVerify: onVerify),
          ),
          const SizedBox(height: 20),
        ],

        // ── Other plans ──
        if (otherPlans.isNotEmpty) ...[
          if (hasActive) ...[
            _FadeSlideIn(
              delay: d(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 2),
                child: Text(
                  'OTHER PLANS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
            _FadeSlideIn(
              delay: d(),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(_Tokens.radiusLg),
                  border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < otherPlans.length; i++) ...[
                      _CompactPlanRow(
                        theme: theme,
                        plan: otherPlans[i],
                        onTap: () =>
                            _openSwitchPlanSheet(context, otherPlans[i]),
                      ),
                      if (i != otherPlans.length - 1)
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.1),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ] else
            ...otherPlans.map(
              (plan) => _FadeSlideIn(
                delay: d(),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _PlanCard(
                    theme: theme,
                    plan: plan,
                    isVerified: isVerified,
                    isLaunching: launchingId == plan.id,
                    onSubscribe: () => onSubscribe(plan),
                  ),
                ),
              ),
            ),
        ],

        const SizedBox(height: 8),
        _FadeSlideIn(
          delay: d(),
          child:
              _SupportFooter(theme: theme, onContactSupport: onContactSupport),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Verified chip
// ─────────────────────────────────────────────────────────────────────────────
class _VerifiedChip extends StatelessWidget {
  final ThemeData theme;
  final String phone;
  const _VerifiedChip({required this.theme, required this.phone});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF22C55E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: green.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded, size: 15, color: green),
          const SizedBox(width: 6),
          Text(
            phone,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Current plan hero
// ─────────────────────────────────────────────────────────────────────────────
class _CurrentPlanHero extends StatefulWidget {
  final ThemeData theme;
  final SubscriptionPlan plan;
  final DateTime expiresAt;
  final VoidCallback onManage;

  const _CurrentPlanHero({
    required this.theme,
    required this.plan,
    required this.expiresAt,
    required this.onManage,
  });

  @override
  State<_CurrentPlanHero> createState() => _CurrentPlanHeroState();
}

class _CurrentPlanHeroState extends State<_CurrentPlanHero> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final plan = widget.plan;
    final daysLeft = widget.expiresAt.difference(DateTime.now()).inDays;
    final isExpiringSoon = daysLeft <= 3;
    final formattedDate = DateFormat('MMM d, yyyy').format(widget.expiresAt);
    final primary = theme.colorScheme.primary;
    final progress = (daysLeft / plan.periodDays).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary,
            Color.lerp(primary, Colors.black, 0.4) ?? primary,
          ],
        ),
        borderRadius: BorderRadius.circular(_Tokens.radiusXl),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_Tokens.radiusXl),
        child: Stack(
          children: [
            // Subtle static accents
            Positioned(right: -36, top: -48, child: _orb(160, 0.08)),
            Positioned(left: -56, bottom: -80, child: _orb(180, 0.05)),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _PulsingDot(),
                            const SizedBox(width: 6),
                            const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.workspace_premium_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    plan.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (plan.tagline != null && plan.tagline!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      plan.tagline!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(
                        isExpiringSoon
                            ? Icons.error_outline_rounded
                            : Icons.event_repeat_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isExpiringSoon
                              ? (daysLeft <= 0
                                  ? 'Expires today'
                                  : 'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}')
                              : 'Renews on $formattedDate',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${daysLeft < 0 ? 0 : daysLeft}d left',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isExpiringSoon
                              ? const Color(0xFFFBBF24)
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Pressable(
                    onTap: widget.onManage,
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_Tokens.radius),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Manage Plan',
                            style: TextStyle(
                              color: primary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded,
                              size: 17, color: primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orb(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 14 * _c.value,
              height: 14 * _c.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.5 * (1 - _c.value)),
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Compact row for other plans
// ─────────────────────────────────────────────────────────────────────────────
class _CompactPlanRow extends StatelessWidget {
  final ThemeData theme;
  final SubscriptionPlan plan;
  final VoidCallback onTap;

  const _CompactPlanRow({
    required this.theme,
    required this.plan,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return _Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.workspace_premium_outlined,
                  size: 18, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          plan.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (plan.isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'POPULAR',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${plan.currencySymbol}${plan.formattedPrice} / ${plan.billingPeriod}',
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ],
              ),
            ),
            Text('Details',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: muted)),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Switch-plan bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class _SwitchPlanSheet extends StatelessWidget {
  final ThemeData theme;
  final SubscriptionPlan plan;
  final VoidCallback onContactSupport;

  const _SwitchPlanSheet({
    required this.theme,
    required this.plan,
    required this.onContactSupport,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(_Tokens.radiusXl),
            topRight: Radius.circular(_Tokens.radiusXl),
          ),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.12)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      plan.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '${plan.currencySymbol}${plan.formattedPrice}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3, left: 3),
                    child: Text('/ ${plan.billingPeriod}',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ],
              ),
              if (plan.tagline != null && plan.tagline!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(plan.tagline!,
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 18),
              for (int i = 0; i < plan.features.length; i++)
                _FadeSlideIn(
                  delay: 60 + i * 45,
                  dy: 0.15,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check_rounded,
                              size: 13, color: theme.colorScheme.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            plan.features[i],
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(_Tokens.radius),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 17, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Plan changes are handled by our support team so any billing adjustment is done correctly.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Pressable(
                onTap: onContactSupport,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(_Tokens.radius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.headset_mic_rounded,
                          size: 18, color: theme.colorScheme.onPrimary),
                      const SizedBox(width: 8),
                      Text(
                        'Contact Support to Switch',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Verify banner
// ─────────────────────────────────────────────────────────────────────────────
class _VerifyBanner extends StatefulWidget {
  final ThemeData theme;
  final VoidCallback onVerify;
  const _VerifyBanner({required this.theme, required this.onVerify});

  @override
  State<_VerifyBanner> createState() => _VerifyBannerState();
}

class _VerifyBannerState extends State<_VerifyBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final amber = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            amber.withValues(alpha: 0.10),
            amber.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(_Tokens.radiusLg),
        border: Border.all(color: amber.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: amber.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: amber.withValues(alpha: 0.16 * _pulse.value),
                    blurRadius: 3 + 8 * _pulse.value,
                    spreadRadius: 1 * _pulse.value,
                  ),
                ],
              ),
              child: child,
            ),
            child: Icon(Icons.chat_rounded, color: amber, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verify your WhatsApp number',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'We use this number to link your payment to your account and to send plan alerts.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                _Pressable(
                  onTap: widget.onVerify,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: amber,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Verify Now',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700)),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded,
                            size: 16, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Full plan card — first-time purchase
// ─────────────────────────────────────────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  final ThemeData theme;
  final SubscriptionPlan plan;
  final bool isVerified;
  final bool isLaunching;
  final VoidCallback onSubscribe;

  const _PlanCard({
    required this.theme,
    required this.plan,
    required this.isVerified,
    required this.isLaunching,
    required this.onSubscribe,
  });

  IconData _iconFor(String feature) {
    final f = feature.toLowerCase();
    if (f.contains('whatsapp')) return Icons.chat_rounded;
    if (f.contains('algo')) return Icons.smart_toy_rounded;
    if (f.contains('market depth')) return Icons.layers_rounded;
    if (f.contains('research')) return Icons.analytics_rounded;
    if (f.contains('stock pick')) return Icons.trending_up_rounded;
    if (f.contains('news')) return Icons.article_rounded;
    if (f.contains('screener')) return Icons.filter_alt_rounded;
    if (f.contains('sentiment')) return Icons.insights_rounded;
    return Icons.check_circle_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final accent =
        plan.isPopular ? primary : theme.colorScheme.onSurfaceVariant;

    final inner = Container(
      decoration: BoxDecoration(
        color: plan.isPopular
            ? Color.alphaBlend(primary.withValues(alpha: isDark ? 0.10 : 0.05),
                theme.colorScheme.surface)
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: isDark ? 0.35 : 0.5),
        borderRadius: BorderRadius.circular(
            plan.isPopular ? _Tokens.radiusLg - 1.5 : _Tokens.radiusLg),
        border: plan.isPopular
            ? null
            : Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  plan.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (plan.isPopular) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 12, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'MOST POPULAR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (plan.tagline != null && plan.tagline!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              plan.tagline!,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Animated price count-up
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: plan.price),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    plan.currencySymbol,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  plan.formatValue(v),
                  style: TextStyle(
                    fontSize: 36,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: -1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 5),
                  child: Text(
                    '/ ${plan.billingPeriod}',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 14),
          for (int i = 0; i < plan.features.length; i++)
            _FadeSlideIn(
              delay: 250 + i * 55,
              dy: 0.2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(_iconFor(plan.features[i]),
                          size: 15, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          plan.features[i],
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          _SubscribeButton(
            theme: theme,
            isPopular: plan.isPopular,
            isVerified: isVerified,
            isLaunching: isLaunching,
            onTap: onSubscribe,
          ),
        ],
      ),
    );

    if (!plan.isPopular) return inner;

    // Popular: gradient border + soft glow
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(_Tokens.radiusLg),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: inner,
    );
  }
}

class _SubscribeButton extends StatelessWidget {
  final ThemeData theme;
  final bool isPopular;
  final bool isVerified;
  final bool isLaunching;
  final VoidCallback onTap;

  const _SubscribeButton({
    required this.theme,
    required this.isPopular,
    required this.isVerified,
    required this.isLaunching,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final bg = isPopular
        ? primary
        : (isDark
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.onSurface);
    final fg = isPopular
        ? theme.colorScheme.onPrimary
        : (isDark ? theme.colorScheme.onSurface : theme.colorScheme.surface);

    final label = isLaunching
        ? 'Opening…'
        : (isVerified ? 'Subscribe Now' : 'Verify to Subscribe');

    return _Pressable(
      onTap: isLaunching ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isLaunching ? bg.withValues(alpha: 0.75) : bg,
          borderRadius: BorderRadius.circular(_Tokens.radius),
          boxShadow: isPopular
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: anim, child: child),
          ),
          child: Row(
            key: ValueKey(label),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLaunching)
                SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                )
              else
                Icon(
                  isVerified
                      ? Icons.arrow_forward_rounded
                      : Icons.lock_outline_rounded,
                  size: 18,
                  color: fg,
                ),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Support footer
// ─────────────────────────────────────────────────────────────────────────────
class _SupportFooter extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onContactSupport;
  const _SupportFooter({required this.theme, required this.onContactSupport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _Pressable(
        onTap: onContactSupport,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.headset_mic_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Have a doubt? Contact Support',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
