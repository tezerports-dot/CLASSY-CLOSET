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

1. Install Flutter 3.x with Windows desktop support.
2. Run `flutter pub get`.
3. Run `dart run build_runner build --delete-conflicting-outputs` to generate Drift code.
4. Run `flutter run -d windows`.

## Important note

This repository environment does not include Flutter/Dart, so generated Drift files and a Windows runner could not be produced here. The committed app code is structured so those steps can be run on a machine with Flutter installed.
