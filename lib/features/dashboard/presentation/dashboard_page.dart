import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _store = getIt<RetailStore>();
  _Period _period = _Period.today;

  SalesSummary get _summary => switch (_period) {
    _Period.today => _store.todaySummary,
    _Period.week => _store.weekSummary,
    _Period.month => _store.monthSummary,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final summary = _summary;
        final showProfit = _store.can(Permission.viewProfit);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good day, ${_store.currentUser?.name ?? 'Admin'}',
                          style: theme.textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(AppFormatters.dateTime(DateTime.now())),
                      ],
                    ),
                  ),
                  SegmentedButton<_Period>(
                    segments: const [
                      ButtonSegment(value: _Period.today, label: Text('Today')),
                      ButtonSegment(value: _Period.week, label: Text('Week')),
                      ButtonSegment(value: _Period.month, label: Text('Month')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (s) =>
                        setState(() => _period = s.single),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Headline figures. Profit and GST are the owner's business, so
              // they only appear for a user who holds viewProfit — a cashier
              // still sees takings, which is what they need to reconcile.
              _CardRow(
                children: [
                  _Kpi(
                    label: '${_period.label} sales',
                    value: AppFormatters.currency(summary.total),
                    caption: '${summary.count} bill(s)',
                    icon: Icons.point_of_sale,
                    color: AppColors.accent,
                  ),
                  if (showProfit)
                    _Kpi(
                      label: '${_period.label} profit',
                      value: AppFormatters.currency(summary.profit),
                      caption:
                          '${summary.marginPercent.toStringAsFixed(1)}% margin',
                      icon: Icons.trending_up,
                      color: AppColors.success,
                    ),
                  if (showProfit)
                    _Kpi(
                      label: 'GST collected',
                      value: AppFormatters.currency(summary.tax),
                      caption: 'payable to government',
                      icon: Icons.receipt_long,
                      color: AppColors.warning,
                    ),
                  _Kpi(
                    label: 'Average bill',
                    value: AppFormatters.currency(summary.averageBill),
                    caption: '${_period.label.toLowerCase()} average',
                    icon: Icons.shopping_bag,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // How the money actually arrived — this is what gets counted
              // against the drawer at close of day.
              _CardRow(
                children: [
                  _Kpi(
                    label: 'Cash taken',
                    value: AppFormatters.currency(summary.cash),
                    caption: 'count this against the drawer',
                    icon: Icons.payments,
                    color: AppColors.success,
                  ),
                  _Kpi(
                    label: 'Card',
                    value: AppFormatters.currency(summary.card),
                    caption: 'settles to the bank',
                    icon: Icons.credit_card,
                    color: AppColors.accent,
                  ),
                  _Kpi(
                    label: 'UPI',
                    value: AppFormatters.currency(summary.upi),
                    caption: 'settles to the bank',
                    icon: Icons.qr_code_2,
                    color: AppColors.accent,
                  ),
                  if (showProfit)
                    _Kpi(
                      label: 'Stock value',
                      value: AppFormatters.currency(_store.inventoryValue),
                      caption: '${_store.products.length} unit(s) on hand',
                      icon: Icons.inventory_2,
                      color: AppColors.warning,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SectionCard(
                      title: 'Low stock',
                      child: _ProductList(
                        products: _store.lowStockProducts.take(10).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SectionCard(
                      title: 'Money owed to you',
                      child: _CustomerList(
                        customers: _store.pendingCustomers.take(10).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SectionCard(
                      title: 'Recent bills',
                      child: _SalesList(sales: _store.sales.take(10).toList()),
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

enum _Period {
  today('Today'),
  week('This week'),
  month('This month');

  const _Period(this.label);
  final String label;
}

/// Lays KPI cards out in an even row that wraps on a narrow window.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 16.0;
      final perRow = constraints.maxWidth < 900 ? 2 : children.length;
      final width = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: theme.textTheme.headlineMedium),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({required this.products});
  final List<ProductRecord> products;

  @override
  Widget build(BuildContext context) => products.isEmpty
      ? const Text('Nothing running low.')
      : Column(
          children: [
            for (final p in products)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.displayName),
                trailing: Text(
                  '${AppFormatters.quantity(p.stock)} left',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        );
}

class _CustomerList extends StatelessWidget {
  const _CustomerList({required this.customers});
  final List<CustomerRecord> customers;

  @override
  Widget build(BuildContext context) => customers.isEmpty
      ? const Text('Nothing outstanding.')
      : Column(
          children: [
            for (final c in customers)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
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
      ? const Text('No bills yet.')
      : Column(
          children: [
            for (final s in sales)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(s.receipt),
                subtitle: Text(
                  '${s.customerName} · ${AppFormatters.date(s.createdAt)}',
                ),
                trailing: Text(AppFormatters.currency(s.total)),
              ),
          ],
        );
}
