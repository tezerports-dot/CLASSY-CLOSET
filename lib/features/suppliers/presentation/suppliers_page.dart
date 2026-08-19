import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/services/statements.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../parties/presentation/widgets/party_actions.dart';
import 'widgets/supplier_form_dialog.dart';

/// Who the stock comes from, and what is still owed for it.
class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final _store = getIt<RetailStore>();
  final _search = TextEditingController();
  bool _owingOnly = false;

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
        final all = _store.suppliers;
        final rows = all
            .where(
              (s) => '${s.name} ${s.phone} ${s.email}'.toLowerCase().contains(
                query,
              ),
            )
            .where((s) => !_owingOnly || s.balance > 0)
            .toList();
        final owed = all.fold(
          0.0,
          (sum, s) => sum + (s.balance > 0 ? s.balance : 0),
        );
        final owingCount = all.where((s) => s.balance > 0).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Suppliers',
                subtitle:
                    '${all.length} on the books'
                    '${owingCount > 0 ? '  ·  $owingCount to pay' : ''}',
                actions: [
                  if (_store.can(Permission.editSuppliers))
                    AccentButton(
                      label: 'Add supplier',
                      icon: Icons.local_shipping_outlined,
                      onPressed: () => _openForm(),
                    ),
                ],
              ),

              if (owed > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: KpiCard(
                        label: 'Owed to suppliers',
                        value: AppFormatters.currency(owed),
                        caption:
                            'Across $owingCount account'
                            '${owingCount == 1 ? '' : 's'}',
                        icon: Icons.receipt_long_outlined,
                        tone: AppColors.danger,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    const Spacer(flex: 2),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
              ],

              SectionCard(
                title: 'Supplier ledger',
                subtitle:
                    'Click a name to edit it, or use the buttons on the right '
                    'to record a payment or print a statement.',
                actions: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                        hintText: 'Name, phone or email',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilterChip(
                    label: const Text('To pay only'),
                    selected: _owingOnly,
                    showCheckmark: false,
                    selectedColor: AppColors.goldWash,
                    onSelected: (v) => setState(() => _owingOnly = v),
                  ),
                ],
                child: AppTable(
                  minWidth: 820,
                  columns: const [
                    DataColumn(label: Text('NAME')),
                    DataColumn(label: Text('PHONE')),
                    DataColumn(label: Text('EMAIL')),
                    DataColumn(label: Text('OWED TO THEM'), numeric: true),
                    DataColumn(label: Text('')),
                  ],
                  empty: _emptyState(all.isEmpty, query),
                  rows: [
                    for (final s in rows)
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              s.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: _store.can(Permission.editSuppliers)
                                ? () => _openForm(s)
                                : null,
                          ),
                          DataCell(
                            s.phone.isEmpty
                                ? const Text('—')
                                : CodeText(s.phone, size: 12),
                          ),
                          DataCell(Text(s.email.isEmpty ? '—' : s.email)),
                          DataCell(
                            s.balance == 0
                                ? const StatusPill(
                                    'Settled',
                                    tone: PillTone.good,
                                  )
                                : MoneyText(
                                    s.balance,
                                    size: 13,
                                    weight: FontWeight.w600,
                                    tone: s.balance > 0
                                        ? AppColors.danger
                                        : AppColors.success,
                                  ),
                          ),
                          DataCell(
                            PartyActions(
                              store: _store,
                              kind: PartyKind.supplier,
                              partyId: s.id,
                              partyName: s.name,
                              outstanding: s.balance,
                            ),
                          ),
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

  Widget _emptyState(bool noneAtAll, String query) {
    if (noneAtAll) {
      return EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No suppliers yet',
        message:
            'Add the wholesalers you buy from, and every purchase you record '
            'builds up their account here.',
        action: _store.can(Permission.editSuppliers)
            ? AccentButton(
                label: 'Add supplier',
                icon: Icons.add_rounded,
                onPressed: () => _openForm(),
              )
            : null,
      );
    }
    if (_owingOnly && query.isEmpty) {
      return EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing outstanding',
        message: 'Every supplier account is settled.',
        action: SecondaryButton(
          label: 'Show all suppliers',
          onPressed: () => setState(() => _owingOnly = false),
        ),
      );
    }
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'No supplier matches that search',
      message: 'Try part of the name or the phone number.',
      action: SecondaryButton(
        label: 'Clear search',
        onPressed: () => setState(() {
          _search.clear();
          _owingOnly = false;
        }),
      ),
    );
  }

  Future<void> _openForm([SupplierRecord? supplier]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => SupplierFormDialog(store: _store, supplier: supplier),
    );
  }
}
