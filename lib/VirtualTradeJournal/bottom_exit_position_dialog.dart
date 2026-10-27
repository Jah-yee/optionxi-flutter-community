import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:optionxi/PushNotification/notifcation_service.dart';
import 'package:optionxi/VirtualTradeJournal/edit_basket_page.dart';
import 'package:optionxi/VirtualTradeJournal/journal_ui_kit.dart';
import 'package:optionxi/VirtualTrading/VDataModel/v_holdings_journal.dart';

/// Opens the "Close this trade" sheet. Resolves to `true` if a close request
/// was sent.
Future<bool?> showExitPositionDialog(
  BuildContext context,
  BasketUserHolding userholding,
  double currentLtp,
  bool isshort,
) =>
    showJtSheet<bool>(
      context,
      (_) => ExitPositionDialog(
        userholding: userholding,
        currentLtp: currentLtp,
        isshort: isshort,
      ),
    );

/// "Close this trade" sheet.
///
/// Plain-language flow: how many shares → at what price → when → see what
/// you'd make → confirm. The data written to Firebase is unchanged
/// (`virtualbasket_toexit/{uid}/{orderId}`).
class ExitPositionDialog extends StatefulWidget {
  final BasketUserHolding userholding;
  final double currentLtp;
  final bool isshort;

  const ExitPositionDialog({
    Key? key,
    required this.userholding,
    required this.currentLtp,
    required this.isshort,
  }) : super(key: key);

  @override
  State<ExitPositionDialog> createState() => _ExitPositionDialogState();
}

class _ExitPositionDialogState extends State<ExitPositionDialog> {
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  bool _useNow = true;
  DateTime _picked = DateTime.now();
  bool _submitting = false;
  String? _error;

  BasketUserHolding get _h => widget.userholding;
  bool get _hasLivePrice => widget.currentLtp > 0;

  int get _qty => int.tryParse(_qtyCtrl.text) ?? 0;
  double? get _price {
    final v = double.tryParse(_priceCtrl.text.replaceAll(',', ''));
    return (v == null || v <= 0) ? null : v;
  }

  bool get _qtyOk => _qty > 0 && _qty <= _h.quantity;

  @override
  void initState() {
    super.initState();
    _qtyCtrl.text = _h.quantity.toString();
    if (_hasLivePrice) _priceCtrl.text = widget.currentLtp.toStringAsFixed(2);
    _qtyCtrl.addListener(_refresh);
    _priceCtrl.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────

  void _setQty(int q) {
    final v = q.clamp(1, _h.quantity);
    _qtyCtrl.text = v.toString();
    _qtyCtrl.selection = TextSelection.collapsed(offset: _qtyCtrl.text.length);
    HapticFeedback.selectionClick();
  }

  Future<void> _editTrade() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditBasketPage(basket: _h)),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final entry =
        DateTime(_h.entryDate.year, _h.entryDate.month, _h.entryDate.day);
    final now = DateTime.now();
    final first = entry.isAfter(now) ? now : entry;
    final initial = _picked.isBefore(first)
        ? first
        : (_picked.isAfter(now) ? now : _picked);
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: now,
    );
    if (d != null && mounted) {
      setState(() {
        _picked =
            DateTime(d.year, d.month, d.day, _picked.hour, _picked.minute);
        _error = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_picked),
    );
    if (t != null && mounted) {
      setState(() {
        _picked = DateTime(
            _picked.year, _picked.month, _picked.day, t.hour, t.minute);
        _error = null;
      });
    }
  }

  String? _validate(DateTime when) {
    if (!_qtyOk) {
      return 'Enter a number of shares between 1 and ${_h.quantity}.';
    }
    if (_price == null) return 'Enter the price you closed at.';
    if (when.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return 'That time is in the future. Pick a time that has already passed.';
    }
    // Compare calendar days only, so a same-day close is never blocked by a
    // time-of-day mismatch.
    final whenDay = DateTime(when.year, when.month, when.day);
    final entryDay =
        DateTime(_h.entryDate.year, _h.entryDate.month, _h.entryDate.day);
    if (whenDay.isBefore(entryDay)) {
      return 'You can\'t close a trade before the day it was opened '
          '(${DateFormat('d MMM yyyy').format(_h.entryDate)}).';
    }
    return null;
  }

  Future<void> _submit() async {
    final when = _useNow ? DateTime.now() : _picked;
    final problem = _validate(when);
    if (problem != null) {
      HapticFeedback.mediumImpact();
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final exitPrice = _price!;
      final exitQuantity = _qty;
      final stockName = _h.symbol;

      final DatabaseReference database = FirebaseDatabase.instance.ref();
      final String orderId =
          database.child('virtualbasket_toexit').child(user.uid).push().key ??
              DateTime.now().millisecondsSinceEpoch.toString();

      await database
          .child('virtualbasket_toexit')
          .child(user.uid)
          .child(orderId)
          .set({
        'symbol': stockName,
        'exit_price': exitPrice,
        'exit_quantity': exitQuantity,
        'exit_datetime': when.toIso8601String(),
        'created_at': ServerValue.timestamp,
        'isshort': widget.isshort,
      });

      if (!mounted) return;
      HapticFeedback.mediumImpact();

      final name = jtDisplaySymbol(stockName);
      final message =
          'Done! Closing your $name trade ($exitQuantity ${exitQuantity == 1 ? 'share' : 'shares'}). '
          'It will appear under Closed trades shortly.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: JT.profit,
          duration: const Duration(milliseconds: 2800),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

      NotificationService().showNotificationBasic(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: 'Closing your trade',
        body: '$name — $exitQuantity '
            '${exitQuantity == 1 ? 'share' : 'shares'} close request sent.',
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Exit position error: $e');
      if (mounted) {
        setState(() {
          _error = 'We couldn\'t send your request. Please check your '
              'internet connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isShort = widget.isshort;
    final name = jtDisplaySymbol(_h.symbol);
    final qtyLabel = _qtyOk
        ? '${isShort ? 'Buy back' : 'Sell'} $_qty ${_qty == 1 ? 'share' : 'shares'}'
        : 'Close trade';

    return JtSheet(
      title: 'Close this trade',
      subtitle: isShort
          ? 'You\'ll buy back the shares you sold earlier.'
          : 'You\'ll sell the shares you bought earlier.',
      trailing: JtButton(
        label: 'Edit',
        icon: Icons.edit_outlined,
        height: 32,
        onTap: _submitting ? null : _editTrade,
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: JT.tint(context, JT.loss, 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 16, color: JT.loss),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: JT.caption(context,
                                    size: 12, color: JT.loss)),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: JtButton(
                  label: 'Not now',
                  height: 50,
                  onTap: _submitting ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: JtButton(
                  label: qtyLabel,
                  icon: Icons.check_rounded,
                  filled: true,
                  expand: true,
                  height: 50,
                  loading: _submitting,
                  onTap: _submitting ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StockSummary(
            holding: _h,
            name: name,
            isShort: isShort,
            ltp: widget.currentLtp,
          ),
          const SizedBox(height: 20),

          // ── How many shares ──
          _FieldLabel(
            'How many shares?',
            hint: 'You hold ${_h.quantity}',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StepperButton(
                icon: Icons.remove_rounded,
                onTap: _qty > 1 ? () => _setQty(_qty - 1) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _qtyCtrl,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    TextInputFormatter.withFunction((oldV, newV) {
                      if (newV.text.isEmpty) return newV;
                      final q = int.tryParse(newV.text) ?? 0;
                      return q > _h.quantity ? oldV : newV;
                    }),
                  ],
                  style: JT.number(context, size: 20),
                  decoration: _inputDecoration(context),
                ),
              ),
              const SizedBox(width: 10),
              _StepperButton(
                icon: Icons.add_rounded,
                onTap: _qty < _h.quantity ? () => _setQty(_qty + 1) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final p in const [25, 50, 75, 100]) ...[
                Expanded(
                  child: _QuickChip(
                    label: p == 100 ? 'All' : '$p%',
                    selected: _qty == _qtyForPercent(p),
                    onTap: () => _setQty(_qtyForPercent(p)),
                  ),
                ),
                if (p != 100) const SizedBox(width: 8),
              ],
            ],
          ),

          const SizedBox(height: 22),

          // ── Price ──
          _FieldLabel(
            isShort ? 'Price you bought back at' : 'Price you sold at',
            hint: _hasLivePrice ? 'Filled with today\'s market price' : null,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            style: JT.number(context, size: 20),
            decoration: _inputDecoration(context).copyWith(
              prefixText: '₹ ',
              prefixStyle:
                  JT.number(context, size: 20, color: JT.text2(context)),
              hintText: 'Enter price',
            ),
          ),
          if (!_hasLivePrice) ...[
            const SizedBox(height: 6),
            Text(
              'Live price isn\'t available right now, so please enter the '
              'price you closed at.',
              style: JT.caption(context, size: 12, color: JT.amber),
            ),
          ] else if (_price == null ||
              (_price! - double.parse(widget.currentLtp.toStringAsFixed(2)))
                      .abs() >
                  0.001) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () =>
                  _priceCtrl.text = widget.currentLtp.toStringAsFixed(2),
              child: Text(
                'Use market price (${jtPrice(widget.currentLtp)})',
                style: JT.caption(context, size: 12, color: JT.blue),
              ),
            ),
          ],

          const SizedBox(height: 22),

          // ── When ──
          const _FieldLabel('When did you close it?'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _QuickChip(
                  label: 'Right now',
                  selected: _useNow,
                  onTap: () => setState(() => _useNow = true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickChip(
                  label: 'Earlier — pick time',
                  selected: !_useNow,
                  onTap: () => setState(() {
                    _useNow = false;
                    _picked = DateTime.now();
                  }),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _useNow
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PickerTile(
                            icon: Icons.calendar_today_rounded,
                            label:
                                DateFormat('EEE, d MMM yyyy').format(_picked),
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PickerTile(
                            icon: Icons.access_time_rounded,
                            label: DateFormat('h:mm a').format(_picked),
                            onTap: _pickTime,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          const SizedBox(height: 22),

          // ── What happens ──
          _OutcomePreview(
            holding: _h,
            isShort: isShort,
            qty: _qtyOk ? _qty : null,
            price: _price,
          ),
        ],
      ),
    );
  }

  int _qtyForPercent(int p) =>
      (_h.quantity * p / 100).round().clamp(1, _h.quantity);

  InputDecoration _inputDecoration(BuildContext context) => InputDecoration(
        filled: true,
        fillColor: JT.surface(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: JT.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: JT.border(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: JT.blue, width: 2),
        ),
      );
}

// ─────────────────────────────────────────────
//  Pieces
// ─────────────────────────────────────────────

class _StockSummary extends StatelessWidget {
  final BasketUserHolding holding;
  final String name;
  final bool isShort;
  final double ltp;
  const _StockSummary({
    required this.holding,
    required this.name,
    required this.isShort,
    required this.ltp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: JT.card(context),
      child: Row(
        children: [
          JtLogo(
            symbolKey: jtLogoKey(holding.symbol),
            accent: isShort ? JT.amber : JT.blue,
            size: 48,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JT.heading(context, size: 17)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    JtDirectionChip(isShort: isShort),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${holding.quantity} ${holding.quantity == 1 ? 'share' : 'shares'}',
                        overflow: TextOverflow.ellipsis,
                        style: JT.caption(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${isShort ? 'Sold' : 'Bought'} at ${jtPrice(holding.averagePrice)}',
                  style: JT.caption(context, size: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Price now', style: JT.caption(context, size: 11)),
              const SizedBox(height: 2),
              Text(
                ltp > 0 ? jtPrice(ltp) : '—',
                style: JT.number(context, size: 17),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutcomePreview extends StatelessWidget {
  final BasketUserHolding holding;
  final bool isShort;
  final int? qty;
  final double? price;
  const _OutcomePreview({
    required this.holding,
    required this.isShort,
    required this.qty,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    final ready = qty != null && price != null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child:
            SizeTransition(sizeFactor: anim, axisAlignment: -1, child: child),
      ),
      child: ready ? _body(context) : const SizedBox(width: double.infinity),
    );
  }

  Widget _body(BuildContext context) {
    final dir = isShort ? -1 : 1;
    final avg = holding.averagePrice;
    final pnl = (price! - avg) * qty! * dir;
    final pct = avg > 0 ? (price! - avg) / avg * 100 * dir : 0.0;
    final color = JT.pnl(pnl);
    final remaining = holding.quantity - qty!;
    final headline = pnl == 0
        ? 'You\'ll break even'
        : 'If you close at this price, you\'ll ${pnl > 0 ? 'make' : 'lose'}';

    return AnimatedContainer(
      key: const ValueKey('preview'),
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JT.tint(context, color, 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: JT.caption(context, size: 12, color: color),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              JtCount(
                value: pnl,
                duration: const Duration(milliseconds: 350),
                format: (v) => jtMoney(v.abs()),
                style: JT.number(context, size: 28, color: color),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: JtPctTag(pct: pct),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                remaining == 0
                    ? Icons.task_alt_rounded
                    : Icons.pie_chart_outline_rounded,
                size: 15,
                color: JT.text2(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  remaining == 0
                      ? 'This closes the whole trade.'
                      : 'You\'ll still have $remaining ${remaining == 1 ? 'share' : 'shares'} open.',
                  style: JT.caption(context, size: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final String? hint;
  const _FieldLabel(this.text, {this.hint});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(text, style: JT.heading(context, size: 15)),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(hint!,
                  overflow: TextOverflow.ellipsis,
                  style: JT.caption(context, size: 12)),
            ),
          ],
        ],
      );
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onTap == null ? 0.4 : 1,
        child: JtPressable(
          onTap: onTap,
          pressedScale: 0.92,
          child: Container(
            width: 48,
            height: 52,
            decoration: BoxDecoration(
              color: JT.surface(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JT.border(context)),
            ),
            child: Icon(icon, color: JT.text(context)),
          ),
        ),
      );
}

class _QuickChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _QuickChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => JtPressable(
        onTap: onTap,
        pressedScale: 0.95,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? JT.blue : JT.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? JT.blue : JT.border(context), width: 1),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? Colors.white : JT.text2(context),
            ),
          ),
        ),
      );
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => JtPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: JT.surface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: JT.border(context)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: JT.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JT.body(context, size: 13, weight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
}
