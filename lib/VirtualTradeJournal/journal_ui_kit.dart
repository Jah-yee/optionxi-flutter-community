import 'dart:ui' show FontFeature;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:optionxi/Helpers/constants.dart';

// ═════════════════════════════════════════════════════════════════════════
//  Shared look & feel for the Journal screens + their bottom sheets.
// ═════════════════════════════════════════════════════════════════════════

/// Design tokens. Colours resolve from the current theme brightness.
class JT {
  JT._();

  // Semantic colours
  static const profit = Color(0xFF16A34A);
  static const profitBright = Color(0xFF22C55E);
  static const loss = Color(0xFFDC2626);
  static const lossBright = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const blue = Color(0xFF3B82F6);

  static bool isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color bg(BuildContext c) =>
      isDark(c) ? const Color(0xFF080B12) : const Color(0xFFF5F7FA);
  static Color surface(BuildContext c) =>
      isDark(c) ? const Color(0xFF111827) : Colors.white;
  static Color surface2(BuildContext c) =>
      isDark(c) ? const Color(0xFF1A2030) : const Color(0xFFF8FAFC);
  static Color border(BuildContext c) =>
      isDark(c) ? const Color(0xFF1E2A3B) : const Color(0xFFE8ECF0);
  static Color text(BuildContext c) =>
      isDark(c) ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
  static Color text2(BuildContext c) =>
      isDark(c) ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color text3(BuildContext c) =>
      isDark(c) ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

  /// Green / red / grey text colour for a profit-or-loss number.
  static Color pnl(double v) =>
      v > 0 ? profit : (v < 0 ? loss : const Color(0xFF64748B));

  /// Soft tinted background for a colour (works in light + dark).
  static Color tint(BuildContext c, Color color, [double light = 0.10]) =>
      color.withOpacity(isDark(c) ? light + 0.06 : light);

  // Typography
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle caption(BuildContext c, {double size = 12, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color ?? text2(c),
        height: 1.3,
      );

  static TextStyle body(BuildContext c,
          {double size = 14, FontWeight? weight, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? text(c),
        height: 1.4,
      );

  static TextStyle heading(BuildContext c,
          {double size = 16, FontWeight? weight, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w700,
        color: color ?? text(c),
        letterSpacing: -0.2,
      );

  /// Numbers: bold, tabular so digits don't jiggle while they animate.
  static TextStyle number(BuildContext c,
          {double size = 16, FontWeight? weight, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w700,
        color: color ?? text(c),
        letterSpacing: -0.3,
        fontFeatures: _tabular,
      );

  static BoxDecoration card(BuildContext c,
          {Color? borderColor, double radius = 18}) =>
      BoxDecoration(
        color: surface(c),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? border(c), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark(c) ? 0.22 : 0.045),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      );
}

// ─────────────────────────────────────────────
//  Formatting helpers
// ─────────────────────────────────────────────

final NumberFormat _inr =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Exact price: ₹1,234.50
String jtPrice(double v) => _inr.format(v);

/// Compact money: ₹12.50K, +₹1.20M (sign only when [signed]).
String jtMoney(double v, {bool signed = false}) {
  if (v.abs() < 0.005) v = 0;
  final abs = v.abs();
  String body;
  if (abs >= 10000000) {
    body = '${(abs / 10000000).toStringAsFixed(2)} Cr';
  } else if (abs >= 100000) {
    body = '${(abs / 100000).toStringAsFixed(2)} L';
  } else if (abs >= 1000) {
    body = '${(abs / 1000).toStringAsFixed(2)}K';
  } else {
    body = abs.toStringAsFixed(2);
  }
  final sign = v > 0 ? (signed ? '+' : '') : (v < 0 ? '-' : '');
  return '$sign₹$body';
}

String jtPercent(double v, {bool signed = true}) {
  if (v.isNaN || v.isInfinite) return '—';
  if (v.abs() < 0.005) v = 0;
  return '${signed && v > 0 ? '+' : ''}${v.toStringAsFixed(2)}%';
}

/// "NSE:TCS-EQ" -> "TCS". (Same rule the logo files are named by.)
String jtLogoKey(String s) {
  try {
    if (s.contains(':')) s = s.split(':')[1];
    if (s.contains('-')) s = s.split('-')[0];
    return s;
  } catch (_) {
    return s;
  }
}

/// Name shown to people. Keeps hyphenated names (BAJAJ-AUTO) intact and
/// shows index contracts as "NIFTY 22DEC22".
String jtDisplaySymbol(String s) {
  try {
    var core = s.contains(':') ? s.split(':').last : s;
    core = core.replaceAll(RegExp(r'-(EQ|BE|BZ|SM|ST|N1|IL|GB|GS)$'), '');
    final upper = core.toUpperCase();
    if ((upper.startsWith('BANKNIFTY-') || upper.startsWith('NIFTY-')) &&
        core.contains('-')) {
      final i = core.indexOf('-');
      return '${core.substring(0, i)} ${core.substring(i + 1)}';
    }
    return core;
  } catch (_) {
    return s;
  }
}

/// "3 days", "5 hours", "12 min" between two moments.
String jtDuration(DateTime from, DateTime to) {
  final d = to.difference(from).abs();
  if (d.inDays >= 2) return '${d.inDays} days';
  if (d.inDays == 1) return '1 day';
  if (d.inHours >= 1) return '${d.inHours} hr';
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return 'under a minute';
}

// ─────────────────────────────────────────────
//  Small animated building blocks
// ─────────────────────────────────────────────

/// Card/button wrapper that gently shrinks while pressed.
class JtPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptic;
  const JtPressable({
    Key? key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.98,
    this.haptic = false,
  }) : super(key: key);

  @override
  State<JtPressable> createState() => _JtPressableState();
}

class _JtPressableState extends State<JtPressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Number that counts up on first show and glides to new values.
class JtCount extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle style;
  final Duration duration;
  const JtCount({
    Key? key,
    required this.value,
    required this.format,
    required this.style,
    this.duration = const Duration(milliseconds: 700),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text(format(v), style: style),
      );
}

/// Pulsing grey placeholder used while loading.
class JtSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const JtSkeleton({Key? key, this.width, this.height = 14, this.radius = 8})
      : super(key: key);

  @override
  State<JtSkeleton> createState() => _JtSkeletonState();
}

class _JtSkeletonState extends State<JtSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base =
        JT.isDark(context) ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
    final light =
        JT.isDark(context) ? const Color(0xFF2B3647) : const Color(0xFFF1F5F9);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(base, light, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Stock logo with a friendly letter fallback.
class JtLogo extends StatelessWidget {
  final String symbolKey; // e.g. "TCS"
  final Color accent;
  final double size;
  const JtLogo({
    Key? key,
    required this.symbolKey,
    required this.accent,
    this.size = 44,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: JT.tint(context, accent, 0.12),
      alignment: Alignment.center,
      child: Text(
        symbolKey.isEmpty ? '?' : symbolKey[0].toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: accent.withOpacity(0.25), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: CachedNetworkImage(
          imageUrl: '${Constants.OptionXiS3Loc}$symbolKey.png',
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (_, __) => fallback,
          errorWidget: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

/// "Bought" / "Sold first" tag. Tapping explains it in plain words.
class JtDirectionChip extends StatelessWidget {
  final bool isShort;
  const JtDirectionChip({Key? key, required this.isShort}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = isShort ? JT.amber : JT.profit;
    return JtPressable(
      onTap: () => showJtHelp(
        context,
        title: isShort ? 'Sold first (short)' : 'Bought',
        body: isShort
            ? 'You sold shares you don\'t own yet, planning to buy them back '
                'later at a lower price. You make money when the price '
                'falls, and lose money when it rises.'
            : 'You bought shares and plan to sell them later. You make money '
                'when the price rises, and lose money when it falls.',
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: JT.tint(context, color, 0.12),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isShort ? Icons.south_east_rounded : Icons.north_east_rounded,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              isShort ? 'Sold first' : 'Bought',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded "+3.4%" tag.
class JtPctTag extends StatelessWidget {
  final double pct;
  const JtPctTag({Key? key, required this.pct}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = JT.pnl(pct);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: JT.tint(context, color, 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        jtPercent(pct),
        style: JT.number(context, size: 12, color: color),
      ),
    );
  }
}

/// Compact button used on cards and sheets.
class JtButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;
  final Color? color;
  final bool expand;
  final bool loading;
  final double height;
  const JtButton({
    Key? key,
    required this.label,
    this.icon,
    this.onTap,
    this.filled = false,
    this.color,
    this.expand = false,
    this.loading = false,
    this.height = 38,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = color ?? JT.blue;
    final enabled = onTap != null && !loading;
    final fg = filled ? Colors.white : c;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
        else ...[
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ],
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled || loading ? 1 : 0.5,
      child: JtPressable(
        onTap: enabled ? onTap : null,
        pressedScale: 0.96,
        haptic: true,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: filled ? c : JT.tint(context, c, 0.10),
            borderRadius: BorderRadius.circular(height * 0.32),
            border: filled
                ? null
                : Border.all(color: c.withOpacity(0.22), width: 1),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Section title with optional explainer.
class JtSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final int? count;
  const JtSectionTitle({
    Key? key,
    required this.title,
    required this.icon,
    required this.color,
    this.subtitle,
    this.count,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: JT.tint(context, color, 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: JT.heading(context, size: 15)),
                    if (count != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                          color: JT.surface2(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: JT.border(context)),
                        ),
                        child: Text('$count',
                            style: JT.number(context,
                                size: 11, color: JT.text2(context))),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null)
                  Text(subtitle!, style: JT.caption(context, size: 11)),
              ],
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────
//  Bottom sheets
// ─────────────────────────────────────────────

/// Opens a bottom sheet with the app's standard behaviour.
Future<T?> showJtSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: builder,
    );

/// Shared sheet shell: drag handle, title, scrolling body, sticky footer, and
/// it lifts above the keyboard (the old exit sheet got hidden behind it).
class JtSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final Widget? footer;
  const JtSheet({
    Key? key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.footer,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
        child: Container(
          decoration: BoxDecoration(
            color: JT.bg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border:
                Border(top: BorderSide(color: JT.border(context), width: 1)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: JT.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: JT.heading(context, size: 20)),
                            if (subtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(subtitle!,
                                  style: JT.caption(context, size: 13)),
                            ],
                          ],
                        ),
                      ),
                      if (trailing != null) trailing!,
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon:
                            Icon(Icons.close_rounded, color: JT.text2(context)),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    physics: const BouncingScrollPhysics(),
                    child: child,
                  ),
                ),
                if (footer != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                    decoration: BoxDecoration(
                      color: JT.surface(context),
                      border: Border(
                          top: BorderSide(color: JT.border(context), width: 1)),
                    ),
                    child: footer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny "what does this mean?" sheet.
Future<void> showJtHelp(BuildContext context,
    {required String title, required String body}) {
  HapticFeedback.selectionClick();
  return showJtSheet<void>(
    context,
    (ctx) => JtSheet(
      title: title,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(body, style: JT.body(ctx, size: 15)),
      ),
    ),
  );
}
