import 'package:go_router/go_router.dart';

import '../core/services/permissions.dart';
import '../core/services/retail_store.dart';
import '../core/widgets/app_shell.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/customers/presentation/customers_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/pos/presentation/pos_page.dart';
import '../features/products/presentation/products_page.dart';
import '../features/expenses/presentation/expenses_page.dart';
import '../features/purchases/presentation/purchases_page.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/returns/presentation/returns_page.dart';
import '../features/shifts/presentation/shift_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/setup/presentation/store_setup_page.dart';
import '../features/suppliers/presentation/suppliers_page.dart';
import '../features/users/presentation/users_page.dart';

GoRouter createAppRouter(RetailStore store) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: store,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final settingUp = location == '/setup';
      final loggingIn = location == '/login';

      if (!store.hasStoreProfile) return settingUp ? null : '/setup';

      final user = store.currentUser;
      if (settingUp) {
        return user == null ? '/login' : landingRouteFor(user.role);
      }
      if (user == null) return loggingIn ? null : '/login';
      if (loggingIn) return landingRouteFor(user.role);

      // The real gate. Typing a URL, restoring a deep link or following a
      // stale route all pass through here, so a cashier cannot reach reports
      // by any path just because the nav item is hidden.
      final required = routePermissions[location];
      if (required != null && !user.can(required)) {
        return landingRouteFor(user.role);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, __) => const StoreSetupPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
          GoRoute(path: '/products', builder: (_, __) => const ProductsPage()),
          GoRoute(path: '/pos', builder: (_, __) => const PosPage()),
          GoRoute(
            path: '/customers',
            builder: (_, __) => const CustomersPage(),
          ),
          GoRoute(
            path: '/suppliers',
            builder: (_, __) => const SuppliersPage(),
          ),
          GoRoute(
            path: '/purchases',
            builder: (_, __) => const PurchasesPage(),
          ),
          GoRoute(path: '/expenses', builder: (_, __) => const ExpensesPage()),
          GoRoute(path: '/returns', builder: (_, __) => const ReturnsPage()),
          GoRoute(path: '/shift', builder: (_, __) => const ShiftPage()),
          GoRoute(path: '/reports', builder: (_, __) => const ReportsPage()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
          GoRoute(path: '/users', builder: (_, __) => const UsersPage()),
        ],
      ),
    ],
  );
}
