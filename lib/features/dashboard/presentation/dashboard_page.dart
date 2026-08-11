import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final cards = [
          (
            'Today\'s Sales',
            AppFormatters.currency(store.todaySales),
            Icons.point_of_sale,
            AppColors.accent,
          ),
          (
            'Today\'s Profit',
            AppFormatters.currency(store.todayProfit),
            Icons.trending_up,
            AppColors.success,
          ),
          (
            'Inventory Value',
            AppFormatters.currency(store.inventoryValue),
            Icons.inventory,
            AppColors.warning,
          ),
          (
            'Open Balances',
            AppFormatters.currency(
              store.pendingCustomers.fold(0.0, (sum, c) => sum + c.balance),
            ),
            Icons.payments,
            AppColors.danger,
          ),
          (
            'Customers',
            store.customers.length.toString(),
            Icons.people,
            AppColors.textSecondary,
          ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good day, ${store.currentUser?.name ?? 'Admin'}',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(AppFormatters.dateTime(DateTime.now())),
              const SizedBox(height: 24),
              GridView.count(
                crossAxisCount: 5,
                crossAxisSpacing: 16,
                shrinkWrap: true,
                childAspectRatio: 1.45,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final card in cards)
                    _KpiCard(
                      label: card.$1,
                      value: card.$2,
                      icon: card.$3,
                      color: card.$4,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SectionCard(
                      title: 'Low Stock Alerts',
                      child: _ProductList(
                        products: store.lowStockProducts.toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SectionCard(
                      title: 'Pending Payments',
                      child: _CustomerList(
                        customers: store.pendingCustomers.toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SectionCard(
                      title: 'Recent Transactions',
                      child: _SalesList(sales: store.sales.take(10).toList()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    ),
  );
}

class _ProductList extends StatelessWidget {
  const _ProductList({required this.products});
  final List<ProductRecord> products;
  @override
  Widget build(BuildContext context) => products.isEmpty
      ? const Text('No low stock items')
      : Column(
          children: [
            for (final p in products)
              ListTile(
                dense: true,
                title: Text(p.name),
                trailing: Text('${p.stock}/${p.minimumStock}'),
              ),
          ],
        );
}

class _CustomerList extends StatelessWidget {
  const _CustomerList({required this.customers});
  final List<CustomerRecord> customers;
  @override
  Widget build(BuildContext context) => customers.isEmpty
      ? const Text('No outstanding balances')
      : Column(
          children: [
            for (final c in customers)
              ListTile(
                dense: true,
                title: Text(c.name),
                trailing: Text(AppFormatters.currency(c.balance)),
              ),
          ],
        );
}

class _SalesList extends StatelessWidget {
  const _SalesList({required this.sales});
  final List<SaleRecord> sales;
  @override
  Widget build(BuildContext context) => sales.isEmpty
      ? const Text('No sales yet')
      : Column(
          children: [
            for (final s in sales)
              ListTile(
                dense: true,
                title: Text(s.receipt),
                subtitle: Text(s.customerName),
                trailing: Text(AppFormatters.currency(s.total)),
              ),
          ],
        );
}
