# 🏪 RetailPro — Offline Desktop ERP/POS
## Master Project Plan · Retail / General Store · Windows Desktop

> **Build Tool:** Claude Opus (Pro Plan) via claude.ai  
> **Target Platform:** Windows Desktop (Flutter)  
> **Database:** SQLite + Drift ORM  
> **Session Format:** 5-hour focused sessions  
> **Architecture:** Feature-First Clean Architecture (MVVM + BLoC)

---

## ⏱️ TOTAL ESTIMATE: 22–28 Sessions × 5 Hours = 110–140 Hours

> Sessions assume Claude Opus with Pro plan context limits. Each session ends before ~40% context fill to avoid "dumb zone" degradation. Keep sessions tightly scoped — one feature module per session max.

---

## 📐 ARCHITECTURE OVERVIEW

```
lib/
├── app/                        # App entry, router, DI setup
│   ├── app.dart
│   ├── router.dart
│   └── di/
│       └── injection.dart      # get_it service locator
│
├── core/                       # Shared across all features
│   ├── database/
│   │   ├── app_database.dart   # Drift DB root
│   │   └── migrations/
│   ├── theme/
│   │   ├── app_theme.dart
│   │   ├── app_colors.dart
│   │   └── app_typography.dart
│   ├── widgets/                # Shared UI components
│   ├── utils/
│   │   ├── formatters.dart
│   │   ├── validators.dart
│   │   ├── pdf_generator.dart
│   │   └── excel_exporter.dart
│   ├── constants/
│   └── errors/
│
└── features/                   # One folder per module
    ├── auth/
    ├── dashboard/
    ├── products/
    ├── categories/
    ├── customers/
    ├── suppliers/
    ├── inventory/
    ├── purchases/
    ├── sales/
    ├── pos/
    ├── returns/
    ├── expenses/
    ├── accounting/
    ├── reports/
    ├── printing/
    ├── settings/
    ├── users/
    └── backup/
```

Each feature follows:
```
features/products/
├── data/
│   ├── models/          # Drift table definitions
│   ├── datasources/     # local_datasource.dart
│   └── repositories/    # repository_impl.dart
├── domain/
│   ├── entities/        # Pure Dart classes
│   ├── repositories/    # Abstract contracts
│   └── usecases/        # One class, one action
└── presentation/
    ├── bloc/            # BLoC state management
    ├── pages/           # Full screens
    └── widgets/         # Screen-specific widgets
```

---

## 🛠️ TECHNOLOGY STACK

| Component | Package | Notes |
|-----------|---------|-------|
| **UI Framework** | Flutter 3.x Desktop | Windows native |
| **State Management** | flutter_bloc + equatable | Per-feature BLoCs |
| **Database** | drift + sqlite3_flutter_libs | SQLite with type-safe Dart API |
| **DI** | get_it + injectable | Service locator |
| **Navigation** | go_router | Declarative routing |
| **Charts** | fl_chart | Dashboard graphs |
| **PDF Export** | pdf + printing | A4 invoice generation |
| **Excel Export** | excel | .xlsx reports |
| **Barcode Scanner** | mobile_scanner | USB/webcam input |
| **Barcode Generator** | barcode_widget | Label printing |
| **Thermal Printer** | windows_printer | ESC/POS 58/80mm |
| **A4 Printing** | pdf + windows_printer | Invoice printing |
| **Image Picker** | file_picker | Product images |
| **Backup/ZIP** | archive | ZIP backup/restore |
| **JSON Settings** | shared_preferences | App config |
| **Auth (local)** | crypto (sha256) | Hashed passwords |
| **Code Gen** | build_runner, drift_dev, injectable_generator | Auto-gen |
| **Logging** | logger | Audit trail |
| **Date/Time** | intl | Formatting |

---

## 📅 SESSION-BY-SESSION PLAN

---

### 🔧 PHASE 0 — Foundation (Sessions 1–2)

#### Session 1 · Project Setup & Database Schema Design (5h)
**Goal:** Working Flutter Windows project with complete DB schema

**Prompt Focus:**
```
You are building a Windows desktop ERP/POS app for a retail general store in Flutter.
Set up the project with:
- flutter_bloc, get_it, injectable, go_router, drift, sqlite3_flutter_libs
- Windows desktop support enabled
- Feature-first clean architecture folder structure
- Core theme system (dark sidebar, white content area, accent color)
- Drift database with ALL tables defined:
  users, roles, permissions,
  categories, brands, units,
  products, product_images,
  customers, suppliers,
  inventory_movements,
  purchases, purchase_items,
  sales, sale_items,
  returns, return_items,
  expenses, expense_categories,
  cash_book, bank_book,
  ledger_entries,
  audit_logs, settings
- All foreign keys, indexes, constraints
- Database migration strategy (v1)
```

**Deliverables:**
- [ ] Flutter project boots on Windows
- [ ] All Drift tables generated
- [ ] Folder structure set up
- [ ] Theme tokens defined

---

#### Session 2 · Core Infrastructure (5h)
**Goal:** Auth, routing, navigation shell, DI wired

**Prompt Focus:**
```
Build the application shell:
- Login screen with local user auth (SHA-256 hashed passwords)
- Seed admin user on first run
- Role-based access control system (Admin, Manager, Cashier, StoreKeeper, Sales)
- Main app layout: collapsible left sidebar, top bar, content area
- go_router with route guards based on user role
- get_it + injectable DI configured
- Audit log service (every data change is recorded)
- App settings service (JSON-based)
- Global search scaffold (keyboard shortcut: Ctrl+K)
```

**Deliverables:**
- [ ] Login screen working
- [ ] Navigation shell with sidebar
- [ ] Role guards on routes
- [ ] DI fully wired

---

### 📦 PHASE 1 — Core Data Modules (Sessions 3–8)

#### Session 3 · Dashboard (5h)
**Goal:** Live dashboard with KPIs and charts

**Prompt Focus:**
```
Build the Dashboard screen:
- KPI cards: Today's Sales, Today's Profit, Today's Purchases, Today's Expenses, Today's Customers
- Low Stock alert list (products below minimum_stock)
- Pending Payments list (customers with outstanding balance)
- Monthly Revenue bar chart (fl_chart)
- Monthly Profit line chart (fl_chart)
- Top 5 Selling Products pie chart
- Recent Transactions table (last 10 sales)
- All data from Drift reactive streams (auto-refresh)
- Greeting with current user name and date/time
```

---

#### Session 4 · Categories, Brands, Units (5h)
**Goal:** All lookup/master data management

**Prompt Focus:**
```
Build master data screens:
- Categories: CRUD with parent/child hierarchy (tree view), color tag, icon
- Brands: CRUD with logo image
- Units of Measure: CRUD (kg, g, pcs, box, dozen, litre, etc.)
- Each screen: DataTable with search, add/edit dialog, soft delete, pagination
- Reusable CRUD dialog widget that can be shared
```

---

#### Session 5 · Products (5h)
**Goal:** Full product management

**Prompt Focus:**
```
Build Product management:
- Product list with image thumbnail, SKU, name, category, stock, price
- Search/filter by name, SKU, barcode, category, brand
- Add/Edit product form:
  - SKU (auto-generate or manual), Barcode, QR Code
  - Name, Description, Category, Brand, Unit, Supplier
  - Purchase Price, Selling Price, Wholesale Price
  - Tax %, Current Stock, Minimum Stock, Max Stock
  - Location (shelf/bin), Expiry Date toggle
  - Product Image (file picker, save to /data/images/products/)
  - Active/Inactive toggle
- Barcode display widget with print button
- Bulk import from CSV
- Export product list to Excel
```

---

#### Session 6 · Customers (5h)
**Goal:** Full customer management + ledger

**Prompt Focus:**
```
Build Customer management:
- Customer list: name, phone, email, outstanding balance, credit limit
- Search by name, phone, email
- Add/Edit customer:
  - Name, Mobile, Email, Address, GST Number
  - Credit Limit, Opening Balance
  - Photo (optional)
  - Notes
- Customer detail view:
  - Purchase history (all sales with dates, amounts)
  - Outstanding balance breakdown
  - Ledger tab: all transactions (sale, payment, return)
  - Payment recording (receive payment)
- Customer statement PDF export
```

---

#### Session 7 · Suppliers (5h)
**Goal:** Full supplier management + ledger

**Prompt Focus:**
```
Build Supplier management:
- Supplier list: name, contact person, phone, pending payment amount
- Add/Edit supplier:
  - Company Name, Contact Person, Phone, Email
  - Address, GST Number, Bank Details
  - Opening Balance
- Supplier detail view:
  - Purchase history
  - Pending payment breakdown
  - Ledger: all transactions (purchase, payment, return)
  - Payment recording (make payment to supplier)
- Supplier statement PDF export
```

---

#### Session 8 · Users & Settings (5h)
**Goal:** User management, roles, app settings

**Prompt Focus:**
```
Build User management and Settings:
- User management (Admin only):
  - List all users with role and status
  - Add/Edit user: name, username, password, role, permissions
  - Enable/disable user
  - Activity log per user
- Permission matrix: toggle permissions per role
- Settings screen:
  - Business Info: name, address, phone, logo, GST number
  - Invoice settings: prefix, starting number, footer text
  - POS settings: default tax, decimal places
  - Printer settings: thermal (58/80mm), A4
  - Backup settings: auto-backup path, frequency reminder
  - Theme: light/dark mode
```

---

### 💰 PHASE 2 — Transactions (Sessions 9–15)

#### Session 9 · Inventory & Stock Management (5h)
**Goal:** All stock movement types

**Prompt Focus:**
```
Build Inventory Management:
- Inventory movement screen with filters:
  - Type: Purchase, Sale, Return, Damage, Adjustment, Transfer, Opening
  - Date range, Product, Category
- Stock adjustment form: product, quantity (±), reason, notes, date
- Damage recording: product, qty, reason, photo attachment
- Opening stock entry: bulk entry for all products
- Stock valuation report (current stock × purchase price)
- Stock movement history per product
- Low stock alerts with reorder suggestion
- Inventory audit mode: scan barcode → verify physical vs system
```

---

#### Session 10 · Purchases (5h)
**Goal:** Purchase order management

**Prompt Focus:**
```
Build Purchase Management:
- Purchase list: date, supplier, items count, total, status (draft/confirmed/received)
- New Purchase form:
  - Supplier selector
  - Date, reference number, notes
  - Line items: product search (by name/barcode), qty, unit price, discount, tax, subtotal
  - Add new product inline if not found
  - Grand total with tax breakdown
  - Payment: paid amount, payment method (cash/bank), due amount
  - Save as draft or confirm
  - On confirm: auto-update stock levels
- Purchase detail view with edit/cancel
- Print purchase order (A4 PDF)
- Purchase return workflow
```

---

#### Session 11 · Sales (5h)
**Goal:** Sales order / invoice management

**Prompt Focus:**
```
Build Sales Management (non-POS):
- Sales list: invoice number, date, customer, items, total, payment status
- New Sale / Invoice form:
  - Customer selector (or walk-in)
  - Date, due date, notes
  - Line items: product search, qty, unit price, discount, tax
  - Subtotal, discount, tax, grand total
  - Payment: received amount, method, balance due
  - Save draft / confirm
  - On confirm: auto-reduce stock, update customer ledger
- Invoice detail view
- Print A4 invoice (PDF)
- Sales return workflow
- Recurring invoice support (optional)
```

---

#### Session 12 · POS Screen (5h)
**Goal:** Fast point-of-sale terminal

**Prompt Focus:**
```
Build the POS (Point of Sale) screen — this is the most used screen:
- Two-panel layout: left=product search + cart, right=payment
- Product search: type name or scan barcode (USB scanner via keyboard input)
- Quick category filter buttons
- Product grid view with image, name, price, stock
- Cart:
  - Add/remove items, change qty, apply item discount
  - Running total with tax
  - Customer selector
  - Saved cart / hold transaction (multiple pending carts)
- Payment panel:
  - Cash / Card / Split payment
  - Cash tendered → change calculator
  - Apply overall discount
  - Grand total display
- On complete sale:
  - Auto-print thermal receipt
  - Update stock
  - Update customer balance
  - Generate invoice number
- Keyboard shortcuts: F1=new sale, F2=hold, F3=recall, F4=discount, F12=pay
- Session mode: open/close cash drawer with opening balance
```

---

#### Session 13 · Thermal Printing & Label Printing (5h)
**Goal:** All printing subsystems

**Prompt Focus:**
```
Build the Printing system:
- Printer settings service: discover Windows printers, save default thermal + A4
- Thermal receipt printer (windows_printer package + ESC/POS):
  - 58mm receipt template
  - 80mm receipt template
  - Business name, address, GST, cashier name
  - Item lines, subtotal, tax, total, payment method, change
  - Footer: thank you message, return policy
  - QR code on receipt
- A4 Invoice PDF (pdf package):
  - Professional invoice template with logo
  - Business info, customer info, GST, item table
  - Terms and conditions footer
- Barcode label printing:
  - Product name, price, barcode, SKU
  - Multiple label sizes (2x1, 3x2 inch)
  - Bulk print for multiple products
- Print preview before printing
- Reprint last receipt
```

---

#### Session 14 · Returns & Refunds (5h)
**Goal:** Complete returns workflow

**Prompt Focus:**
```
Build Returns management:
- Sales Return:
  - Reference original invoice (search by invoice number or customer)
  - Select which items to return, qty, reason
  - Refund method: cash refund / credit to account
  - Auto-restore stock
  - Generate credit note PDF
  - Update customer ledger
- Purchase Return:
  - Reference original purchase
  - Select items/qty, reason
  - Debit to supplier account
  - Auto-reduce stock
  - Generate debit note PDF
  - Update supplier ledger
- Returns list with filter by type, date, status
```

---

#### Session 15 · Expenses & Cash Book (5h)
**Goal:** Expense tracking and daily cash management

**Prompt Focus:**
```
Build Expense and Cash Book:
- Expense categories: CRUD (Rent, Electricity, Salary, Transport, etc.)
- Expense entry:
  - Date, category, amount, payment method (cash/bank)
  - Description, receipt image attachment
  - Recurring expense toggle
- Daily Expense list with totals
- Cash Book:
  - Opening balance per day
  - Cash In: sales, customer payments
  - Cash Out: purchases, supplier payments, expenses
  - Closing balance
  - Cash denomination counter (for end-of-day)
- Bank Book:
  - Bank transactions (deposits, withdrawals, transfers)
  - Bank reconciliation
```

---

### 📊 PHASE 3 — Accounting & Reports (Sessions 16–20)

#### Session 16 · Ledger & Accounting Core (5h)
**Goal:** Double-entry accounting foundation

**Prompt Focus:**
```
Build Accounting module:
- Chart of accounts (simplified): Assets, Liabilities, Income, Expense
- Ledger entries: auto-posted from sales, purchases, expenses
- Customer ledger: all transactions per customer (sale, payment, return, credit)
- Supplier ledger: all transactions per supplier (purchase, payment, return, debit)
- Outstanding receivables: all customers with unpaid balances
- Outstanding payables: all suppliers with pending payments
- Opening/Closing balance per period
- Journal entry view
- Profit & Loss calculation: Income - COGS - Expenses
```

---

#### Session 17 · Sales Reports (5h)
**Goal:** All sales reporting screens + exports

**Prompt Focus:**
```
Build Sales Reports:
Each report has: date range filter, export to Excel + PDF, print option

1. Daily Sales Report — sales by day, totals, payment method breakdown
2. Monthly Sales Report — month-wise summary with growth %
3. Yearly Sales Report — annual overview with month comparison
4. Sales by Product — best sellers, qty sold, revenue per product
5. Sales by Category — revenue per category
6. Sales by Customer — top customers by revenue
7. Sales by Cashier/User — performance per user
8. Payment Method Report — cash vs card vs credit breakdown
9. GST/Tax Report — output tax collected, HSN-wise
10. Outstanding Payments — customers with pending dues, aging (30/60/90 days)
```

---

#### Session 18 · Inventory & Purchase Reports (5h)
**Goal:** All inventory/purchase reporting

**Prompt Focus:**
```
Build Inventory and Purchase Reports:

Inventory Reports:
1. Current Stock Report — all products with qty, value
2. Stock Movement Report — in/out movements per period
3. Low Stock Report — products below minimum stock
4. Dead Stock Report — products with zero movement > 30 days
5. Expiry Report — products expiring within N days
6. Stock Valuation Report — current stock at cost price

Purchase Reports:
7. Purchase Report — all purchases by date/supplier
8. Purchase by Supplier — spend per supplier
9. Purchase Return Report
10. Pending Payments (Payable Aging Report)

Each: Excel + PDF export
```

---

#### Session 19 · Profit, Loss & Financial Reports (5h)
**Goal:** Business financial health reports

**Prompt Focus:**
```
Build Financial Reports:
1. Profit & Loss Statement — revenue, COGS, gross profit, expenses, net profit
   - Daily / Monthly / Yearly view
   - Comparison: this month vs last month
2. Cash Flow Report — cash in vs cash out per period
3. Expense Report — expenses by category, by date
4. Expense vs Budget — if budget feature added
5. Top Selling Products (by revenue and by qty)
6. Product Profitability — selling price - purchase price × qty sold
7. Customer Profitability — revenue per customer
8. Daily Summary Report — end-of-day report (sales, expense, cash, profit)
9. Business Health Dashboard — single-page financial snapshot

All reports: PDF export + print
```

---

#### Session 20 · Global Search, Barcode Scanner & Quick Actions (5h)
**Goal:** Power-user features and speed

**Prompt Focus:**
```
Build Global Search and Power Features:
- Global Search (Ctrl+K):
  - Search across: Products, Customers, Suppliers, Invoices, Purchase Orders
  - Instant results as you type
  - Keyboard navigate results, Enter to open
  - Shows: type icon, name, secondary detail (price / phone / invoice#)
- Barcode scanner integration:
  - USB scanner = keyboard wedge input
  - On product scan: open product or add to current POS cart
  - On invoice scan: open invoice
- Quick invoice lookup: enter invoice number → view invoice
- Customer quick lookup: enter phone → view customer
- Recent transactions widget (sidebar or dashboard)
```

---

### 🔒 PHASE 4 — Enterprise Features (Sessions 21–25)

#### Session 21 · Backup, Restore & Data Management (5h)
**Goal:** Bulletproof data safety

**Prompt Focus:**
```
Build Backup and Data Management:
- One-click Backup:
  - Compresses: database.db + /data/images/ + /data/settings/ + /data/templates/
  - Creates: backup_YYYY_MM_DD_HHMM.zip
  - Save to user-selected folder (or default /backups/)
  - Shows backup size and timestamp
- Restore:
  - Select .zip backup file
  - Validate backup integrity
  - Confirm warning dialog (will overwrite current data)
  - Restore and restart app
- Auto-backup reminder: popup after X days without backup
- Backup history log
- Database maintenance:
  - Vacuum SQLite database
  - Integrity check
  - Export all data to Excel
  - Clear old data (archive by date)
- Import data from CSV (products, customers, suppliers)
```

---

#### Session 22 · Audit Logs & Security (5h)
**Goal:** Full audit trail and security hardening

**Prompt Focus:**
```
Build Audit and Security system:
- Audit log table: every CREATE, UPDATE, DELETE records:
  - user_id, action, table_name, record_id, old_value (JSON), new_value (JSON), timestamp, ip
- Audit log viewer (admin only):
  - Filter by user, action, table, date range
  - Show changes side-by-side (old vs new)
  - Export audit log to Excel/PDF
- Soft delete: no hard deletes — records marked deleted_at
- Undo: last N actions can be undone (within same session)
- Session management:
  - Auto-lock after idle time (configurable: 5/10/30 min)
  - Lock screen with PIN re-entry
  - Login session recorded in audit log
- Password policy:
  - Minimum 8 chars, must change on first login
  - Admin can reset any user password
```

---

#### Session 23 · Notifications, Alerts & Dashboard Widgets (5h)
**Goal:** Proactive business intelligence

**Prompt Focus:**
```
Build Alerts and Intelligence features:
- Alert center (bell icon in top bar):
  - Low stock alerts (products below min stock)
  - Expiry alerts (products expiring in 7/14/30 days)
  - Pending payments overdue (customers > 30 days)
  - Pending payables overdue (suppliers > 30 days)
  - No backup > 7 days warning
  - Large transaction alerts (above threshold)
- Dashboard customization:
  - Drag and resize KPI cards
  - Save layout per user
- Quick actions widget:
  - New Sale, New Purchase, Add Product, Receive Payment, Record Expense
- Business insights panel:
  - "Your best selling product today is X"
  - "Customer Y has not purchased in 30 days"
  - "Stock of Z will run out in ~N days at current rate"
```

---

#### Session 24 · Data Import & Migration Tools (5h)
**Goal:** Onboarding tools for new users

**Prompt Focus:**
```
Build Data Import system for new business setup:
- Import Wizard (step-by-step):
  Step 1: Download Excel template
  Step 2: Fill in data
  Step 3: Upload file
  Step 4: Preview & validate (show errors)
  Step 5: Confirm import

- Import templates for:
  - Products (with categories auto-create)
  - Customers (with opening balance)
  - Suppliers (with opening balance)
  - Opening stock (product + quantity)

- Validation rules:
  - Duplicate SKU check
  - Required fields check
  - Data type check
  - Stock quantity must be positive

- Import log: what was imported, what failed
- Rollback: undo import if mistakes found
```

---

#### Session 25 · Performance, Polish & Testing (5h)
**Goal:** Production-ready quality

**Prompt Focus:**
```
Performance and Polish pass:
- Database query optimization:
  - Add missing indexes on frequently queried columns
  - Review N+1 query problems
  - Drift background isolate for heavy operations
- UI Polish:
  - Loading skeletons on all data tables
  - Empty state illustrations for all lists
  - Proper error states with retry buttons
  - Smooth page transitions
  - Keyboard navigation everywhere
  - Tooltips on all icon buttons
- Accessibility:
  - Keyboard focus indicators
  - Screen reader labels on icons
- Error handling:
  - Global error boundary
  - User-friendly error messages (not Dart stack traces)
  - Network-unavailable state (offline mode only, so not applicable)
- App startup optimization:
  - Splash screen
  - Background DB initialization
```

---

### 🎨 PHASE 5 — UI/UX Polish (Sessions 26–28)

#### Session 26 · Design System Implementation (5h)
**Goal:** Consistent, professional UI throughout

**Prompt Focus:**
```
Implement the full design system:
- Color tokens:
  - Primary: #1A1D2E (dark navy sidebar)
  - Accent: #6C63FF (purple-indigo)
  - Success: #22C55E
  - Warning: #F59E0B
  - Error: #EF4444
  - Surface: #FFFFFF
  - Background: #F8F9FC
- Typography:
  - Display: Inter 700 (page titles)
  - Body: Inter 400/500 (content)
  - Mono: JetBrains Mono (codes, numbers, prices)
- Component library:
  - AppCard, AppDataTable, AppSearchField, AppDialog
  - AppButton (primary, secondary, danger, ghost)
  - AppBadge (status chips: Active, Draft, Paid, Partial, Overdue)
  - AppTextField, AppDropdown, AppDatePicker
  - StatsCard, ChartCard, AlertCard
  - Sidebar navigation with active state indicators
- Dark mode support
- Windows-native window decorations (title bar, min/max/close)
```

---

#### Session 27 · UX Flows & Micro-interactions (5h)
**Goal:** App feels delightful to use

**Prompt Focus:**
```
UX Flow polish:
- POS checkout flow optimization:
  - Tab order: search → cart → payment → complete
  - Auto-focus product search on screen open
  - Number pad for cash entry
  - Sound feedback on successful sale (optional)
- Form UX:
  - Auto-advance to next field on Tab
  - Ctrl+S to save any form
  - Escape to cancel/close dialog
  - Unsaved changes warning on navigate away
- Toast notifications:
  - Success: "Sale #INV-0042 created"
  - Error: "Insufficient stock for Product X"
  - Info: "Backup created successfully"
- Confirmation dialogs for destructive actions
- Undo toast for deletions (5-second window)
- Infinite scroll or cursor pagination on all lists
- Sticky table headers
- Right-click context menus on table rows
```

---

#### Session 28 · Final Testing, Installer & Deployment (5h)
**Goal:** Ship-ready Windows application

**Prompt Focus:**
```
Final deployment preparation:
- Windows installer:
  - MSIX package (preferred) or Inno Setup installer
  - App icon set (ico format, all sizes)
  - Installer includes: app + C++ runtime + SQLite3
  - Default install path: C:\Program Files\RetailPro\
  - Data path: C:\ProgramData\RetailPro\ (or user documents)
  - Start menu shortcut + desktop icon
- First-run setup wizard:
  - Welcome screen
  - Business information form
  - Create admin account
  - Select data directory
  - Optional: import existing data
- Auto-update check (optional, reads a version file from URL)
- CLAUDE.md file: complete project briefing for future sessions
- Final smoke test checklist:
  - Login / logout
  - Add product, make sale, print receipt
  - Backup and restore
  - All reports generate without error
```

---

## 🗺️ SESSION MAP SUMMARY

| # | Session | Phase | Hours |
|---|---------|-------|-------|
| 1 | Project Setup + DB Schema | Foundation | 5h |
| 2 | Core Infrastructure + Auth + Shell | Foundation | 5h |
| 3 | Dashboard | Phase 1 | 5h |
| 4 | Categories, Brands, Units | Phase 1 | 5h |
| 5 | Products | Phase 1 | 5h |
| 6 | Customers | Phase 1 | 5h |
| 7 | Suppliers | Phase 1 | 5h |
| 8 | Users & Settings | Phase 1 | 5h |
| 9 | Inventory & Stock | Phase 2 | 5h |
| 10 | Purchases | Phase 2 | 5h |
| 11 | Sales / Invoicing | Phase 2 | 5h |
| 12 | POS Screen | Phase 2 | 5h |
| 13 | Thermal + Label Printing | Phase 2 | 5h |
| 14 | Returns & Refunds | Phase 2 | 5h |
| 15 | Expenses & Cash Book | Phase 2 | 5h |
| 16 | Ledger & Accounting Core | Phase 3 | 5h |
| 17 | Sales Reports | Phase 3 | 5h |
| 18 | Inventory & Purchase Reports | Phase 3 | 5h |
| 19 | Financial Reports | Phase 3 | 5h |
| 20 | Global Search + Barcode | Phase 3 | 5h |
| 21 | Backup & Restore | Phase 4 | 5h |
| 22 | Audit Logs & Security | Phase 4 | 5h |
| 23 | Alerts & Intelligence | Phase 4 | 5h |
| 24 | Data Import Wizard | Phase 4 | 5h |
| 25 | Performance & Polish | Phase 4 | 5h |
| 26 | Design System | Phase 5 | 5h |
| 27 | UX Flows & Micro-interactions | Phase 5 | 5h |
| 28 | Installer & Deployment | Phase 5 | 5h |

**Total: 28 sessions × 5 hours = 140 hours**

---

## 📂 DATABASE SCHEMA (All Tables)

### Users & Auth
```sql
users            (id, name, username, password_hash, role_id, is_active, created_at)
roles            (id, name, description)
permissions      (id, role_id, module, can_view, can_create, can_edit, can_delete)
sessions         (id, user_id, login_at, logout_at, ip_address)
```

### Master Data
```sql
categories       (id, name, parent_id, color, icon, is_active, deleted_at)
brands           (id, name, logo_path, is_active)
units            (id, name, abbreviation, is_active)
tax_rates        (id, name, percentage, is_active)
expense_categories (id, name, description, is_active)
```

### Products
```sql
products         (id, sku, barcode, name, description, category_id, brand_id, unit_id,
                  supplier_id, purchase_price, selling_price, wholesale_price,
                  tax_rate_id, current_stock, minimum_stock, max_stock,
                  location, has_expiry, expiry_date, image_path, is_active, deleted_at)
```

### People
```sql
customers        (id, name, mobile, email, address, gst_number, credit_limit,
                  opening_balance, current_balance, photo_path, notes,
                  is_active, created_at, deleted_at)
suppliers        (id, name, contact_person, mobile, email, address, gst_number,
                  bank_name, account_number, opening_balance, current_balance,
                  is_active, created_at, deleted_at)
```

### Transactions
```sql
sales            (id, invoice_number, customer_id, user_id, sale_date, subtotal,
                  discount_amount, tax_amount, grand_total, paid_amount,
                  payment_method, balance_due, status, notes, created_at)
sale_items       (id, sale_id, product_id, quantity, unit_price,
                  discount_pct, tax_pct, subtotal)

purchases        (id, reference_number, supplier_id, user_id, purchase_date,
                  subtotal, tax_amount, grand_total, paid_amount,
                  payment_method, balance_due, status, notes, created_at)
purchase_items   (id, purchase_id, product_id, quantity, unit_price, subtotal)

returns          (id, return_number, type (sale/purchase), reference_id,
                  customer_id, supplier_id, user_id, return_date,
                  total_amount, refund_method, reason, status, created_at)
return_items     (id, return_id, product_id, quantity, unit_price, subtotal)

expenses         (id, category_id, user_id, amount, payment_method,
                  description, receipt_path, expense_date, is_recurring, created_at)
```

### Accounting
```sql
ledger_entries   (id, type, reference_id, party_type (customer/supplier),
                  party_id, debit, credit, balance, narration, entry_date, created_at)
cash_book        (id, type (in/out), reference_id, amount, narration,
                  opening_balance, closing_balance, entry_date, user_id)
bank_book        (id, bank_name, account_number, type (in/out/transfer),
                  amount, narration, entry_date, user_id)
```

### Inventory
```sql
inventory_movements (id, product_id, type (purchase/sale/return/damage/adjustment/transfer),
                     reference_id, qty_before, quantity_change, qty_after,
                     notes, moved_at, user_id)
```

### System
```sql
audit_logs       (id, user_id, action, table_name, record_id,
                  old_values (JSON), new_values (JSON), timestamp)
settings         (id, key, value, updated_at)
```

---

## 🎨 UI/UX HANDOFF FOR CLAUDE DESIGN

### Visual Identity
- **Style:** Professional, clean, enterprise software aesthetic
- **Sidebar:** Dark navy (`#1A1D2E`) with white icons, collapsible to icon-only mode
- **Content area:** Light gray background (`#F8F9FC`), white cards
- **Accent color:** Purple-indigo (`#6C63FF`) for primary actions and highlights
- **Font:** Inter (Google Fonts) — ubiquitous, readable at all sizes
- **Numbers/Prices:** JetBrains Mono — monospaced for alignment in tables

### Screen Inventory (28 distinct screens)
1. Login Screen
2. Dashboard
3. POS (Point of Sale) — most critical
4. Sales List + New Sale Form
5. Sale Detail / Invoice View
6. Purchase List + New Purchase Form
7. Purchase Detail View
8. Product List
9. Product Add/Edit Form
10. Product Detail (with barcode + stock history)
11. Customer List
12. Customer Detail (with ledger)
13. Supplier List
14. Supplier Detail (with ledger)
15. Inventory Movements
16. Stock Adjustment Form
17. Returns List + Return Form
18. Expense List + Expense Form
19. Cash Book
20. Bank Book
21. Reports Hub (grid of report types)
22. Report Viewer (with export/print)
23. User Management
24. Settings (tabbed: Business / Printers / Backup / Security)
25. Backup & Restore
26. Audit Log Viewer
27. Import Wizard (multi-step)
28. Global Search Overlay (Ctrl+K)

### Layout Pattern
```
┌─────────┬──────────────────────────────────────────┐
│         │  Top Bar: Breadcrumb | Search | User     │
│         ├──────────────────────────────────────────┤
│ Sidebar │                                          │
│         │  Page Title + Action Buttons             │
│  Nav    │  ─────────────────────────────────────   │
│  Icons  │  Filter Bar (optional)                   │
│  +      │  ─────────────────────────────────────   │
│  Labels │                                          │
│         │  Main Content (DataTable / Form / Chart) │
│  (dark  │                                          │
│  navy)  │                                          │
│         │  Pagination / Footer                     │
└─────────┴──────────────────────────────────────────┘
```

### POS Layout
```
┌──────────────────────────┬─────────────────────────┐
│  Search: [___________]   │  CART                   │
│  [All] [Food] [Drink]..  │  ─────────────────────  │
│  ┌────┐ ┌────┐ ┌────┐   │  Item 1    2 × $5  $10  │
│  │img │ │img │ │img │   │  Item 2    1 × $8   $8  │
│  │ P1 │ │ P2 │ │ P3 │   │  ─────────────────────  │
│  └────┘ └────┘ └────┘   │  Subtotal         $18   │
│  ┌────┐ ┌────┐ ┌────┐   │  Tax 5%           $0.90 │
│  │img │ │img │ │img │   │  ─────────────────────  │
│  │ P4 │ │ P5 │ │ P6 │   │  TOTAL           $18.90 │
│  └────┘ └────┘ └────┘   │                         │
│                          │  [CASH] [CARD] [SPLIT]  │
│  Customer: [Walk-in ▼]   │  Cash: [$_____]        │
│                          │  Change: $1.10          │
│                          │  [  COMPLETE SALE F12 ] │
└──────────────────────────┴─────────────────────────┘
```

---

## 📝 CLAUDE.md TEMPLATE
*(Put this in your project root — Claude reads this at session start)*

```markdown
# RetailPro — Offline Desktop ERP/POS for Windows

## Project Overview
Flutter Windows desktop app for retail general stores.
Offline-only, SQLite database, no server required.

## Architecture
- Feature-first clean architecture (MVVM + BLoC)
- Drift ORM for SQLite
- get_it + injectable for DI
- go_router for navigation

## Key Decisions
- No hard deletes (soft delete with deleted_at)
- All prices in minor units (paise/cents) stored as integers
- Audit log every data mutation
- Images stored in /data/images/, not in DB
- Backup creates ZIP of: database.db + images + settings

## File Paths (Windows production)
- App: C:\Program Files\RetailPro\
- Data: C:\ProgramData\RetailPro\
- DB: C:\ProgramData\RetailPro\data\database.db
- Images: C:\ProgramData\RetailPro\data\images\
- Backups: C:\ProgramData\RetailPro\backups\

## Packages (see pubspec.yaml for versions)
flutter_bloc, equatable, get_it, injectable,
go_router, drift, sqlite3_flutter_libs,
pdf, excel, fl_chart, windows_printer,
mobile_scanner, barcode_widget, file_picker,
archive, crypto, logger, intl, shared_preferences

## Current Session Progress
[Update this each session with what was completed]
```

---

## ⚠️ SESSION TIPS FOR CLAUDE OPUS

1. **Keep context < 40%** — Start a new session when context fills. Paste CLAUDE.md at the top of every new session.
2. **One module per session** — Don't try to do Products + Customers in one session.
3. **Commit after every session** — Use Git. Tag each session: `git tag session-05-products`
4. **Give Claude the schema** — Paste the relevant table definitions at the start of each session.
5. **Paste existing code** — For sessions 10+, paste 1–2 completed feature implementations as a "style reference" so Claude matches your patterns.
6. **Use CLAUDE.md** — Keep it updated. Claude reads it at session start.
7. **Test before moving on** — Manually verify each session's features before starting the next.

---

## 🚀 REALISTIC TIMELINE

| Weeks | Sessions | Milestone |
|-------|----------|-----------|
| Week 1–2 | 1–4 | Project boots, DB ready, Dashboard, Master data |
| Week 3–4 | 5–8 | Products, Customers, Suppliers, Users |
| Week 5–7 | 9–12 | Inventory, Purchases, Sales, POS working |
| Week 8–9 | 13–15 | Printing, Returns, Expenses |
| Week 10–11 | 16–20 | Accounting, All reports, Search |
| Week 12–13 | 21–25 | Backup, Audit, Alerts, Import, Polish |
| Week 14 | 26–28 | Design system, UX, Installer |

**Realistic calendar: 3–4 months** at 2 sessions/week pace.
**Aggressive pace: 6–7 weeks** at daily sessions.

---

*Document generated August 2026 · RetailPro ERP/POS Master Plan v1.0*
