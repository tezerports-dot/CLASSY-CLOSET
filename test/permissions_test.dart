import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/permissions.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('role grants', () {
    test('an admin can do everything', () {
      expect(permissionsFor(AppRole.admin), containsAll(Permission.values));
    });

    test('a cashier can bill but cannot see profit, settings or staff', () {
      final cashier = permissionsFor(AppRole.cashier);

      expect(cashier, contains(Permission.sellAtPos));
      expect(cashier, contains(Permission.viewProducts));
      expect(cashier, contains(Permission.editCustomers));

      expect(cashier, isNot(contains(Permission.viewProfit)));
      expect(cashier, isNot(contains(Permission.viewReports)));
      expect(cashier, isNot(contains(Permission.manageSettings)));
      expect(cashier, isNot(contains(Permission.manageUsers)));
      expect(cashier, isNot(contains(Permission.backupRestore)));
      expect(cashier, isNot(contains(Permission.editProducts)));
      expect(cashier, isNot(contains(Permission.giveDiscount)));
    });

    test('a manager runs the shop but cannot touch staff or settings', () {
      final manager = permissionsFor(AppRole.manager);

      expect(manager, contains(Permission.viewProfit));
      expect(manager, contains(Permission.viewReports));
      expect(manager, contains(Permission.editProducts));

      expect(manager, isNot(contains(Permission.manageUsers)));
      expect(manager, isNot(contains(Permission.manageSettings)));
    });

    test(
      'an unknown role name falls back to the least access, not the most',
      () {
        expect(AppRole.fromName('Wizard'), AppRole.cashier);
        expect(AppRole.fromName(null), AppRole.cashier);
        expect(AppRole.fromName(''), AppRole.cashier);
        expect(
          permissionsFor(AppRole.fromName('typo')),
          isNot(contains(Permission.manageUsers)),
        );
      },
    );

    test('role names are matched however they are cased or spaced', () {
      expect(AppRole.fromName('admin'), AppRole.admin);
      expect(AppRole.fromName('ADMIN'), AppRole.admin);
      expect(AppRole.fromName('Store Keeper'), AppRole.storeKeeper);
    });

    test('every guarded route names a permission that exists', () {
      for (final entry in routePermissions.entries) {
        expect(
          Permission.values,
          contains(entry.value),
          reason: '${entry.key} is guarded by an unknown permission',
        );
      }
    });

    test(
      'someone who cannot see profit lands on the till, not the dashboard',
      () {
        expect(landingRouteFor(AppRole.cashier), '/pos');
        expect(landingRouteFor(AppRole.admin), '/');
        expect(landingRouteFor(AppRole.manager), '/');
      },
    );
  });

  group('against the database', () {
    late AppDatabase db;
    late RetailStore store;

    setUp(() async {
      db = AppDatabase.withExecutor(NativeDatabase.memory());
      store = RetailStore(db);
      await store.initialize();
    });

    tearDown(() async => db.close());

    test('nobody signed in can do anything', () {
      expect(store.isAuthenticated, isFalse);
      for (final permission in Permission.values) {
        expect(store.can(permission), isFalse);
      }
    });

    test('an added cashier signs in with only counter rights', () async {
      await store.login('admin', 'admin123');
      final problem = await store.saveUser(
        id: 0,
        fullName: 'Shop Employee',
        username: 'employee',
        role: AppRole.cashier,
        password: 'shop2026',
      );
      expect(problem, isNull);

      await store.logout();
      expect(await store.login('employee', 'shop2026'), isTrue);

      expect(store.can(Permission.sellAtPos), isTrue);
      expect(store.can(Permission.viewProducts), isTrue);
      expect(store.can(Permission.viewProfit), isFalse);
      expect(store.can(Permission.viewReports), isFalse);
      expect(store.can(Permission.manageSettings), isFalse);
      expect(store.can(Permission.manageUsers), isFalse);
      expect(store.can(Permission.backupRestore), isFalse);
    });

    test('a duplicate username is refused', () async {
      await store.login('admin', 'admin123');
      await store.saveUser(
        id: 0,
        fullName: 'First',
        username: 'sameName',
        role: AppRole.cashier,
        password: 'pass1234',
      );

      final problem = await store.saveUser(
        id: 0,
        fullName: 'Second',
        username: 'samename',
        role: AppRole.cashier,
        password: 'pass1234',
      );

      expect(problem, contains('already taken'));
      expect(store.users.where((u) => u.username == 'samename'), hasLength(1));
    });

    test('a new account without a password is refused', () async {
      await store.login('admin', 'admin123');
      final problem = await store.saveUser(
        id: 0,
        fullName: 'No Password',
        username: 'nopass',
        role: AppRole.cashier,
      );
      expect(problem, contains('password'));
    });

    test('the last administrator cannot be demoted or switched off', () async {
      await store.login('admin', 'admin123');
      final admin = store.users.firstWhere((u) => u.username == 'admin');

      final demote = await store.saveUser(
        id: admin.id,
        fullName: admin.name,
        username: admin.username,
        role: AppRole.cashier,
      );
      expect(demote, contains('only administrator'));

      final disable = await store.saveUser(
        id: admin.id,
        fullName: admin.name,
        username: admin.username,
        role: AppRole.admin,
        isActive: false,
      );
      expect(disable, contains('only administrator'));

      // Still an admin, so the shop is not locked out.
      expect(
        store.users.firstWhere((u) => u.username == 'admin').role,
        AppRole.admin,
      );
    });

    test('demotion is allowed once a second administrator exists', () async {
      await store.login('admin', 'admin123');
      await store.saveUser(
        id: 0,
        fullName: 'Owner Two',
        username: 'owner2',
        role: AppRole.admin,
        password: 'pass1234',
      );

      final admin = store.users.firstWhere((u) => u.username == 'admin');
      final problem = await store.saveUser(
        id: admin.id,
        fullName: admin.name,
        username: admin.username,
        role: AppRole.manager,
      );

      expect(problem, isNull);
      expect(
        store.users.firstWhere((u) => u.username == 'admin').role,
        AppRole.manager,
      );
    });

    test('a disabled account cannot sign in', () async {
      await store.login('admin', 'admin123');
      await store.saveUser(
        id: 0,
        fullName: 'Former Staff',
        username: 'former',
        role: AppRole.cashier,
        password: 'pass1234',
      );
      final former = store.users.firstWhere((u) => u.username == 'former');
      await store.saveUser(
        id: former.id,
        fullName: former.name,
        username: former.username,
        role: former.role,
        isActive: false,
      );

      await store.logout();
      expect(await store.login('former', 'pass1234'), isFalse);
    });

    test(
      'editing a user without a password keeps the old one working',
      () async {
        await store.login('admin', 'admin123');
        await store.saveUser(
          id: 0,
          fullName: 'Keeps Password',
          username: 'keeps',
          role: AppRole.cashier,
          password: 'original',
        );
        final user = store.users.firstWhere((u) => u.username == 'keeps');

        await store.saveUser(
          id: user.id,
          fullName: 'Renamed Person',
          username: 'keeps',
          role: AppRole.sales,
        );

        await store.logout();
        expect(await store.login('keeps', 'original'), isTrue);
        expect(store.currentUser?.name, 'Renamed Person');
        expect(store.currentUser?.role, AppRole.sales);
      },
    );

    test('changing your own password requires the current one', () async {
      await store.login('admin', 'admin123');

      expect(
        await store.changeOwnPassword('wrong', 'newpass1'),
        contains('not correct'),
      );
      expect(await store.changeOwnPassword('admin123', 'newpass1'), isNull);

      await store.logout();
      expect(await store.login('admin', 'admin123'), isFalse);
      expect(await store.login('admin', 'newpass1'), isTrue);
    });

    test('the seeded password is flagged until it is changed', () async {
      expect(await store.usingDefaultAdminPassword(), isTrue);

      await store.login('admin', 'admin123');
      await store.changeOwnPassword('admin123', 'something-else');

      expect(await store.usingDefaultAdminPassword(), isFalse);
    });
  });
}
