import 'package:flutter/material.dart';

import '../../../../core/services/permissions.dart';
import '../../../../core/services/retail_store.dart';
import '../../../../core/services/statements.dart';
import '../../../../core/utils/formatters.dart';
import 'payment_dialog.dart';
import 'statement_dialog.dart';

/// The settle-up and statement buttons that sit on every customer and supplier
/// row. Shared so the two screens cannot drift apart.
class PartyActions extends StatelessWidget {
  const PartyActions({
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

  bool get _isCustomer => kind == PartyKind.customer;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (store.can(Permission.recordPayments))
          IconButton(
            tooltip: _isCustomer
                ? 'Receive money from $partyName'
                : 'Pay $partyName',
            // Nothing owed means nothing to settle, so the button is off rather
            // than opening a dialog that can only be cancelled.
            onPressed: outstanding <= 0 ? null : () => _openPayment(context),
            icon: Icon(
              _isCustomer ? Icons.payments_outlined : Icons.outbox_outlined,
            ),
          ),
        IconButton(
          tooltip: 'Statement of account',
          onPressed: () => _openStatement(context),
          icon: const Icon(Icons.receipt_long_outlined),
        ),
      ],
    );
  }

  Future<void> _openPayment(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final payment = await showDialog<PartyPaymentRecord>(
      context: context,
      builder: (_) => PaymentDialog(
        store: store,
        kind: kind,
        partyId: partyId,
        partyName: partyName,
        outstanding: outstanding,
      ),
    );
    if (payment == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${AppFormatters.currency(payment.amount)} recorded against '
          '$partyName — voucher ${payment.reference}.',
        ),
      ),
    );
  }

  Future<void> _openStatement(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => StatementDialog(
      store: store,
      kind: kind,
      partyId: partyId,
      partyName: partyName,
    ),
  );
}
