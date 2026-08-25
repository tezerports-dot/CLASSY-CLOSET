import 'package:flutter/material.dart';

import '../../../../core/services/retail_store.dart';
import '../../../../core/theme/app_colors.dart';

/// Clears the practice data a shop rings up while learning the till.
///
/// Every shop does a week of fake sales before it opens, and then has to open
/// for real with a ledger full of them. Rather than making somebody delete a
/// hundred rows by hand — or reinstall and retype the whole catalogue — this
/// wipes the history and leaves the setup.
///
/// It is deliberately awkward: two checkboxes for the wider blast radii, a
/// typed confirmation, and a summary of exactly what is about to go. Nothing
/// here can be undone from inside the app, so the backup is named as the way
/// out before the button is ever pressed.
class ResetDataPanel extends StatefulWidget {
  const ResetDataPanel({required this.store, required this.onDone, super.key});

  final RetailStore store;
  final VoidCallback onDone;

  @override
  State<ResetDataPanel> createState() => _ResetDataPanelState();
}

class _ResetDataPanelState extends State<ResetDataPanel> {
  bool _alsoParties = false;
  bool _alsoCatalogue = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.dangerWash,
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
            borderRadius: AppRadii.inputBorder,
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.danger,
                size: 20,
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'This cannot be undone from inside the app. Take a backup '
                  'first — Settings → Backup — and keep it until you are sure '
                  'the shop is trading correctly.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _line('Bills, returns and credit notes', store.sales.length),
        _line('Deliveries recorded against suppliers', store.purchases.length),
        _line('Expenses', store.expenses.length),
        _line('Payments taken and made', store.partyPayments.length),
        _line('Held bills', store.heldBills.length),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Stock goes back to zero on every product, and customer and '
          'supplier balances are cleared — they are worked out from the rows '
          'above, so leaving them would leave money owed by nobody. Bill '
          'numbering starts again at one.',
          style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
        ),
        const Divider(height: 32),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _alsoParties,
          onChanged: _busy
              ? null
              : (v) => setState(() => _alsoParties = v ?? false),
          title: const Text('Also delete customers and suppliers'),
          subtitle: Text(
            'Removes all ${store.customers.length} customer'
            "${store.customers.length == 1 ? '' : 's'} and "
            '${store.suppliers.length} supplier'
            "${store.suppliers.length == 1 ? '' : 's'}. Leave this off if you "
            'typed real ones in already.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _alsoCatalogue,
          onChanged: _busy
              ? null
              : (v) => setState(() => _alsoCatalogue = v ?? false),
          title: const Text('Also delete the whole catalogue'),
          subtitle: Text(
            'Removes all ${store.styles.length} design'
            "${store.styles.length == 1 ? '' : 's'} and "
            '${store.products.length} unit'
            "${store.products.length == 1 ? '' : 's'}, with their photos. "
            'Your shop profile, staff logins and settings are kept.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            onPressed: _busy ? null : _confirm,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset the shop data'),
          ),
        ),
      ],
    );
  }

  Widget _line(String label, int count) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        const Icon(
          Icons.remove_circle_outline,
          size: 14,
          color: AppColors.danger,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    ),
  );

  Future<void> _confirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmResetDialog(
        alsoParties: _alsoParties,
        alsoCatalogue: _alsoCatalogue,
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.store.resetTradingData(
        alsoParties: _alsoParties,
        alsoCatalogue: _alsoCatalogue,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _alsoParties = false;
          _alsoCatalogue = false;
        });
      }
    }
    widget.onDone();
  }
}

/// The typed confirmation. A button this destructive should not be reachable
/// by a mis-click, and "are you sure?" alone is one click away from yes.
class _ConfirmResetDialog extends StatefulWidget {
  const _ConfirmResetDialog({
    required this.alsoParties,
    required this.alsoCatalogue,
  });

  final bool alsoParties;
  final bool alsoCatalogue;

  @override
  State<_ConfirmResetDialog> createState() => _ConfirmResetDialogState();
}

class _ConfirmResetDialogState extends State<_ConfirmResetDialog> {
  static const _phrase = 'RESET';
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _typed.text.trim().toUpperCase() == _phrase;
    return AlertDialog(
      title: const Text('Reset the shop data?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This deletes every bill, delivery, expense, payment and till '
              'session${widget.alsoParties ? ', every customer and supplier' : ''}'
              '${widget.alsoCatalogue ? ', and the whole catalogue' : ''}. '
              'It cannot be undone.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'Type RESET to confirm.',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _typed,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: _phrase),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (matches) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Reset everything'),
        ),
      ],
    );
  }
}
