import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show DateFormat;

/// Plan model --------------------------------------------------------------
class _Plan {
  final String id;
  final String name;
  final int price;
  final String tagline;
  final IconData icon;
  final List<Color> colors;
  final List<_Feature> features;
  final String? badge;

  const _Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.tagline,
    required this.icon,
    required this.colors,
    required this.features,
    this.badge,
  });
}

class _Feature {
  final IconData icon;
  final String text;
  final bool highlight;
  const _Feature(this.icon, this.text, {this.highlight = false});
}

const _plans = <_Plan>[
  _Plan(
    id: 'pro',
    name: 'Pro',
    price: 800,
    tagline: 'Never miss a move',
    icon: Icons.workspace_premium_rounded,
    colors: [Color(0xFF109D58), Color(0xFF25D366)],
    badge: 'BEST VALUE',
    features: [
      _Feature(Icons.notifications_active_rounded,
          'Realtime notifications for ALL features',
          highlight: true),
      _Feature(Icons.bolt_rounded, 'Zero-delay alert delivery'),
      _Feature(Icons.tune_rounded, 'Customisable alert rules'),
      _Feature(Icons.support_agent_rounded, 'Priority support'),
      _Feature(Icons.rocket_launch_rounded, 'Early access to new features'),
    ],
  ),
  _Plan(
    id: 'max',
    name: 'Max',
    price: 1500,
    tagline: 'Run your own strategies',
    icon: Icons.diamond_rounded,
    colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
    features: [
      _Feature(Icons.memory_rounded, 'Custom algo deployment', highlight: true),
      _Feature(Icons.check_circle_rounded, 'Everything in Pro'),
      _Feature(Icons.notifications_active_rounded,
          'Realtime notifications for ALL features'),
      _Feature(Icons.engineering_rounded, 'Dedicated algo setup & tuning'),
      _Feature(Icons.workspace_premium_rounded, 'Highest priority support'),
    ],
  ),
];

/// Animated two-plan upgrade card -----------------------------------------
class _UpgradeCard extends StatefulWidget {
  /// Called after the user comes back from the subscription screen.
  final VoidCallback onReturn;
  const _UpgradeCard({super.key, required this.onReturn});

  @override
  State<_UpgradeCard> createState() => _UpgradeCardState();
}

class _UpgradeCardState extends State<_UpgradeCard>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _loop;
  int _selected = 1; // Max preselected (anchors higher price)

  _Plan get _plan => _plans[_selected];

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  Widget _stagger(double begin, double end, Widget child) {
    final curved = CurvedAnimation(
      parent: _enter,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  void _select(int i) {
    if (i == _selected) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = i);
  }

  Future<void> _checkout() async {
    HapticFeedback.mediumImpact();
    await Get.toNamed(
      '/subscription-razorpay',
      arguments: {'plan': _plan.id, 'price': _plan.price},
    );
    widget.onReturn();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF111418),
        border: Border.all(color: plan.colors.last.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: plan.colors.last.withOpacity(0.25),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stagger(0.0, 0.4, _header(plan)),
          const SizedBox(height: 16),
          _stagger(0.15, 0.55, _planSelector()),
          const SizedBox(height: 16),
          _stagger(0.3, 0.7, _featureList(plan)),
          const SizedBox(height: 18),
          _stagger(0.5, 1.0, _ctaButton(plan)),
          const SizedBox(height: 10),
          _stagger(
            0.6,
            1.0,
            Center(
              child: Text(
                'Secure payment via Razorpay  •  Cancel anytime',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Header ------------------------------------------------------------------
  Widget _header(_Plan plan) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _loop,
          builder: (_, child) {
            final pulse = (1 + _wave(_loop.value)) / 2; // 0..1
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: plan.colors),
                boxShadow: [
                  BoxShadow(
                    color: plan.colors.last.withOpacity(0.25 + 0.3 * pulse),
                    blurRadius: 10 + 12 * pulse,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(plan.icon,
                key: ValueKey(plan.id), color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upgrade your plan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  plan.tagline,
                  key: ValueKey(plan.tagline),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Plan selector -------------------------------------------------------------
  Widget _planSelector() {
    return Row(
      children: [
        for (var i = 0; i < _plans.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _planTile(i)),
        ],
      ],
    );
  }

  Widget _planTile(int i) {
    final p = _plans[i];
    final selected = i == _selected;

    return GestureDetector(
      onTap: () => _select(i),
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.96,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: selected
                    ? LinearGradient(
                        colors:
                            p.colors.map((c) => c.withOpacity(0.28)).toList(),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: selected ? null : Colors.white.withOpacity(0.04),
                border: Border.all(
                  color:
                      selected ? p.colors.last : Colors.white.withOpacity(0.10),
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(
                          color: Colors.white.withOpacity(selected ? 1 : 0.7),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (c, a) =>
                            ScaleTransition(scale: a, child: c),
                        child: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          key: ValueKey(selected),
                          size: 18,
                          color: selected
                              ? p.colors.last
                              : Colors.white.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${p.price}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(selected ? 1 : 0.75),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '/mo',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (p.badge != null)
              Positioned(
                top: -9,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: p.colors),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    p.badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Feature list ----------------------------------------------------------------
  Widget _featureList(_Plan plan) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [
            ...previous,
            if (current != null) current,
          ],
        ),
        child: Column(
          key: ValueKey(plan.id),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in plan.features) _featureRow(f, plan),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(_Feature f, _Plan plan) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: plan.colors.last.withOpacity(f.highlight ? 0.28 : 0.14),
            ),
            child: Icon(f.icon, size: 14, color: plan.colors.last),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              f.text,
              style: TextStyle(
                color: Colors.white.withOpacity(f.highlight ? 1 : 0.8),
                fontSize: 13,
                fontWeight: f.highlight ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // CTA ---------------------------------------------------------------------------
  Widget _ctaButton(_Plan plan) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: plan.colors),
        boxShadow: [
          BoxShadow(
            color: plan.colors.last.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withOpacity(0.2),
          onTap: _checkout,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                // Shimmer sweep
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _loop,
                    builder: (_, __) {
                      // Band center sweeps from left (-1.5) to right (1.5).
                      final dx = _loop.value * 3 - 1.5;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(dx - 1, 0),
                            end: Alignment(dx + 1, 0),
                            colors: [
                              Colors.white.withOpacity(0),
                              Colors.white.withOpacity(0.22),
                              Colors.white.withOpacity(0),
                            ],
                            stops: const [0.35, 0.5, 0.65],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Row(
                        key: ValueKey(plan.id),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Get ${plan.name} for ₹${plan.price}/mo',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedBuilder(
                            animation: _loop,
                            builder: (_, child) => Transform.translate(
                              offset:
                                  Offset(3 * (1 + _wave(_loop.value)) / 2, 0),
                              child: child,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
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

  /// Smooth -1..1 wave from a 0..1 loop value.
  double _wave(double t) =>
      Curves.easeInOut.transform(t < 0.5 ? t * 2 : (1 - t) * 2) * 2 - 1;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Public entry point: checks subscription, shows banner OR upgrade card
// ─────────────────────────────────────────────────────────────────────────────
class ProUpgradeButton extends StatefulWidget {
  const ProUpgradeButton({super.key});

  @override
  State<ProUpgradeButton> createState() => _ProUpgradeButtonState();
}

class _ProUpgradeButtonState extends State<ProUpgradeButton> {
  _SubStatus? _status;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _SubStatus.fetch();
    if (!mounted) return;
    setState(() {
      _status = s;
      _loaded = true;
    });
  }

  Future<void> _openSubscriptionScreen() async {
    await Get.toNamed('/subscription-razorpay');
    _load(); // refresh when the user comes back
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (!_loaded) {
      child = const SizedBox(key: ValueKey('loading'), width: double.infinity);
    } else if (_status?.isActive == true) {
      child = _ActivePlanBanner(
        key: const ValueKey('active'),
        status: _status!,
        onTap: _openSubscriptionScreen,
      );
    } else {
      child = _UpgradeCard(key: const ValueKey('upgrade'), onReturn: _load);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(a),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

/// Lightweight subscription status (same endpoint the subscription screen uses)
class _SubStatus {
  final String? planKey;
  final DateTime? expiresAt;
  const _SubStatus({this.planKey, this.expiresAt});

  bool get isActive =>
      planKey != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());

  String get displayName {
    final k = (planKey ?? '').toLowerCase();
    if (k.contains('max')) return 'Max';
    if (k.contains('pro')) return 'Pro';
    if (k.isEmpty) return 'Premium';
    final s = k.replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }

  List<Color> get colors => displayName == 'Max'
      ? const [Color(0xFF7C3AED), Color(0xFFEC4899)]
      : const [Color(0xFF109D58), Color(0xFF25D366)];

  /// Never throws: on any failure the user is treated as "not subscribed"
  /// and just sees the upgrade card (the subscription screen shows the truth).
  static Future<_SubStatus> fetch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const _SubStatus();
    try {
      final token = await user.getIdToken();
      final base = dotenv.env['RAZORPAY_API_URL']!;
      final resp = await http.get(
        Uri.parse('$base/payments/current-subscription'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return const _SubStatus();
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return _SubStatus(
        planKey: body['active_plan_key'] as String?,
        expiresAt: body['expires_at'] != null
            ? DateTime.tryParse(body['expires_at'] as String)
            : null,
      );
    } catch (_) {
      return const _SubStatus();
    }
  }
}

/// Slim banner shown when the user already has an active plan.
class _ActivePlanBanner extends StatelessWidget {
  final _SubStatus status;
  final VoidCallback onTap;
  const _ActivePlanBanner(
      {super.key, required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final expires = status.expiresAt!;
    final daysLeft = expires.difference(DateTime.now()).inDays;
    final soon = daysLeft <= 3;
    final subtitle = soon
        ? 'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'} • Tap to renew'
        : 'Renews ${DateFormat('MMM d, yyyy').format(expires)}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: status.colors),
        boxShadow: [
          BoxShadow(
            color: status.colors.last.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withOpacity(0.15),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${status.displayName} plan',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(soon ? 0.95 : 0.75),
                          fontSize: 12,
                          fontWeight: soon ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white60, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
