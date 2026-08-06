import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Row(children: [
            Expanded(child: SectionCard(title: 'Sales Summary', child: _Metric(label: 'Today Sales', value: AppFormatters.currency(store.todaySales)))),
            const SizedBox(width: 16),
            Expanded(child: SectionCard(title: 'Profit Summary', child: _Metric(label: 'Today Profit', value: AppFormatters.currency(store.todayProfit)))),
            const SizedBox(width: 16),
            Expanded(child: SectionCard(title: 'Inventory Summary', child: _Metric(label: 'Stock Value', value: AppFormatters.currency(store.inventoryValue)))),
          ]),
          const SizedBox(height: 16),
          SectionCard(title: 'Audit Log', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final log in store.auditLogs.take(20)) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(log))])),
        ]),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: Theme.of(context).textTheme.headlineMedium), Text(label)]);
}
