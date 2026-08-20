/// Things a signed-in user is allowed to do.
///
/// Permissions are named for the action, not the screen, so a check reads the
/// same whether it guards a route, a button or a single figure on a card.
enum Permission {
  /// See the dashboard at all.
  viewDashboard,

  /// See profit, margin and GST-collected figures. Separate from
  /// [viewDashboard] on purpose: a cashier needs to see the day's takings to
  /// reconcile the drawer, but the shop's margin is the owner's business.
  viewProfit,

  /// Ring up a sale.
  sellAtPos,

  /// Take money off a line or a bill.
  giveDiscount,

  /// See the catalogue.
  viewProducts,

  /// Add or change designs, stock levels and prices.
  editProducts,

  viewCustomers,
  editCustomers,

  viewSuppliers,
  editSuppliers,

  /// Open the reports section.
  viewReports,

  /// Change the shop profile, GST rates and other settings.
  manageSettings,

  /// Add staff, change roles, reset passwords.
  manageUsers,

  /// Take a backup or restore one.
  backupRestore,

  /// Take goods back and refund or credit them.
  processReturns,

  /// Open and close a till session and count the drawer.
  manageShift,

  /// Receive stock from a supplier.
  recordPurchases,

  /// Record what the shop spent.
  recordExpenses,

  /// Settle money against a customer's or a supplier's balance.
  ///
  /// Separate from [editCustomers] on purpose: a cashier can correct a phone
  /// number, but writing off what someone owes is the owner's decision.
  recordPayments,

  /// Count the rails and apply what the count found.
  ///
  /// Committing a count writes shrinkage off the books, which is why it is not
  /// simply part of [editProducts].
  adjustStock,
}

/// The roles a user can hold. The name stored in the database is matched
/// case-insensitively against these.
enum AppRole {
  /// The owner. Everything.
  admin('Admin', 'Full access to the whole system'),

  /// Runs the shop day to day but does not see the money behind it.
  manager('Manager', 'Everything except staff accounts and settings'),

  /// Serves customers at the counter.
  cashier('Cashier', 'Billing and customers only'),

  /// Handles stock, not money.
  storeKeeper('StoreKeeper', 'Stock and suppliers, no billing'),

  /// Sells but cannot change the catalogue.
  sales('Sales', 'Billing and customers, view-only catalogue');

  const AppRole(this.label, this.description);
  final String label;
  final String description;

  static AppRole fromName(String? name) {
    final normalized = (name ?? '').trim().toLowerCase().replaceAll(' ', '');
    for (final role in AppRole.values) {
      if (role.label.toLowerCase() == normalized) return role;
    }
    // An unrecognised role gets the least access rather than the most: a typo
    // in the database must never hand someone the keys.
    return AppRole.cashier;
  }
}

/// What each role may do.
///
/// Deliberately written out in full rather than built by adding to a base set,
/// so the answer to "what can a cashier do?" is one list you can read, not a
/// chain of inherited grants you have to follow.
const Map<AppRole, Set<Permission>> rolePermissions = {
  AppRole.admin: {
    Permission.viewDashboard,
    Permission.viewProfit,
    Permission.sellAtPos,
    Permission.giveDiscount,
    Permission.viewProducts,
    Permission.editProducts,
    Permission.viewCustomers,
    Permission.editCustomers,
    Permission.viewSuppliers,
    Permission.editSuppliers,
    Permission.viewReports,
    Permission.manageSettings,
    Permission.manageUsers,
    Permission.backupRestore,
    Permission.processReturns,
    Permission.manageShift,
    Permission.recordPurchases,
    Permission.recordExpenses,
    Permission.recordPayments,
    Permission.adjustStock,
  },
  AppRole.manager: {
    Permission.viewDashboard,
    Permission.viewProfit,
    Permission.sellAtPos,
    Permission.giveDiscount,
    Permission.viewProducts,
    Permission.editProducts,
    Permission.viewCustomers,
    Permission.editCustomers,
    Permission.viewSuppliers,
    Permission.editSuppliers,
    Permission.viewReports,
    Permission.backupRestore,
    Permission.processReturns,
    Permission.manageShift,
    Permission.recordPurchases,
    Permission.recordExpenses,
    Permission.recordPayments,
    Permission.adjustStock,
  },
  AppRole.cashier: {
    Permission.viewDashboard,
    Permission.sellAtPos,
    Permission.viewProducts,
    Permission.viewCustomers,
    Permission.editCustomers,
    // A customer bringing something back is an everyday counter job, and the
    // shift is how their own drawer gets counted.
    Permission.processReturns,
    Permission.manageShift,
  },
  AppRole.storeKeeper: {
    Permission.viewDashboard,
    Permission.viewProducts,
    Permission.editProducts,
    Permission.viewSuppliers,
    Permission.editSuppliers,
    // Receiving a delivery and counting the rails are exactly this role's job.
    Permission.recordPurchases,
    Permission.adjustStock,
  },
  AppRole.sales: {
    Permission.viewDashboard,
    Permission.sellAtPos,
    Permission.viewProducts,
    Permission.viewCustomers,
    Permission.editCustomers,
    Permission.manageShift,
  },
};

Set<Permission> permissionsFor(AppRole role) =>
    rolePermissions[role] ?? const <Permission>{};

/// The route a role should land on after signing in.
///
/// A cashier has no dashboard worth showing on its own, so they go straight to
/// the till — which is where they were going anyway.
String landingRouteFor(AppRole role) =>
    permissionsFor(role).contains(Permission.viewProfit) ? '/' : '/pos';

/// Routes and the permission each one needs. A route that is absent is open to
/// anyone signed in.
const Map<String, Permission> routePermissions = {
  '/': Permission.viewDashboard,
  '/pos': Permission.sellAtPos,
  '/products': Permission.viewProducts,
  '/customers': Permission.viewCustomers,
  '/suppliers': Permission.viewSuppliers,
  '/returns': Permission.processReturns,
  '/shift': Permission.manageShift,
  '/purchases': Permission.recordPurchases,
  '/expenses': Permission.recordExpenses,
  '/reports': Permission.viewReports,
  '/hardware': Permission.manageSettings,
  '/settings': Permission.manageSettings,
  '/users': Permission.manageUsers,
};
