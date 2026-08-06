import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return AnimatedBuilder(animation: store, builder: (context, _) => Padding(padding: const EdgeInsets.all(24), child: SectionCard(title: 'Suppliers', child: DataTable(columns: const [DataColumn(label: Text('Name')), DataColumn(label: Text('Phone')), DataColumn(label: Text('Email')), DataColumn(label: Text('Balance'))], rows: [for (final s in store.suppliers) DataRow(cells: [DataCell(Text(s.name)), DataCell(Text(s.phone)), DataCell(Text(s.email)), DataCell(Text(AppFormatters.currency(s.balance)))])]))));
  }
}
