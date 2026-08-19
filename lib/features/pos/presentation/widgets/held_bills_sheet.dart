import 'package:flutter/material.dart';

import '../../../../core/services/held_bills.dart';
import '../../../../core/services/retail_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/ui_kit.dart';

/// The parked bills, waiting to come back to the counter.
///
/// A customer goes to the trial room, the queue behind them keeps moving, and
/// their basket waits here. Recalling pops this sheet with the bill's id so the
/// billing screen knows something came back; discarding stays open, because the
/// counter usually clears several stale bills in one go.
class HeldBillsSheet extends StatefulWidget {
  const HeldBillsSheet({super.key, required this.store});

  final RetailStore store;

  @override
  State<HeldBillsSheet> createState() => _HeldBillsSheetState();
}

class _HeldBillsSheetState extends State<HeldBillsSheet> {
  int? _busyId;

  RetailStore get _store => widget.store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bills = _store.heldBills;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.xl),
        constraints: const BoxConstraints(maxHeight: 560, maxWidth: 620),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.cardBorder,
          border: Border.all(color: AppColors.border),
          boxShadow: const [AppColors.panelShadow],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.xl,
                AppSpacing.base,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Held bills',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          bills.isEmpty
                              ? 'Nothing is parked right now.'
                              : '${bills.length} basket${bills.length == 1 ? '' : 's'} waiting to come back.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: bills.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: EmptyState(
                        icon: Icons.pause_circle_outline,
                        title: 'No bills on hold',
                        message:
                            'Use "Hold bill" on the counter when a customer '
                            'steps away, and it will wait here.',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      shrinkWrap: true,
                      itemCount: bills.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _tile(context, bills[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, HeldBillRecord bill) {
    final theme = Theme.of(context);
    final busy = _busyId == bill.id;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.base,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        bill.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (bill.customerName != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      StatusPill(bill.customerName!, tone: PillTone.strong),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${bill.itemCount} item${bill.itemCount == 1 ? '' : 's'}  ·  '
                  'held ${AppFormatters.dateTime(bill.heldAt)}',
                  style: AppTypography.microLabel.copyWith(
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.base),
          MoneyText(bill.total, size: 15, weight: FontWeight.w600),
          const SizedBox(width: AppSpacing.lg),
          SecondaryButton(
            label: 'Discard',
            tone: AppColors.danger,
            onPressed: busy ? null : () => _discard(bill),
          ),
          const SizedBox(width: AppSpacing.sm),
          AccentButton(
            label: 'Recall',
            icon: Icons.play_arrow_rounded,
            busy: busy,
            onPressed: busy ? null : () => _recall(bill),
          ),
        ],
      ),
    );
  }

  Future<void> _recall(HeldBillRecord bill) async {
    setState(() => _busyId = bill.id);
    try {
      await _store.recallHeldBill(bill.id);
      if (mounted) Navigator.of(context).pop(bill.id);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _discard(HeldBillRecord bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this held bill?'),
        content: Text(
          '"${bill.label}" has ${bill.itemCount} item'
          '${bill.itemCount == 1 ? '' : 's'} worth '
          '${AppFormatters.currency(bill.total)}. Nothing is sold and no stock '
          'moves — the basket is simply thrown away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = bill.id);
    await _store.discardHeldBill(bill.id);
    if (mounted) setState(() => _busyId = null);
  }
}
