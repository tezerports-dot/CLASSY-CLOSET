import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/services/stocktake.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/ui_kit.dart';

/// Counting the rails and putting the books right afterwards.
class StocktakePage extends StatefulWidget {
  const StocktakePage({super.key});

  @override
  State<StocktakePage> createState() => _StocktakePageState();
}

class _StocktakePageState extends State<StocktakePage> {
  final _store = getIt<RetailStore>();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  ProductRecord? _selected;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final session = _store.openStocktake;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Stock count',
                subtitle:
                    'Count what is actually on the rails, then apply the count '
                    'so the books match.',
                actions: [
                  StatusPill(
                    session == null ? 'No count open' : 'Counting',
                    tone: session == null ? PillTone.neutral : PillTone.caution,
                  ),
                ],
              ),
              if (session == null)
                _startCard(context)
              else
                _countCard(context, session),
              const SizedBox(height: AppSpacing.xl),
              _adjustCard(context),
              const SizedBox(height: AppSpacing.xl),
              _historyCard(context),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ starting up

  Widget _startCard(BuildContext context) => SectionCard(
    child: Column(
      children: [
        EmptyState(
          icon: Icons.playlist_add_check_rounded,
          title: 'No count in progress',
          message:
              'Sales carry on as normal while you count — each line is '
              'compared against the stock figure at the moment you enter it, '
              'so a sale rung up mid-count is not read as shrinkage.',
          action: AccentButton(
            label: 'Start a count',
            icon: Icons.playlist_add_check_rounded,
            busy: _busy,
            onPressed: _start,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.base),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ],
    ),
  );

  // -------------------------------------------------------------- counting

  Widget _countCard(BuildContext context, StocktakeRecord session) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Counting — ${session.reference}',
      subtitle:
          'Scan or search for a garment, type what is on the rail, and press '
          'Record. Nothing moves on the books until you apply the count.',
      actions: [
        SecondaryButton(
          label: 'Abandon',
          icon: Icons.close_rounded,
          tone: AppColors.danger,
          onPressed: _busy ? null : () => _abandon(session),
        ),
        const SizedBox(width: AppSpacing.sm),
        AccentButton(
          label: 'Apply the count',
          icon: Icons.check_rounded,
          busy: _busy,
          onPressed: session.lines.isEmpty ? null : () => _commit(session),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Scan or find the item',
                    hintText: 'Scan a barcode, or type a name, SKU or size',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _onScan,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _counted,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Counted'),
                  onSubmitted: (_) => _saveCount(session),
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: AccentButton(
                  label: 'Record',
                  icon: Icons.add_task_rounded,
                  tall: true,
                  busy: _busy,
                  onPressed: _selected == null
                      ? null
                      : () => _saveCount(session),
                ),
              ),
            ],
          ),
          if (_selected != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Counting ${_selected!.displayName} — the books say '
                '${AppFormatters.quantity(_selected!.stock)}',
                style: theme.textTheme.bodySmall,
              ),
            )
          else if (_search.text.trim().isNotEmpty)
            _matches(),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: AppSpacing.xl),
          _summaryStrip(context, session),
          const SizedBox(height: AppSpacing.base),
          AppTable(
            minWidth: 760,
            empty: const EmptyState(
              icon: Icons.checklist_rtl_rounded,
              title: 'Nothing counted yet',
              message:
                  'Scan the first garment and type how many are on the '
                  'rail. Lines appear here as you go, and the count can be '
                  'picked back up tomorrow.',
            ),
            columns: const [
              DataColumn(label: Text('ITEM')),
              DataColumn(label: Text('BOOKS'), numeric: true),
              DataColumn(label: Text('COUNTED'), numeric: true),
              DataColumn(label: Text('DIFFERENCE'), numeric: true),
              DataColumn(label: Text('AT COST'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final line in session.lines)
                DataRow(
                  cells: [
                    DataCell(Text(line.description)),
                    DataCell(Text(AppFormatters.quantity(line.systemQuantity))),
                    DataCell(
                      Text(AppFormatters.quantity(line.countedQuantity)),
                    ),
                    DataCell(
                      line.matches
                          ? const StatusPill('Matches', tone: PillTone.good)
                          : Text(
                              '${line.variance > 0 ? '+' : ''}'
                              '${AppFormatters.quantity(line.variance)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: line.variance < 0
                                    ? AppColors.danger
                                    : AppColors.success,
                              ),
                            ),
                    ),
                    DataCell(
                      line.matches
                          ? const Text('—')
                          : MoneyText(line.varianceValue, size: 13),
                    ),
                    DataCell(
                      IconButton(
                        tooltip: 'Remove this line',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy
                            ? null
                            : () => _store.removeCount(
                                stocktakeId: session.id,
                                productId: line.productId,
                              ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStrip(BuildContext context, StocktakeRecord session) =>
      Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: AppRadii.inputBorder,
          border: Border.all(color: AppColors.border),
        ),
        child: Wrap(
          spacing: 32,
          runSpacing: AppSpacing.base,
          children: [
            _tally('Lines counted', '${session.countedLines}'),
            _tally('Differences', '${session.discrepancies.length}'),
            _tally(
              'Short',
              AppFormatters.currency(session.shortValue.abs()),
              tone: session.shortValue.abs() > 0 ? AppColors.danger : null,
            ),
            _tally(
              'Over',
              AppFormatters.currency(session.overValue),
              tone: session.overValue > 0 ? AppColors.success : null,
            ),
            _tally(
              'Net effect',
              AppFormatters.currency(session.netValue),
              strong: true,
            ),
          ],
        ),
      );

  Widget _tally(
    String label,
    String value, {
    Color? tone,
    bool strong = false,
  }) => Column(
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
      Text(
        value,
        style: TextStyle(
          fontSize: strong ? 19 : 15,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
          fontFeatures: AppTypography.tabular,
          color: tone,
        ),
      ),
    ],
  );

  Widget _matches() {
    final query = _search.text.trim().toLowerCase();
    final matches = _store.products
        .where((p) => p.active)
        .where(
          (p) => '${p.name} ${p.sku} ${p.barcode} ${p.size} ${p.color}'
              .toLowerCase()
              .contains(query),
        )
        .take(6)
        .toList();
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Text(
          'Nothing matches that. Check the barcode, or search by name.',
          style: AppTypography.microLabel.copyWith(color: AppColors.inkFaint),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadii.inputBorder,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final product in matches)
            ListTile(
              dense: true,
              title: Text(product.displayName),
              subtitle: Text(
                '${product.sku} — books say '
                '${AppFormatters.quantity(product.stock)}',
              ),
              trailing: const Icon(Icons.arrow_forward_rounded, size: 15),
              onTap: () => _select(product),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- one-off changes

  Widget _adjustCard(BuildContext context) => SectionCard(
    title: 'Write something off',
    subtitle:
        'For a single item damaged, given away or found — without opening a '
        'whole count.',
    actions: [
      SecondaryButton(
        label: 'Adjust one item',
        icon: Icons.edit_note_rounded,
        onPressed: () => _openAdjustDialog(context),
      ),
    ],
    child: const SizedBox.shrink(),
  );

  // -------------------------------------------------------------- history

  Widget _historyCard(BuildContext context) {
    final past = _store.stocktakes.where((s) => !s.isOpen).take(20).toList();
    return SectionCard(
      title: 'Past counts',
      child: AppTable(
        minWidth: 900,
        empty: const EmptyState(
          icon: Icons.fact_check_outlined,
          title: 'No counts finished yet',
          message:
              'A finished count is the record of what was written off '
              'and by whom, so it cannot be edited afterwards.',
        ),
        columns: const [
          DataColumn(label: Text('REFERENCE')),
          DataColumn(label: Text('STARTED')),
          DataColumn(label: Text('FINISHED')),
          DataColumn(label: Text('BY')),
          DataColumn(label: Text('STATUS')),
          DataColumn(label: Text('LINES'), numeric: true),
          DataColumn(label: Text('DIFFERENCES'), numeric: true),
          DataColumn(label: Text('NET EFFECT'), numeric: true),
        ],
        rows: [
          for (final session in past)
            DataRow(
              cells: [
                DataCell(CodeText(session.reference, size: 12)),
                DataCell(Text(AppFormatters.date(session.startedAt))),
                DataCell(
                  Text(
                    session.committedAt == null
                        ? '—'
                        : AppFormatters.date(session.committedAt!),
                  ),
                ),
                DataCell(Text(session.userName)),
                DataCell(
                  StatusPill(
                    session.status.label,
                    tone: session.status == StocktakeStatus.committed
                        ? PillTone.good
                        : PillTone.neutral,
                  ),
                ),
                DataCell(Text('${session.countedLines}')),
                DataCell(Text('${session.discrepancies.length}')),
                DataCell(
                  session.status == StocktakeStatus.committed
                      ? MoneyText(session.netValue, size: 13)
                      : const Text('—'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- behaviour

  void _select(ProductRecord product) {
    setState(() {
      _selected = product;
      _search.text = product.displayName;
      _counted.text = '';
      _error = null;
    });
  }

  /// A wedge scanner types the barcode and presses Enter, so an exact barcode
  /// or SKU match selects straight away and the cursor lands in the count box.
  void _onScan(String value) {
    final query = value.trim().toLowerCase();
    if (query.isEmpty) return;
    final exact = _store.products
        .where(
          (p) =>
              p.barcode.toLowerCase() == query || p.sku.toLowerCase() == query,
        )
        .firstOrNull;
    if (exact != null) _select(exact);
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _store.startStocktake();
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCount(StocktakeRecord session) async {
    final product = _selected;
    if (product == null) return;
    final counted = double.tryParse(_counted.text.trim());
    if (counted == null) {
      setState(() => _error = 'Enter how many you counted.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _store.recordCount(
        stocktakeId: session.id,
        productId: product.id,
        counted: counted,
      );
      if (!mounted) return;
      setState(() {
        _selected = null;
        _search.clear();
        _counted.clear();
      });
      _searchFocus.requestFocus();
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit(StocktakeRecord session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apply this count?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${session.discrepancies.length} of ${session.countedLines} '
                'counted lines differ from the books. Applying the count sets '
                'stock to what you counted and cannot be undone.',
              ),
              const SizedBox(height: 8),
              Text(
                'Net effect on stock value: '
                '${AppFormatters.currency(session.netValue)}',
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Who counted, anything unusual…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final applied = await _store.commitStocktake(
        session.id,
        notes: _notes.text,
      );
      if (!mounted) return;
      _notes.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${applied.reference} applied — '
            '${applied.discrepancies.length} lines adjusted.',
          ),
        ),
      );
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _abandon(StocktakeRecord session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abandon this count?'),
        content: const Text(
          'Everything counted so far is kept for the record, but stock will '
          'not be changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep counting'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abandon'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.abandonStocktake(session.id);
  }

  Future<void> _openAdjustDialog(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => _AdjustDialog(store: _store),
  );
}

/// A single write-off, outside any count.
class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.store});

  final RetailStore store;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _search = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _reason = TextEditingController();
  ProductRecord? _product;
  bool _adding = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matches = query.isEmpty || _product != null
        ? const <ProductRecord>[]
        : widget.store.products
              .where((p) => p.active)
              .where(
                (p) => '${p.name} ${p.sku} ${p.barcode}'.toLowerCase().contains(
                  query,
                ),
              )
              .take(5)
              .toList();

    return AlertDialog(
      title: const Text('Adjust one item'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Item',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() => _product = null),
            ),
            for (final product in matches)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(product.displayName),
                subtitle: Text(
                  'In stock: ${AppFormatters.quantity(product.stock)}',
                ),
                onTap: () => setState(() {
                  _product = product;
                  _search.text = product.displayName;
                }),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Take off'),
                        icon: Icon(Icons.remove),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Add on'),
                        icon: Icon(Icons.add),
                      ),
                    ],
                    selected: {_adding},
                    onSelectionChanged: (s) =>
                        setState(() => _adding = s.first),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'How many'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Why',
                hintText: 'Damaged in the fitting room, given as a sample…',
              ),
            ),
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
        FilledButton(
          onPressed: _product == null || _saving ? null : _save,
          child: const Text('Adjust'),
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
      final magnitude = double.tryParse(_quantity.text.trim()) ?? 0;
      await widget.store.adjustStock(
        productId: _product!.id,
        delta: _adding ? magnitude : -magnitude,
        reason: _reason.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }
}
