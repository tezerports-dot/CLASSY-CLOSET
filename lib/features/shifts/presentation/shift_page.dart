import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/services/returns_and_shifts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';

/// Opening and closing the till, and counting the drawer against it.
///
/// This is the record that makes a cash shortfall attributable: without it
/// there is no way to say who was on the counter when money went missing.
class ShiftPage extends StatefulWidget {
  const ShiftPage({super.key});

  @override
  State<ShiftPage> createState() => _ShiftPageState();
}

class _ShiftPageState extends State<ShiftPage> {
  final _store = getIt<RetailStore>();
  final _float = TextEditingController(text: '0');
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  final _movementAmount = TextEditingController();
  final _movementReason = TextEditingController();

  ShiftRecord? _live;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshLive();
  }

  @override
  void dispose() {
    _float.dispose();
    _counted.dispose();
    _notes.dispose();
    _movementAmount.dispose();
    _movementReason.dispose();
    super.dispose();
  }

  Future<void> _refreshLive() async {
    final live = await _store.currentShiftWithTotals();
    if (mounted) setState(() => _live = live);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final open = _store.openShift;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Till',
                subtitle:
                    'Opening and closing the drawer, and counting it against '
                    'what the day says should be there.',
                actions: [
                  StatusPill(
                    open == null ? 'Till closed' : 'Till open',
                    tone: open == null ? PillTone.neutral : PillTone.good,
                  ),
                ],
              ),
              if (open == null) _openCard() else _runningCard(context),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: 'Past sessions',
                subtitle:
                    'A closed session is the record that makes a shortfall '
                    'attributable, so it cannot be edited afterwards.',
                child: AppTable(
                  minWidth: 1080,
                  empty: const EmptyState(
                    icon: Icons.point_of_sale_outlined,
                    title: 'No sessions closed yet',
                    message:
                        'Open the till at the start of the day and close it at '
                        'the end, and each day appears here with its count.',
                  ),
                  columns: const [
                    DataColumn(label: Text('WHO')),
                    DataColumn(label: Text('OPENED')),
                    DataColumn(label: Text('CLOSED')),
                    DataColumn(label: Text('BILLS'), numeric: true),
                    DataColumn(label: Text('CASH'), numeric: true),
                    DataColumn(label: Text('CARD'), numeric: true),
                    DataColumn(label: Text('UPI'), numeric: true),
                    DataColumn(label: Text('EXPECTED'), numeric: true),
                    DataColumn(label: Text('COUNTED'), numeric: true),
                    DataColumn(label: Text('DIFFERENCE'), numeric: true),
                  ],
                  rows: [
                    for (final s in _store.shifts.where((s) => !s.isOpen))
                      DataRow(
                        cells: [
                          DataCell(Text(s.userName)),
                          DataCell(Text(AppFormatters.dateTime(s.openedAt))),
                          DataCell(
                            Text(
                              s.closedAt == null
                                  ? '—'
                                  : AppFormatters.dateTime(s.closedAt!),
                            ),
                          ),
                          DataCell(Text('${s.saleCount}')),
                          DataCell(MoneyText(s.cashSales, size: 13)),
                          DataCell(MoneyText(s.cardSales, size: 13)),
                          DataCell(MoneyText(s.upiSales, size: 13)),
                          DataCell(MoneyText(s.expectedCash ?? 0, size: 13)),
                          DataCell(MoneyText(s.closingCount ?? 0, size: 13)),
                          DataCell(_variance(context, s.variance)),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _variance(BuildContext context, double? variance) {
    if (variance == null) return const Text('—');
    // A shortfall is the one worth spotting across a crowded table.
    if (variance.abs() < 0.01) {
      return const StatusPill('Balanced', tone: PillTone.good);
    }
    return MoneyText(
      variance,
      size: 13,
      weight: FontWeight.w600,
      tone: variance < 0 ? AppColors.danger : AppColors.goldDeep,
    );
  }

  Widget _openCard() => SectionCard(
    title: 'Start the till',
    subtitle:
        'Count the cash you are putting in the drawer and enter it as the '
        'opening float. Everything sold from now on is recorded against this '
        'session.',
    child: Row(
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _float,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Opening float',
              prefixText: '${AppFormatters.symbol} ',
            ),
            onSubmitted: (_) => _start(),
          ),
        ),
        const SizedBox(width: AppSpacing.xl),
        AccentButton(
          label: 'Open till',
          icon: Icons.play_arrow_rounded,
          tall: true,
          busy: _busy,
          onPressed: _start,
        ),
      ],
    ),
  );

  Widget _runningCard(BuildContext context) {
    final live = _live;
    final theme = Theme.of(context);
    final expected = live?.computedExpectedCash ?? 0;
    final counted = double.tryParse(_counted.text.trim());
    final difference = counted == null ? null : counted - expected;

    return SectionCard(
      title: 'Till is open',
      subtitle:
          'Opened by ${live?.userName ?? '—'} at '
          '${live == null ? '—' : AppFormatters.dateTime(live.openedAt)}',
      actions: [
        TextButton.icon(
          onPressed: _refreshLive,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The X report: where the session stands right now, without closing.
          Wrap(
            spacing: 32,
            runSpacing: AppSpacing.base,
            children: [
              _stat('Bills', '${live?.saleCount ?? 0}'),
              _stat('Opening float', live?.openingFloat ?? 0),
              _stat('Cash sales', live?.cashSales ?? 0),
              _stat('Card', live?.cardSales ?? 0),
              _stat('UPI', live?.upiSales ?? 0),
              _stat('Cash refunds', -(live?.cashRefunds ?? 0)),
              _stat('Paid in', live?.paidIn ?? 0),
              _stat('Paid out', -(live?.paidOut ?? 0)),
              _stat('Cash expected', expected, strong: true),
            ],
          ),
          const Divider(height: 32),

          Text(
            'Money in or out of the drawer',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 3),
          Text(
            'Use this for anything that is not a sale — paying a delivery in '
            'cash, or taking change from the bank.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            children: [
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _movementAmount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: '${AppFormatters.symbol} ',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _movementReason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              SecondaryButton(
                label: 'Paid in',
                icon: Icons.arrow_downward_rounded,
                onPressed: _busy ? null : () => _move(true),
              ),
              const SizedBox(width: AppSpacing.sm),
              SecondaryButton(
                label: 'Paid out',
                icon: Icons.arrow_upward_rounded,
                onPressed: _busy ? null : () => _move(false),
              ),
            ],
          ),
          const Divider(height: 32),

          Text('Close the till', style: theme.textTheme.titleLarge),
          const SizedBox(height: 3),
          Text(
            'Count the cash in the drawer and enter the total. The difference '
            'is recorded against this session and cannot be edited afterwards.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _counted,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Cash counted',
                    prefixText: '${AppFormatters.symbol} ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
              ),
            ],
          ),
          if (difference != null) ...[
            const SizedBox(height: AppSpacing.base),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: difference.abs() < 0.01
                    ? AppColors.successWash
                    : difference < 0
                    ? AppColors.dangerWash
                    : AppColors.goldWash,
                borderRadius: AppRadii.inputBorder,
              ),
              child: Row(
                children: [
                  Icon(
                    difference.abs() < 0.01
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 16,
                    color: difference.abs() < 0.01
                        ? AppColors.success
                        : difference < 0
                        ? AppColors.danger
                        : AppColors.goldDeep,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    difference.abs() < 0.01
                        ? 'The drawer balances exactly.'
                        : difference < 0
                        ? 'Short by ${AppFormatters.currency(difference.abs())}.'
                        : 'Over by ${AppFormatters.currency(difference)}.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: difference.abs() < 0.01
                          ? AppColors.success
                          : difference < 0
                          ? AppColors.danger
                          : AppColors.goldDeep,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Align(
            alignment: Alignment.centerLeft,
            child: AccentButton(
              label: 'Close till and record the count',
              icon: Icons.lock_outline_rounded,
              tall: true,
              busy: _busy,
              onPressed: counted == null ? null : _close,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, Object value, {bool strong = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label.toUpperCase(),
        style: AppTypography.microLabel.copyWith(
          color: strong ? AppColors.goldDeep : AppColors.inkFaint,
        ),
      ),
      const SizedBox(height: 2),
      if (value is num)
        MoneyText(
          value.toDouble(),
          size: strong ? 21 : 15,
          weight: strong ? FontWeight.w700 : FontWeight.w600,
          signed: value < 0,
        )
      else
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: strong ? 21 : 15,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
    ],
  );

  Future<void> _start() async {
    setState(() => _busy = true);
    await _store.startShift(
      openingFloat: double.tryParse(_float.text.trim()) ?? 0,
    );
    await _refreshLive();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _move(bool isIn) async {
    final amount = double.tryParse(_movementAmount.text.trim()) ?? 0;
    final reason = _movementReason.text.trim();
    if (amount <= 0 || reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount and a reason.')),
      );
      return;
    }
    setState(() => _busy = true);
    await _store.recordCashMovement(isIn: isIn, amount: amount, reason: reason);
    _movementAmount.clear();
    _movementReason.clear();
    await _refreshLive();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _close() async {
    final counted = double.tryParse(_counted.text.trim());
    if (counted == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close the till?'),
        content: Text(
          'Recording ${AppFormatters.currency(counted)} counted against '
          '${AppFormatters.currency(_live?.computedExpectedCash ?? 0)} expected.'
          '\n\nA closed session cannot be edited.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close till'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    await _store.endShift(countedCash: counted, notes: _notes.text);
    _counted.clear();
    _notes.clear();
    await _refreshLive();
    if (mounted) setState(() => _busy = false);
  }
}
