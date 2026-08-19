import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';

/// The owner's first look at the day.
///
/// Two rows of figures then three short lists — what sold, what is running
/// out, and who owes money. Everything behind [Permission.viewProfit] is
/// dropped rather than blanked for a cashier, so their dashboard reads as a
/// complete screen rather than a redacted one.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

enum _Period {
  today('Today'),
  week('This week'),
  month('This month');

  const _Period(this.label);
  final String label;
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
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final showProfit = _store.can(Permission.viewProfit);
        final summary = _summary;

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = AppBreakpoints.kpiColumns(constraints.maxWidth);
            final narrow = constraints.maxWidth < AppBreakpoints.laptop;

            return SingleChildScrollView(
              padding: EdgeInsets.all(narrow ? AppSpacing.xl : AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, narrow),
                  const SizedBox(height: AppSpacing.xxl),
                  _kpiGrid(columns, [
                    KpiCard(
                      label: 'Sales',
                      value: AppFormatters.currency(summary.total),
                      caption: '${summary.count} bill(s)',
                      icon: Icons.receipt_long_rounded,
                    ),
                    if (showProfit)
                      KpiCard(
                        label: 'Profit',
                        value: AppFormatters.currency(summary.profit),
                        caption:
                            '${summary.marginPercent.toStringAsFixed(1)}% margin',
                        icon: Icons.trending_up_rounded,
                        tone: AppColors.success,
                      ),
                    if (showProfit)
                      KpiCard(
                        label: 'GST collected',
                        value: AppFormatters.currency(summary.tax),
                        caption: 'Payable to the government',
                        icon: Icons.account_balance_rounded,
                        tone: AppColors.goldDeep,
                      ),
                    KpiCard(
                      label: 'Average bill',
                      value: AppFormatters.currency(summary.averageBill),
                      caption: 'Across ${summary.count} bill(s)',
                      icon: Icons.calculate_rounded,
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.base),
                  _kpiGrid(columns, [
                    KpiCard(
                      label: 'Cash taken',
                      value: AppFormatters.currency(summary.cash),
                      icon: Icons.payments_rounded,
                    ),
                    KpiCard(
                      label: 'Card',
                      value: AppFormatters.currency(summary.card),
                      icon: Icons.credit_card_rounded,
                    ),
                    KpiCard(
                      label: 'UPI',
                      value: AppFormatters.currency(summary.upi),
                      icon: Icons.qr_code_2_rounded,
                    ),
                    KpiCard(
                      label: 'Stock value',
                      value: AppFormatters.currency(_store.inventoryValue),
                      caption: '${_store.products.length} item(s) on hand',
                      icon: Icons.inventory_2_rounded,
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.xxl),
                  _lists(context, narrow, showProfit),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _header(BuildContext context, bool narrow) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 17 ? 'Good afternoon' : 'Good evening');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$greeting, ${_store.currentUser?.name.split(' ').first ?? 'there'}',
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 3),
              Text(
                DateFormat('EEEE, d MMMM y').format(now),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
        if (!narrow)
          SegmentedButton<_Period>(
            segments: [
              for (final p in _Period.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {_period},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
      ],
    );
  }

  Widget _kpiGrid(int columns, List<Widget> cards) {
    final visible = cards.where((c) => true).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.base;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in visible)
              SizedBox(
                width: width > 0 ? width : constraints.maxWidth,
                child: card,
              ),
          ],
        );
      },
    );
  }

  Widget _lists(BuildContext context, bool narrow, bool showProfit) {
    final cards = <Widget>[
      SectionCard(
        title: 'Running low',
        icon: Icons.warning_amber_rounded,
        child: _store.lowStockProducts.isEmpty
            ? const _MiniEmpty('Nothing is running low.')
            : Column(
                children: [
                  for (final p in _store.lowStockProducts.take(6))
                    _MiniRow(
                      label: p.displayName,
                      sub: p.sku,
                      trailing: StockPill(
                        stock: p.stock,
                        minimum: p.minimumStock,
                      ),
                      onTap: () => context.go('/products'),
                    ),
                ],
              ),
      ),
      SectionCard(
        title: 'Money owed to you',
        icon: Icons.account_balance_wallet_outlined,
        child: _store.pendingCustomers.isEmpty
            ? const _MiniEmpty('Nobody owes anything.')
            : Column(
                children: [
                  for (final c in _store.pendingCustomers.take(6))
                    _MiniRow(
                      label: c.name,
                      sub: c.phone,
                      trailing: MoneyText(c.balance, signed: true, size: 13),
                      onTap: () => context.go('/customers'),
                    ),
                ],
              ),
      ),
      SectionCard(
        title: 'Recent bills',
        icon: Icons.receipt_rounded,
        child: _store.sales.isEmpty
            ? const _MiniEmpty('No bills yet today.')
            : Column(
                children: [
                  for (final s in _store.sales.take(6))
                    _MiniRow(
                      label: s.receipt,
                      labelIsCode: true,
                      sub: s.customerName,
                      trailing: MoneyText(s.total, size: 13),
                      onTap: () => context.go('/pos'),
                    ),
                ],
              ),
      ),
    ];

    if (narrow) {
      return Column(
        children: [
          for (final c in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.base),
              child: c,
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          Expanded(child: cards[i]),
          if (i < cards.length - 1) const SizedBox(width: AppSpacing.base),
        ],
      ],
    );
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({
    required this.label,
    required this.trailing,
    this.sub,
    this.onTap,
    this.labelIsCode = false,
  });

  final String label;
  final String? sub;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool labelIsCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.input),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  labelIsCode
                      ? CodeText(label)
                      : Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                  if ((sub ?? '').isNotEmpty)
                    Text(
                      sub!,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _MiniEmpty extends StatelessWidget {
  const _MiniEmpty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Text(
      message,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppColors.inkFaint),
    ),
  );
}
