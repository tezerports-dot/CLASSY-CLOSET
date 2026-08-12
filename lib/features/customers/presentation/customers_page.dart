import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';
import 'widgets/customer_form_dialog.dart';

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: SectionCard(
          title: 'Customers & Ledger',
          actions: [
            if (store.can(Permission.editCustomers))
              FilledButton.icon(
                onPressed: () => _openForm(context, store),
                icon: const Icon(Icons.add),
                label: const Text('Add customer'),
              ),
          ],
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Phone')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('Credit Limit')),
              DataColumn(label: Text('Outstanding')),
            ],
            rows: [
              for (final c in store.customers)
                DataRow(
                  cells: [
                    DataCell(
                      InkWell(
                        onTap: () => _openForm(context, store, c),
                        child: Text(c.name),
                      ),
                    ),
                    DataCell(Text(c.phone)),
                    DataCell(Text(c.email)),
                    DataCell(Text(AppFormatters.currency(c.creditLimit))),
                    DataCell(Text(AppFormatters.currency(c.balance))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    RetailStore store, [
    CustomerRecord? customer,
  ]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => CustomerFormDialog(store: store, customer: customer),
    );
  }
}
