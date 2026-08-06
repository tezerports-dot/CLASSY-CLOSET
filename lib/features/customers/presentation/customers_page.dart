import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return AnimatedBuilder(animation: store, builder: (context, _) => Padding(padding: const EdgeInsets.all(24), child: SectionCard(title: 'Customers & Ledger', actions: [FilledButton.icon(onPressed: () => store.addCustomer(CustomerRecord(id: store.customers.length + 1, name: 'New Customer ${store.customers.length + 1}', phone: '555-0000', email: 'new@example.com', creditLimit: 250)), icon: const Icon(Icons.add), label: const Text('Add customer'))], child: DataTable(columns: const [DataColumn(label: Text('Name')), DataColumn(label: Text('Phone')), DataColumn(label: Text('Email')), DataColumn(label: Text('Credit Limit')), DataColumn(label: Text('Outstanding'))], rows: [for (final c in store.customers) DataRow(cells: [DataCell(Text(c.name)), DataCell(Text(c.phone)), DataCell(Text(c.email)), DataCell(Text(AppFormatters.currency(c.creditLimit))), DataCell(Text(AppFormatters.currency(c.balance)))])]))));
  }
}
