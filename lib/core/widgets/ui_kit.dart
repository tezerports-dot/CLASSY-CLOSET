/// The pieces every screen is assembled from.
///
/// One definition each, so a status pill on the till looks like a status pill
/// on the reports screen and a change here reaches the whole app.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';

// ------------------------------------------------------------------- pills

/// What a pill is saying.
enum PillTone {
  /// Paid, settled, in stock, balanced.
  good,

  /// Low stock, pending, partial.
  caution,

  /// Out of stock, money owed, refunds.
  bad,

  /// Nothing in particular.
  neutral,

  /// A category or code — the darkest, quietest form.
  strong,
}

extension _PillColors on PillTone {
  Color get fg => switch (this) {
    PillTone.good => AppColors.success,
    PillTone.caution => AppColors.warn,
    PillTone.bad => AppColors.danger,
    PillTone.neutral => AppColors.inkSoft,
    PillTone.strong => AppColors.brandInk,
  };

  Color get bg => switch (this) {
    PillTone.good => AppColors.successWash,
    PillTone.caution => AppColors.warnWash,
    PillTone.bad => AppColors.dangerWash,
    PillTone.neutral => AppColors.surfaceAlt,
    PillTone.strong => AppColors.brand,
  };
}

/// A small state label — "In stock", "Owed", "Applied".
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = PillTone.neutral});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: tone.bg,
      borderRadius: AppRadii.pillBorder,
      border: Border.all(
        color: tone == PillTone.neutral ? AppColors.border : Colors.transparent,
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: tone.fg,
        height: 1.25,
      ),
    ),
  );
}

/// The stock pill, so "how many left" reads the same everywhere.
class StockPill extends StatelessWidget {
  const StockPill({super.key, required this.stock, this.minimum = 0});

  final double stock;
  final double minimum;

  @override
  Widget build(BuildContext context) {
    if (stock <= 0) return const StatusPill('Out of stock', tone: PillTone.bad);
    if (stock <= (minimum > 0 ? minimum : 2)) {
      return StatusPill(
        '${AppFormatters.quantity(stock)} left',
        tone: PillTone.caution,
      );
    }
    return StatusPill(
      '${AppFormatters.quantity(stock)} in stock',
      tone: PillTone.good,
    );
  }
}

// ------------------------------------------------------------------- money

/// A rupee amount, tabular so columns of them line up.
///
/// Money is the product here, so it gets its own widget rather than being
/// formatted inline and drifting screen to screen.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.style,
    this.size,
    this.weight,
    this.tone,
    this.signed = false,
    this.symbol = true,
  });

  final double amount;
  final TextStyle? style;
  final double? size;
  final FontWeight? weight;
  final Color? tone;

  /// Show a leading − and colour it as a deduction. Used for discounts,
  /// refunds and anything owed.
  final bool signed;
  final bool symbol;

  @override
  Widget build(BuildContext context) {
    final negative = amount < 0 || signed;
    final text = symbol
        ? AppFormatters.currency(amount.abs())
        : AppFormatters.amount(amount.abs());
    return Text(
      '${negative && amount != 0 ? '−' : ''}$text',
      style: (style ?? AppTypography.money).copyWith(
        fontFamily: AppTypography.sans,
        fontFeatures: AppTypography.tabular,
        fontSize: size,
        fontWeight: weight,
        color: tone ?? (negative && amount != 0 ? AppColors.danger : null),
      ),
    );
  }
}

/// A SKU, invoice number or GSTIN — fixed advance, so it scans by eye.
class CodeText extends StatelessWidget {
  const CodeText(this.value, {super.key, this.size, this.color});

  final String value;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: AppTypography.code.copyWith(fontSize: size, color: color),
  );
}

// ------------------------------------------------------------------- cards

/// A titled white panel. Nearly every screen is a stack of these.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.padding = const EdgeInsets.all(AppSpacing.xl),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadii.cardBorder,
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                AppSpacing.lg,
                padding.right,
                subtitle == null ? AppSpacing.base : AppSpacing.md,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: AppColors.goldDeep),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title!, style: theme.textTheme.titleLarge),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.inkFaint,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          if (title != null) const Divider(height: 1),
          Padding(
            padding: title == null
                ? padding
                : padding.copyWith(top: AppSpacing.xl),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// One figure on the dashboard.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadii.cardBorder,
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: tone ?? AppColors.goldDeep),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.kpi.copyWith(color: tone ?? AppColors.ink),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              caption!,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.inkFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- buttons

/// The gold one. Exactly one per screen — the thing the counter is there to do.
class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.tall = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  /// 48px — the checkout button, which is aimed at from across the counter.
  final bool tall;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.inkFaint,
        minimumSize: Size(0, tall ? 48 : 40),
        textStyle: TextStyle(
          fontFamily: AppTypography.sans,
          fontSize: tall ? 14.5 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.ink,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 17),
          if (busy || icon != null) const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// The dark one. Ordinary primary actions.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const SizedBox.square(
            dimension: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.brandInk,
            ),
          )
        else if (icon != null)
          Icon(icon, size: 16),
        if (busy || icon != null) const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    ),
  );
}

/// The white one with a border. Everything secondary.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(foregroundColor: tone),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16),
          const SizedBox(width: AppSpacing.xs),
        ],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

// ------------------------------------------------------------------ states

/// Nothing here yet — with the one thing to do about it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: 40,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: AppColors.goldWash,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: AppColors.goldDeep),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.inkFaint,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Something went wrong, what it was, and what to do about it.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.error_outline,
  });

  final String title;
  final String message;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: AppColors.dangerWash,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: AppColors.danger),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.inkFaint,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Skeleton rows rather than a spinner: the shape of what is coming reads as
/// progress, where a spinner reads as a stall.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.rows = 6, this.height = 44});

  final int rows;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < rows; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.input),
            ),
          ),
        ),
    ],
  );
}

/// The banner that says the shop is fine without a connection.
///
/// Worded to reassure rather than alarm: this app is offline by design, so an
/// absent network is normal operation, not a fault.
class OfflineNotice extends StatelessWidget {
  const OfflineNotice({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.base,
    ),
    decoration: BoxDecoration(
      color: AppColors.goldWash,
      border: Border.all(color: AppColors.goldWashBorder),
      borderRadius: AppRadii.inputBorder,
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off, size: 17, color: AppColors.goldDeep),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            message ??
                'Working offline. Everything is saved on this PC — that is '
                    'how the shop is meant to run.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.goldDeep),
          ),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ tables

/// A page heading with its actions.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.headlineLarge),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Wrap(spacing: AppSpacing.sm, children: actions),
        ],
      ),
    );
  }
}

/// The table shell: horizontal scroll on narrow screens, and the three states
/// baked in so no screen can forget them.
class AppTable extends StatelessWidget {
  const AppTable({
    super.key,
    required this.columns,
    required this.rows,
    this.loading = false,
    this.empty,
    this.minWidth = 720,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;
  final bool loading;
  final Widget? empty;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: SkeletonRows(),
      );
    }
    if (rows.isEmpty && empty != null) return empty!;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : minWidth,
          ),
          child: DataTable(
            columns: columns,
            rows: rows,
            border: const TableBorder(
              horizontalInside: BorderSide(color: AppColors.borderSoft),
            ),
          ),
        ),
      ),
    );
  }
}
