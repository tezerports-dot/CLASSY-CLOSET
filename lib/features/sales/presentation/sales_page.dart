import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/search.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../pos/presentation/widgets/bill_preview_dialog.dart';

/// Every bill this shop has ever rung up, one row per bill.
///
/// The counter had no way to pull up a past bill by number until now — the
/// return desk could load one, but only if the customer's copy was in hand.
/// This page lets the shop look one up by invoice, by customer, or by any of
/// the fields printed on the roll, and drills into a printable copy so it can
/// be reprinted or scanned into the customer's email.
class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _store = getIt<RetailStore>();
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    // A search typed into the top-bar global box lands on the receipt list
    // pre-populated, then clears so a back-and-forth navigation does not
    // keep re-seeding it.
    _search = TextEditingController(text: _store.consumePendingGlobalQuery());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final query = _search.text.trim().toLowerCase();
        final rows = _store.sales
            .where(
              (s) => AppSearch.matches(
                '${s.receipt} ${s.customerName} '
                '${s.paymentReference ?? ''} ${s.paymentMethod}',
                query,
              ),
            )
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Bills',
                subtitle:
                    '${_store.sales.length} bill'
                    "${_store.sales.length == 1 ? '' : 's'} in the ledger. "
                    'Click any row to open the full bill.',
              ),
              SectionCard(
                title: 'Recent bills',
                subtitle: _store.sales.length > 200
                    ? 'The 200 most recent.'
                    : null,
                actions: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        hintText:
                            'Invoice number, customer, or transaction ref',
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () => setState(_search.clear),
                              ),
                      ),
                    ),
                  ),
                ],
                child: AppTable(
                  minWidth: 940,
                  columns: const [
                    DataColumn(label: Text('INVOICE')),
                    DataColumn(label: Text('WHEN')),
                    DataColumn(label: Text('CUSTOMER')),
                    DataColumn(label: Text('METHOD')),
                    DataColumn(label: Text('REFERENCE')),
                    DataColumn(label: Text('TOTAL'), numeric: true),
                  ],
                  empty: EmptyState(
                    icon: _store.sales.isEmpty
                        ? Icons.receipt_long_rounded
                        : Icons.search_off_rounded,
                    title: _store.sales.isEmpty
                        ? 'No bills yet'
                        : 'Nothing matches "${_search.text.trim()}"',
                    message: _store.sales.isEmpty
                        ? 'Rung-up bills appear here in reverse date order. '
                              'The list is one click away from the printed '
                              'copy for a re-print.'
                        : 'Try the last few digits of the invoice, or the '
                              'customer\'s name.',
                    action: _store.sales.isEmpty || query.isEmpty
                        ? null
                        : SecondaryButton(
                            label: 'Clear search',
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                  rows: [
                    for (final sale in rows.take(200))
                      DataRow(
                        cells: [
                          DataCell(
                            CodeText(sale.receipt, size: 12),
                            onTap: () => _openBill(sale),
                          ),
                          DataCell(
                            Text(AppFormatters.dateTime(sale.createdAt)),
                          ),
                          DataCell(Text(sale.customerName)),
                          DataCell(_MethodPill(method: sale.paymentMethod)),
                          DataCell(
                            (sale.paymentReference ?? '').isEmpty
                                ? const Text(
                                    '—',
                                    style: TextStyle(color: AppColors.inkFaint),
                                  )
                                : CodeText(sale.paymentReference!, size: 12),
                          ),
                          DataCell(MoneyText(sale.total, size: 13)),
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

  Future<void> _openBill(SaleRecord sale) async {
    final invoice = await _store.loadInvoiceForReceipt(sale.receipt);
    if (!mounted) return;
    if (invoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load ${sale.receipt}.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => BillPreviewDialog(
        invoice: invoice,
        settings: _store.printerSettings,
        // Re-printing straight from the bills list would need the whole
        // deliver-receipt plumbing — the on-screen preview already carries
        // its own print button through the print dialog, which is the safe
        // route for a reprint anyway.
        onPrint: null,
      ),
    );
  }
}

/// A small pill that names how a bill was paid at a glance.
class _MethodPill extends StatelessWidget {
  const _MethodPill({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final label = switch (method) {
      'cash' => 'Cash',
      'card' => 'Card',
      'upi' => 'UPI',
      'split' => 'Split',
      _ => method,
    };
    final tone = switch (method) {
      'cash' => PillTone.good,
      'card' || 'upi' => PillTone.strong,
      'split' => PillTone.caution,
      _ => PillTone.neutral,
    };
    return StatusPill(label, tone: tone);
  }
}
