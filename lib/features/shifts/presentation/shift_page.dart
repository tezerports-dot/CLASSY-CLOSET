import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/services/returns_and_shifts.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

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
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (open == null) _openCard() else _runningCard(context),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Past sessions',
                child: _store.shifts.where((s) => !s.isOpen).isEmpty
                    ? const Text('No till sessions have been closed yet.')
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Who')),
                            DataColumn(label: Text('Opened')),
                            DataColumn(label: Text('Closed')),
                            DataColumn(label: Text('Bills')),
                            DataColumn(label: Text('Cash')),
                            DataColumn(label: Text('Card')),
                            DataColumn(label: Text('UPI')),
                            DataColumn(label: Text('Expected')),
                            DataColumn(label: Text('Counted')),
                            DataColumn(label: Text('Difference')),
                          ],
                          rows: [
                            for (final s in _store.shifts.where(
                              (s) => !s.isOpen,
                            ))
                              DataRow(
                                cells: [
                                  DataCell(Text(s.userName)),
                                  DataCell(
                                    Text(AppFormatters.dateTime(s.openedAt)),
                                  ),
                                  DataCell(
                                    Text(
                                      s.closedAt == null
                                          ? '—'
                                          : AppFormatters.dateTime(s.closedAt!),
                                    ),
                                  ),
                                  DataCell(Text('${s.saleCount}')),
                                  DataCell(
                                    Text(AppFormatters.currency(s.cashSales)),
                                  ),
                                  DataCell(
                                    Text(AppFormatters.currency(s.cardSales)),
                                  ),
                                  DataCell(
                                    Text(AppFormatters.currency(s.upiSales)),
                                  ),
                                  DataCell(
                                    Text(
                                      AppFormatters.currency(
                                        s.expectedCash ?? 0,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      AppFormatters.currency(
                                        s.closingCount ?? 0,
                                      ),
                                    ),
                                  ),
                                  DataCell(_variance(context, s.variance)),
                                ],
                              ),
                          ],
                        ),
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
    final theme = Theme.of(context);
    // A shortfall is the one worth spotting across a crowded table.
    final colour = variance.abs() < 0.01
        ? null
        : (variance < 0 ? theme.colorScheme.error : theme.colorScheme.primary);
    return Text(
      AppFormatters.currency(variance),
      style: TextStyle(color: colour, fontWeight: FontWeight.w600),
    );
  }

  Widget _openCard() => SectionCard(
    title: 'Start the till',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Count the cash you are putting in the drawer and enter it as the '
          'opening float. Everything sold from now on is recorded against this '
          'session.',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _float,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Opening float',
                  prefixText: '${AppFormatters.symbol} ',
                ),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Open till'),
            ),
          ],
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
      actions: [
        TextButton.icon(
          onPressed: _refreshLive,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Opened by ${live?.userName ?? '—'} at '
            '${live == null ? '—' : AppFormatters.dateTime(live.openedAt)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),

          // The X report: where the session stands right now, without closing.
          Wrap(
            spacing: 28,
            runSpacing: 12,
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
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Use this for anything that is not a sale — paying a delivery in '
            'cash, or taking change from the bank.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
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
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _move(true),
                icon: const Icon(Icons.arrow_downward),
                label: const Text('Paid in'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _move(false),
                icon: const Icon(Icons.arrow_upward),
                label: const Text('Paid out'),
              ),
            ],
          ),
          const Divider(height: 32),

          Text('Close the till', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Count the cash in the drawer and enter the total. The difference '
            'is recorded against this session and cannot be edited afterwards.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            Text(
              difference.abs() < 0.01
                  ? 'The drawer balances exactly.'
                  : difference < 0
                  ? 'Short by ${AppFormatters.currency(difference.abs())}.'
                  : 'Over by ${AppFormatters.currency(difference)}.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: difference.abs() < 0.01
                    ? theme.colorScheme.primary
                    : difference < 0
                    ? theme.colorScheme.error
                    : null,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || counted == null ? null : _close,
            icon: const Icon(Icons.lock),
            label: const Text('Close till and record the count'),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, Object value, {bool strong = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 11.5)),
      Text(
        value is num ? AppFormatters.currency(value) : value.toString(),
        style: TextStyle(
          fontSize: strong ? 20 : 16,
          fontWeight: strong ? FontWeight.bold : FontWeight.w600,
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
