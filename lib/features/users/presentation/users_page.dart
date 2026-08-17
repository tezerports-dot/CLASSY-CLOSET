import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/widgets/section_card.dart';
import 'widgets/user_form_dialog.dart';

/// Staff accounts and what each role is allowed to do.
class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SectionCard(
              title: 'Staff',
              actions: [
                FilledButton.icon(
                  onPressed: () => _openForm(context, store),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add staff'),
                ),
              ],
              child: Column(
                children: [
                  for (final user in store.users)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(
                          user.name.isEmpty
                              ? '?'
                              : user.name.characters.first.toUpperCase(),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(user.name),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(user.role.label),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          if (!user.isActive) ...[
                            const SizedBox(width: 6),
                            Chip(
                              label: const Text('Disabled'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                            ),
                          ],
                          if (user.id == store.currentUser?.id) ...[
                            const SizedBox(width: 6),
                            const Chip(
                              label: Text('You'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        '${user.username} · ${user.role.description}',
                      ),
                      trailing: TextButton.icon(
                        onPressed: () => _openForm(context, store, user),
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'What each role can do',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('Can…')),
                    for (final role in AppRole.values)
                      DataColumn(label: Text(role.label)),
                  ],
                  rows: [
                    for (final permission in Permission.values)
                      DataRow(
                        cells: [
                          DataCell(Text(_permissionLabel(permission))),
                          for (final role in AppRole.values)
                            DataCell(
                              permissionsFor(role).contains(permission)
                                  ? Icon(
                                      Icons.check_circle,
                                      size: 18,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    )
                                  : Icon(
                                      Icons.remove,
                                      size: 18,
                                      color: Theme.of(context).disabledColor,
                                    ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    RetailStore store, [
    AppUser? user,
  ]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => UserFormDialog(store: store, user: user),
    );
  }
}

String _permissionLabel(Permission permission) => switch (permission) {
  Permission.viewDashboard => 'Open the dashboard',
  Permission.viewProfit => 'See profit, margin and GST totals',
  Permission.sellAtPos => 'Ring up a sale',
  Permission.giveDiscount => 'Give a discount',
  Permission.viewProducts => 'See the catalogue',
  Permission.editProducts => 'Add or change designs and stock',
  Permission.viewCustomers => 'See customers',
  Permission.editCustomers => 'Add or change customers',
  Permission.viewSuppliers => 'See suppliers',
  Permission.editSuppliers => 'Add or change suppliers',
  Permission.viewReports => 'Open reports',
  Permission.manageSettings => 'Change settings and GST rates',
  Permission.manageUsers => 'Manage staff accounts',
  Permission.backupRestore => 'Back up and restore',
  Permission.processReturns => 'Take goods back and refund',
  Permission.manageShift => 'Open and close the till',
  Permission.recordPurchases => 'Receive stock from a supplier',
  Permission.recordExpenses => 'Record what the shop spent',
  Permission.recordPayments => 'Settle a customer or supplier balance',
};
