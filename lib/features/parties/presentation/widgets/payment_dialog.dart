import 'package:flutter/material.dart';

import '../../../../core/services/retail_store.dart';
import '../../../../core/services/statements.dart';
import '../../../../core/utils/formatters.dart';

/// Takes money against a customer's balance, or pays a supplier down.
class PaymentDialog extends StatefulWidget {
  const PaymentDialog({
    super.key,
    required this.store,
    required this.kind,
    required this.partyId,
    required this.partyName,
    required this.outstanding,
  });

  final RetailStore store;
  final PartyKind kind;
  final int partyId;
  final String partyName;
  final double outstanding;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  late final _amount = TextEditingController(
    // Settling the whole balance is the common case, so it is pre-filled and
    // the cashier only types when it is a part payment.
    text: widget.outstanding > 0 ? widget.outstanding.toStringAsFixed(2) : '',
  );
  final _notes = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _isReceipt => widget.kind == PartyKind.customer;

  @override
  Widget build(BuildContext context) {
    final entered = double.tryParse(_amount.text.trim()) ?? 0;
    final remaining = widget.outstanding - entered;

    return AlertDialog(
      title: Text(
        _isReceipt
            ? 'Receive from ${widget.partyName}'
            : 'Pay ${widget.partyName}',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.kind.balanceLabel}: '
              '${AppFormatters.currency(widget.outstanding)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${AppFormatters.symbol} ',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PaymentMethod>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Paid by'),
              items: [
                for (final method in PaymentMethod.values)
                  DropdownMenuItem(value: method, child: Text(method.label)),
              ],
              onChanged: (m) => setState(() => _method = m ?? _method),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Cheque number, who handed it over…',
              ),
            ),
            if (entered > 0) ...[
              const SizedBox(height: 12),
              Text(
                remaining > 0.001
                    ? 'Still outstanding after this: '
                          '${AppFormatters.currency(remaining)}'
                    : remaining < -0.001
                    ? 'This is ${AppFormatters.currency(-remaining)} more than '
                          'the balance — it will be carried as an advance.'
                    : 'This settles the balance in full.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_method == PaymentMethod.cash &&
                widget.store.openShift != null) ...[
              const SizedBox(height: 8),
              Text(
                _isReceipt
                    ? 'Cash will be added to the open till session.'
                    : 'Cash will be taken out of the open till session.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_isReceipt ? 'Record receipt' : 'Record payment'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payment = await widget.store.recordPartyPayment(
        kind: widget.kind,
        partyId: widget.partyId,
        amount: double.tryParse(_amount.text.trim()) ?? 0,
        method: _method,
        notes: _notes.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(payment);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }
}
