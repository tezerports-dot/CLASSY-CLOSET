import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';
import 'widgets/supplier_form_dialog.dart';

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: SectionCard(
          title: 'Suppliers',
          actions: [FilledButton.icon(onPressed: () => _openForm(context, store), icon: const Icon(Icons.add), label: const Text('Add supplier'))],
          child: DataTable(
            columns: const [DataColumn(label: Text('Name')), DataColumn(label: Text('Phone')), DataColumn(label: Text('Email')), DataColumn(label: Text('Balance'))],
            rows: [
              for (final s in store.suppliers)
                DataRow(cells: [
                  DataCell(InkWell(onTap: () => _openForm(context, store, s), child: Text(s.name))),
                  DataCell(Text(s.phone)),
                  DataCell(Text(s.email)),
                  DataCell(Text(AppFormatters.currency(s.balance))),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, RetailStore store, [SupplierRecord? supplier]) async {
    await showDialog<void>(context: context, builder: (_) => SupplierFormDialog(store: store, supplier: supplier));
  }
}
