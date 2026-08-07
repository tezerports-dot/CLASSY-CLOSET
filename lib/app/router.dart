import 'package:go_router/go_router.dart';

import '../core/services/retail_store.dart';
import '../core/widgets/app_shell.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/customers/presentation/customers_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/pos/presentation/pos_page.dart';
import '../features/products/presentation/products_page.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/setup/presentation/store_setup_page.dart';
import '../features/suppliers/presentation/suppliers_page.dart';

GoRouter createAppRouter(RetailStore store) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: store,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final settingUp = location == '/setup';
      final loggingIn = location == '/login';
      if (!store.hasStoreProfile) return settingUp ? null : '/setup';
      if (settingUp) return store.isAuthenticated ? '/' : '/login';
      if (!store.isAuthenticated) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, __) => const StoreSetupPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
          GoRoute(path: '/products', builder: (_, __) => const ProductsPage()),
          GoRoute(path: '/pos', builder: (_, __) => const PosPage()),
          GoRoute(path: '/customers', builder: (_, __) => const CustomersPage()),
          GoRoute(path: '/suppliers', builder: (_, __) => const SuppliersPage()),
          GoRoute(path: '/reports', builder: (_, __) => const ReportsPage()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
        ],
      ),
    ],
  );
}
