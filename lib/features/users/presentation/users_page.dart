import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/ui_kit.dart';
import 'widgets/user_form_dialog.dart';

/// Staff accounts and what each role is allowed to do.
///
/// The permission matrix is on the same screen as the accounts on purpose: the
/// question "what will this person be able to do?" is answered before the
/// account is created, not after something has gone missing.
class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final active = store.users.where((u) => u.isActive).length;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Staff',
                subtitle:
                    '$active active account${active == 1 ? '' : 's'}'
                    '${store.users.length > active ? '  ·  ${store.users.length - active} disabled' : ''}',
                actions: [
                  AccentButton(
                    label: 'Add staff',
                    icon: Icons.person_add_alt_rounded,
                    onPressed: () => _openForm(context, store),
                  ),
                ],
              ),

              SectionCard(
                title: 'Accounts',
                subtitle:
                    'Every bill, refund and stock change is stamped with who '
                    'was signed in, so each person needs their own login.',
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.lg,
                ),
                child: store.users.isEmpty
                    ? EmptyState(
                        icon: Icons.badge_outlined,
                        title: 'No staff accounts',
                        message:
                            'Add an account for each person who works the '
                            'counter.',
                        action: AccentButton(
                          label: 'Add staff',
                          icon: Icons.person_add_alt_rounded,
                          onPressed: () => _openForm(context, store),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < store.users.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _userTile(context, store, store.users[i]),
                          ],
                        ],
                      ),
              ),

              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: 'What each role can do',
                subtitle:
                    'Roles are fixed so they cannot be edited into something '
                    'unsafe. Pick the one that matches the job.',
                child: AppTable(
                  minWidth: 720,
                  columns: [
                    const DataColumn(label: Text('CAN…')),
                    for (final role in AppRole.values)
                      DataColumn(label: Text(role.label.toUpperCase())),
                  ],
                  rows: [
                    for (final permission in Permission.values)
                      DataRow(
                        cells: [
                          DataCell(Text(_permissionLabel(permission))),
                          for (final role in AppRole.values)
                            DataCell(
                              permissionsFor(role).contains(permission)
                                  ? const Icon(
                                      Icons.check_circle,
                                      size: 17,
                                      color: AppColors.success,
                                    )
                                  : const Icon(
                                      Icons.remove,
                                      size: 17,
                                      color: AppColors.border,
                                    ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _userTile(BuildContext context, RetailStore store, AppUser user) {
    final theme = Theme.of(context);
    final isMe = user.id == store.currentUser?.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: user.isActive ? AppColors.brand : AppColors.surfaceAlt,
              shape: BoxShape.circle,
              border: Border.all(
                color: user.isActive ? AppColors.gold : AppColors.border,
              ),
            ),
            child: Text(
              user.name.isEmpty
                  ? '?'
                  : user.name.characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: user.isActive ? AppColors.brandInk : AppColors.inkFaint,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    StatusPill(user.role.label, tone: PillTone.strong),
                    if (!user.isActive) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const StatusPill('Disabled', tone: PillTone.bad),
                    ],
                    if (isMe) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const StatusPill('You', tone: PillTone.caution),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    CodeText(user.username, size: 11.5),
                    Text(
                      '  ·  ${user.role.description}',
                      style: AppTypography.microLabel.copyWith(
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.base),
          SecondaryButton(
            label: 'Edit',
            icon: Icons.edit_outlined,
            onPressed: () => _openForm(context, store, user),
          ),
        ],
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
  Permission.adjustStock => 'Count stock and write differences off',
};
