import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di/injection.dart';
import '../services/permissions.dart';
import '../services/retail_store.dart';
import '../theme/app_colors.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _collapsed = false;
  final _store = getIt<RetailStore>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: _collapsed ? 76 : 260,
            color: AppColors.sidebar,
            child: SafeArea(
              child: Column(
                children: [
                  ListTile(
                    leading:
                        _store.storeProfile?.logoPath == null ||
                            !File(_store.storeProfile!.logoPath!).existsSync()
                        ? const Icon(Icons.storefront, color: Colors.white)
                        : Image.file(
                            File(_store.storeProfile!.logoPath!),
                            width: 28,
                            height: 28,
                            fit: BoxFit.contain,
                          ),
                    title: _collapsed
                        ? null
                        : Text(
                            _store.displayStoreName,
                            style: const TextStyle(color: Colors.white),
                          ),
                    trailing: IconButton(
                      onPressed: () => setState(() => _collapsed = !_collapsed),
                      icon: Icon(
                        _collapsed ? Icons.chevron_right : Icons.chevron_left,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white12),
                  Expanded(
                    child: ListView(
                      children: [
                        // Only what this user may actually open. The
                        // router blocks the rest as well, so hiding an item is
                        // tidiness rather than the security boundary.
                        for (final item in _navItems)
                          if (_store.can(item.permission))
                            _NavItem(
                              collapsed: _collapsed,
                              icon: item.icon,
                              label: item.label,
                              route: item.route,
                              selected: widget.location == item.route,
                              onTap: _go,
                            ),
                      ],
                    ),
                  ),
                  _NavItem(
                    collapsed: _collapsed,
                    icon: Icons.logout,
                    label: 'Logout',
                    route: '/login',
                    onTap: (_) async => _store.logout(),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 64,
                  color: AppColors.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      const Expanded(child: _GlobalSearchHint()),
                      CircleAvatar(
                        child: Text(
                          (_store.currentUser?.name ?? 'A').characters.first,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(_store.currentUser?.name ?? 'Admin'),
                    ],
                  ),
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _go(String route) => context.go(route);
}

/// One sidebar entry and the permission that reveals it.
class _NavEntry {
  const _NavEntry(this.icon, this.label, this.route, this.permission);
  final IconData icon;
  final String label;
  final String route;
  final Permission permission;
}

const _navItems = <_NavEntry>[
  _NavEntry(Icons.dashboard, 'Dashboard', '/', Permission.viewDashboard),
  _NavEntry(Icons.point_of_sale, 'Billing', '/pos', Permission.sellAtPos),
  _NavEntry(
    Icons.inventory_2,
    'Products',
    '/products',
    Permission.viewProducts,
  ),
  _NavEntry(
    Icons.assignment_return,
    'Returns',
    '/returns',
    Permission.processReturns,
  ),
  _NavEntry(Icons.savings, 'Till', '/shift', Permission.manageShift),
  _NavEntry(Icons.people, 'Customers', '/customers', Permission.viewCustomers),
  _NavEntry(
    Icons.local_shipping,
    'Suppliers',
    '/suppliers',
    Permission.viewSuppliers,
  ),
  _NavEntry(Icons.bar_chart, 'Reports', '/reports', Permission.viewReports),
  _NavEntry(Icons.badge, 'Staff', '/users', Permission.manageUsers),
  _NavEntry(Icons.settings, 'Settings', '/settings', Permission.manageSettings),
];

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.collapsed,
    required this.icon,
    required this.label,
    required this.route,
    required this.onTap,
    this.selected = false,
  });

  final bool collapsed;
  final IconData icon;
  final String label;
  final String route;
  final ValueChanged<String> onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? AppColors.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () => onTap(route),
        leading: Icon(icon, color: selected ? Colors.white : Colors.white70),
        title: collapsed
            ? null
            : Text(label, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }
}

class _GlobalSearchHint extends StatelessWidget {
  const _GlobalSearchHint();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 360,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.contentBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.search, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text('Search everything... Ctrl+K'),
          ],
        ),
      ),
    );
  }
}
