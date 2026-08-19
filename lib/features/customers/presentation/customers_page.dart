import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/services/statements.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../parties/presentation/widgets/party_actions.dart';
import 'widgets/customer_form_dialog.dart';

/// Who buys here, and who still owes for it.
///
/// A regular running a monthly account is normal in this trade, so the balance
/// column is the point of the screen — not an afterthought behind a menu.
class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _store = getIt<RetailStore>();
  final _search = TextEditingController();

  /// Show only the accounts with money still on them.
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
        final all = _store.customers;
        final rows = all
            .where(
              (c) => '${c.name} ${c.phone} ${c.email}'.toLowerCase().contains(
                query,
              ),
            )
            .where((c) => !_owingOnly || c.balance > 0)
            .toList();
        final owed = all.fold(
          0.0,
          (sum, c) => sum + (c.balance > 0 ? c.balance : 0),
        );
        final owingCount = all.where((c) => c.balance > 0).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Customers',
                subtitle:
                    '${all.length} on the books'
                    '${owingCount > 0 ? '  ·  $owingCount owing' : ''}',
                actions: [
                  if (_store.can(Permission.editCustomers))
                    AccentButton(
                      label: 'Add customer',
                      icon: Icons.person_add_alt_rounded,
                      onPressed: () => _openForm(),
                    ),
                ],
              ),

              if (owed > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: KpiCard(
                        label: 'Owed to the shop',
                        value: AppFormatters.currency(owed),
                        caption:
                            'Across $owingCount account'
                            '${owingCount == 1 ? '' : 's'}',
                        icon: Icons.account_balance_wallet_outlined,
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
                title: 'Customer ledger',
                subtitle:
                    'Click a name to edit it, or use the buttons on the right '
                    'to take a payment or print a statement.',
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
                    label: const Text('Owing only'),
                    selected: _owingOnly,
                    showCheckmark: false,
                    selectedColor: AppColors.goldWash,
                    onSelected: (v) => setState(() => _owingOnly = v),
                  ),
                ],
                child: AppTable(
                  minWidth: 900,
                  columns: const [
                    DataColumn(label: Text('NAME')),
                    DataColumn(label: Text('PHONE')),
                    DataColumn(label: Text('EMAIL')),
                    DataColumn(label: Text('CREDIT LIMIT'), numeric: true),
                    DataColumn(label: Text('OUTSTANDING'), numeric: true),
                    DataColumn(label: Text('')),
                  ],
                  empty: _emptyState(all.isEmpty, query),
                  rows: [
                    for (final c in rows)
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              c.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: _store.can(Permission.editCustomers)
                                ? () => _openForm(c)
                                : null,
                          ),
                          DataCell(
                            c.phone.isEmpty
                                ? const Text('—')
                                : CodeText(c.phone, size: 12),
                          ),
                          DataCell(Text(c.email.isEmpty ? '—' : c.email)),
                          DataCell(
                            c.creditLimit <= 0
                                ? const Text('—')
                                : MoneyText(c.creditLimit, size: 13),
                          ),
                          DataCell(
                            c.balance == 0
                                ? const StatusPill(
                                    'Settled',
                                    tone: PillTone.good,
                                  )
                                : MoneyText(
                                    c.balance,
                                    size: 13,
                                    weight: FontWeight.w600,
                                    tone: c.balance > 0
                                        ? AppColors.danger
                                        : AppColors.success,
                                  ),
                          ),
                          DataCell(
                            PartyActions(
                              store: _store,
                              kind: PartyKind.customer,
                              partyId: c.id,
                              partyName: c.name,
                              outstanding: c.balance,
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
        icon: Icons.people_outline_rounded,
        title: 'No customers yet',
        message:
            'Add a customer to keep a running account for them, or carry on '
            'billing walk-ins without one.',
        action: _store.can(Permission.editCustomers)
            ? AccentButton(
                label: 'Add customer',
                icon: Icons.person_add_alt_rounded,
                onPressed: () => _openForm(),
              )
            : null,
      );
    }
    if (_owingOnly && query.isEmpty) {
      return EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Everyone has settled up',
        message: 'No customer is carrying a balance right now.',
        action: SecondaryButton(
          label: 'Show all customers',
          onPressed: () => setState(() => _owingOnly = false),
        ),
      );
    }
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'Nobody matches that search',
      message:
          'Try part of the name or the last few digits of the phone number.',
      action: SecondaryButton(
        label: 'Clear search',
        onPressed: () => setState(() {
          _search.clear();
          _owingOnly = false;
        }),
      ),
    );
  }

  Future<void> _openForm([CustomerRecord? customer]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => CustomerFormDialog(store: _store, customer: customer),
    );
  }
}
