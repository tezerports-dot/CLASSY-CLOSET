import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di/injection.dart';
import '../services/permissions.dart';
import '../services/retail_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';
import 'brand_mark.dart';

/// The frame every screen mounts inside: a brand rail on the left, a white top
/// bar above, and the working surface filling the rest.
///
/// The rail changes shape three times as the window narrows — full, icon-only,
/// then an off-canvas drawer — because the same build runs on the counter PC,
/// the owner's laptop and a tablet on the shop floor.
class AppShell extends StatefulWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _store = getIt<RetailStore>();

  /// Manual collapse, only offered where there is room to choose.
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final phone = AppBreakpoints.isPhone(width);
          final iconOnly = _collapsed || AppBreakpoints.isTablet(width);

          return Scaffold(
            backgroundColor: AppColors.bg,
            // Below the tablet breakpoint the rail becomes a drawer rather
            // than eating a third of the screen.
            drawer: phone
                ? Drawer(
                    backgroundColor: AppColors.brand,
                    width: 248,
                    child: _Rail(
                      store: _store,
                      location: widget.location,
                      iconOnly: false,
                      onNavigate: (route) {
                        Navigator.of(context).pop();
                        context.go(route);
                      },
                    ),
                  )
                : null,
            body: Row(
              children: [
                if (!phone)
                  _Rail(
                    store: _store,
                    location: widget.location,
                    iconOnly: iconOnly,
                    onToggle: AppBreakpoints.isDesktop(width)
                        ? () => setState(() => _collapsed = !_collapsed)
                        : null,
                    onNavigate: context.go,
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(store: _store, showMenu: phone),
                      Expanded(child: ClipRect(child: widget.child)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------- the rail

class _Rail extends StatelessWidget {
  const _Rail({
    required this.store,
    required this.location,
    required this.iconOnly,
    required this.onNavigate,
    this.onToggle,
  });

  final RetailStore store;
  final String location;
  final bool iconOnly;
  final ValueChanged<String> onNavigate;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: iconOnly ? 76 : 248,
      color: AppColors.brand,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xxs,
                ),
                children: [
                  // Hidden here and blocked in the router: the rail is
                  // tidiness, the route guard is the boundary.
                  for (final item in navItems)
                    if (store.can(item.permission))
                      _RailItem(
                        entry: item,
                        selected: location == item.route,
                        iconOnly: iconOnly,
                        badge:
                            item.route == '/pos' && store.heldBills.isNotEmpty
                            ? store.heldBills.length
                            : null,
                        onTap: () => onNavigate(item.route),
                      ),
                ],
              ),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.xxl,
      AppSpacing.base,
      AppSpacing.xl,
    ),
    child: Row(
      children: [
        const BrandMark(size: 34),
        if (!iconOnly) ...[
          const SizedBox(width: AppSpacing.md),
          const Expanded(child: BrandWordmark(size: 15)),
          if (onToggle != null)
            IconButton(
              tooltip: 'Collapse the menu',
              onPressed: onToggle,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.chevron_left,
                size: 18,
                color: AppColors.brandInkFaint,
              ),
            ),
        ],
      ],
    ),
  );

  Widget _footer(BuildContext context) {
    final user = store.currentUser;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A251D))),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.brandRaised,
            child: Text(
              (user?.name.trim().isNotEmpty ?? false)
                  ? user!.name.trim().characters.first.toUpperCase()
                  : '?',
              style: const TextStyle(
                color: AppColors.brandInk,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          if (!iconOnly) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.name ?? 'Not signed in',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.brandInkSoft,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    user?.role.label ?? '',
                    style: const TextStyle(
                      color: AppColors.brandInkFaint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await store.logout();
              if (context.mounted) context.go('/login');
            },
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.logout,
              size: 17,
              color: AppColors.brandInkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.entry,
    required this.selected,
    required this.iconOnly,
    required this.onTap,
    this.badge,
  });

  final NavEntry entry;
  final bool selected;
  final bool iconOnly;
  final VoidCallback onTap;
  final int? badge;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final content = Row(
      mainAxisAlignment: widget.iconOnly
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Icon(
          widget.entry.icon,
          size: 18,
          color: selected ? AppColors.brandInk : AppColors.brandInkSoft,
        ),
        if (!widget.iconOnly) ...[
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              widget.entry.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: selected ? AppColors.brandInk : AppColors.brandInkSoft,
              ),
            ),
          ),
        ],
        if (widget.badge != null)
          Container(
            margin: EdgeInsets.only(left: widget.iconOnly ? 2 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              '${widget.badge}',
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: widget.iconOnly ? widget.entry.label : '',
          waitDuration: const Duration(milliseconds: 400),
          child: Material(
            color: selected
                ? AppColors.brandRaised
                : (_hovered ? AppColors.brandHover : Colors.transparent),
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(9),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  // The gold bar is what says "you are here" at a glance from
                  // across the counter.
                  border: selected
                      ? const Border(
                          left: BorderSide(color: AppColors.gold, width: 3),
                        )
                      : null,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- the top bar

class _TopBar extends StatelessWidget {
  const _TopBar({required this.store, required this.showMenu});

  final RetailStore store;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final shift = store.openShift;
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Row(
        children: [
          if (showMenu)
            IconButton(
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          const Expanded(child: _GlobalSearch()),
          const SizedBox(width: AppSpacing.xl),
          if (shift != null && MediaQuery.sizeOf(context).width >= 640)
            _TillChip(
              label: 'Till open',
              amount: shift.openingFloat + shift.cashSales,
            ),
        ],
      ),
    );
  }
}

class _GlobalSearch extends StatelessWidget {
  const _GlobalSearch();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      width: 380,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: AppColors.inkFaint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Search products, bills, customers…',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.inkFaint),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Ctrl K',
              style: AppTypography.code.copyWith(
                fontSize: 10,
                color: AppColors.inkFaint,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TillChip extends StatelessWidget {
  const _TillChip({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.base,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.successWash,
      border: Border.all(color: AppColors.successWash),
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '$label · ${AppFormatters.currency(amount)}',
          style: AppTypography.money.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.success,
          ),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ the items

/// One rail entry and the permission that reveals it.
class NavEntry {
  const NavEntry(this.icon, this.label, this.route, this.permission);
  final IconData icon;
  final String label;
  final String route;
  final Permission permission;
}

const navItems = <NavEntry>[
  NavEntry(Icons.grid_view_rounded, 'Dashboard', '/', Permission.viewDashboard),
  NavEntry(
    Icons.point_of_sale_rounded,
    'Billing',
    '/pos',
    Permission.sellAtPos,
  ),
  NavEntry(
    Icons.checkroom_rounded,
    'Products',
    '/products',
    Permission.viewProducts,
  ),
  NavEntry(
    Icons.local_shipping_rounded,
    'Purchases',
    '/purchases',
    Permission.recordPurchases,
  ),
  NavEntry(
    Icons.fact_check_rounded,
    'Stock count',
    '/stocktake',
    Permission.adjustStock,
  ),
  NavEntry(
    Icons.receipt_long_rounded,
    'Expenses',
    '/expenses',
    Permission.recordExpenses,
  ),
  NavEntry(
    Icons.assignment_return_rounded,
    'Returns',
    '/returns',
    Permission.processReturns,
  ),
  NavEntry(Icons.savings_rounded, 'Till', '/shift', Permission.manageShift),
  NavEntry(
    Icons.people_alt_rounded,
    'Customers',
    '/customers',
    Permission.viewCustomers,
  ),
  NavEntry(
    Icons.storefront_rounded,
    'Suppliers',
    '/suppliers',
    Permission.viewSuppliers,
  ),
  NavEntry(
    Icons.insights_rounded,
    'Reports',
    '/reports',
    Permission.viewReports,
  ),
  NavEntry(Icons.badge_rounded, 'Staff', '/users', Permission.manageUsers),
  NavEntry(
    Icons.print_rounded,
    'Hardware',
    '/hardware',
    Permission.manageSettings,
  ),
  NavEntry(
    Icons.settings_rounded,
    'Settings',
    '/settings',
    Permission.manageSettings,
  ),
];
