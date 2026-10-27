// ─────────────────────────────────────────────
// PREMIUM DIALOG
// ─────────────────────────────────────────────

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ═══════════════════════════════════════════════════════════════
//  THEME — fresh, modern palette
//  Electric blue → sky gradient, clean green/red for gains/losses.
// ═══════════════════════════════════════════════════════════════

class _T {
  // Brand
  static const accent = Color(0xFF2563EB); // electric blue
  static const accent2 = Color(0xFF38BDF8); // sky
  static const gold = Color(0xFFFFB020);
  static const green = Color(0xFF16A34A); // clean gain green
  static const red = Color(0xFFDC2626); // clean loss red

  static LinearGradient get brandGradient =>
      const LinearGradient(colors: [accent, accent2]);

  // Surfaces
  static Color bg(bool d) =>
      d ? const Color(0xFF0B0C12) : const Color(0xFFF3F4FB);
  static Color surface(bool d) => d ? const Color(0xFF151724) : Colors.white;
  static Color surface2(bool d) =>
      d ? const Color(0xFF1D1F31) : const Color(0xFFF0F1F9);
  static Color border(bool d) =>
      d ? const Color(0xFF282B45) : const Color(0xFFE6E8F4);
  static Color text(bool d) =>
      d ? const Color(0xFFF2F3FF) : const Color(0xFF11132A);
  static Color sub(bool d) =>
      d ? const Color(0xFF7E86A8) : const Color(0xFF707899);

  // Dark chip background used by snackbars / skeletons
  static const darkChip = Color(0xFF1B2138);
}

class PremiumDialogCust extends StatelessWidget {
  const PremiumDialogCust();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: _T.surface(dark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFFB347), Color(0xFFE65100)]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFFE65100).withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: 16),
              Text('Upgrade to Premium',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _T.text(dark))),
              const SizedBox(height: 6),
              Text(
                'Free plan allows 10 saved scanners.\nUpgrade to save up to 50.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: _T.sub(dark), height: 1.5),
              ),
              const SizedBox(height: 22),
              _PlanCard(
                dark: dark,
                title: 'Basic',
                price: '₹800',
                period: '/month',
                color: _T.accent,
                features: const [
                  '10 → 50 saved scanners',
                  'All screener features',
                  'Priority support',
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFFB347), Color(0xFFE65100)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFFE65100).withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);

                      Get.toNamed("/subscription-razorpay");
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('View Plans & Subscribe',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Maybe later',
                    style: TextStyle(color: _T.sub(dark), fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final bool dark;
  final String title, price, period;
  final Color color;
  final List<String> features;
  final bool isRecommended = false;

  const _PlanCard({
    required this.dark,
    required this.title,
    required this.price,
    required this.period,
    required this.color,
    required this.features,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRecommended ? color.withOpacity(0.06) : _T.surface2(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRecommended ? color : _T.border(dark),
          width: isRecommended ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: _T.text(dark))),
          if (isRecommended) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(6)),
              child: const Text('BEST VALUE',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
            ),
          ],
          const Spacer(),
          RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: price,
                  style: TextStyle(
                      color: color, fontSize: 20, fontWeight: FontWeight.w800)),
              TextSpan(
                  text: period,
                  style: TextStyle(
                      color: _T.sub(dark),
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: color, size: 14),
                const SizedBox(width: 6),
                Text(f,
                    style: TextStyle(
                        fontSize: 12,
                        color: _T.text(dark),
                        fontWeight: FontWeight.w500)),
              ]),
            )),
      ]),
    );
  }
}
