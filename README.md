# RetailPro — Offline Desktop ERP/POS

Flutter Windows desktop application scaffold for an offline retail ERP/POS backed by SQLite and Drift.

## Implemented in this branch

- Feature-first clean architecture folders for all planned modules.
- Material 3 desktop shell with collapsible dark sidebar, top search bar, route highlighting, logout, and guarded navigation.
- Local auth service with SHA-256 password hashing and seeded demo admin credentials (`admin` / `admin123`).
- In-app retail store state for products, customers, suppliers, POS cart, checkout, dashboard KPIs, low-stock alerts, pending balances, recent sales, and audit logging.
- Functional screens for Dashboard, Products, POS, Customers, Suppliers, Reports/Audit Log, and Settings placeholders for printing/backup/security.
- Drift schema definition for the planned v1 database tables, relationships, constraints, and foreign-key enforcement.
- Dependency list for Flutter desktop, Drift, BLoC, DI, routing, exports, barcode, printing, backups, and local settings.

## Run locally

1. Install Flutter 3.35 or newer with desktop support for your platform.
2. Run `flutter pub get`.
3. Run `dart run build_runner build` to generate the Drift code (`lib/core/database/app_database.g.dart` is generated and not committed).
4. Run `flutter run -d windows` (or `-d linux`).

Checks: `flutter analyze` and `flutter test`.

## Notes

- `app_database.g.dart` is generated, so step 3 is required before analyzing, testing or running.
- The `linux/` native build compiles SQLite from source, which `sqlite3_flutter_libs` downloads from `sqlite.org` during the CMake configure step. That host must be reachable the first time you build.
