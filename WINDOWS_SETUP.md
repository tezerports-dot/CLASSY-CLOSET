# Setting up RetailPro on the shop computer

This guide is written for someone who does not write code. Follow it top to
bottom on the Windows PC that will sit at the counter. Nothing here needs the
internet once the app is installed.

If you only want to hand a finished installer to the shop, read
[BUILD_INSTALLER.md](BUILD_INSTALLER.md) instead — that explains how to turn
this project into a single `RetailProSetup.exe`. This file covers doing it on
the shop machine directly.

---

## What you need

- A Windows 10 or Windows 11 PC (64-bit).
- About 5 GB of free disk space for the tools, plus space for your data.
- An internet connection **for the setup only**. After that the app runs fully
  offline.
- Administrator rights on the PC (you will be installing software).

Optional hardware, which you can add later:

- A barcode scanner (any USB "keyboard wedge" model — it types the barcode
  like a keyboard, so it needs no driver).
- A thermal receipt printer, 58 mm or 80 mm.
- A cash drawer that plugs into the printer.

---

## Step 1 — Install Git

Git is the tool that downloads the project.

1. Go to <https://git-scm.com/download/win>.
2. The download starts on its own. Run the file it gives you.
3. Click **Next** on every screen, then **Install**, then **Finish**. The
   defaults are all fine.

## Step 2 — Install Flutter

Flutter is what turns the project into a running Windows program.

1. Go to <https://docs.flutter.dev/get-started/install/windows/desktop>.
2. Download the Flutter SDK zip file.
3. Create a folder `C:\src` (open This PC → C: drive → right-click → New →
   Folder → name it `src`).
4. Open the downloaded zip and drag the `flutter` folder inside it into
   `C:\src`. You should end up with `C:\src\flutter`.

   > Do **not** put it in `C:\Program Files`. Flutter needs a folder that does
   > not require administrator rights to write to.

5. Now tell Windows where Flutter is:
   - Press the Windows key, type `environment variables`, and open
     **Edit the system environment variables**.
   - Click **Environment Variables…**
   - Under **User variables**, click the row named **Path**, then **Edit…**
   - Click **New** and type: `C:\src\flutter\bin`
   - Click **OK** on all three windows to close them.

6. Check it worked. Press the Windows key, type `cmd`, open **Command Prompt**,
   and type:

   ```
   flutter --version
   ```

   You should see a version number. If you see "not recognized", close the
   Command Prompt, open a new one, and try again — the Path change only
   applies to newly opened windows.

## Step 3 — Install Visual Studio (the C++ part)

Windows apps need Microsoft's C++ build tools. This is the biggest download,
so start it and make a cup of tea.

1. Go to <https://visualstudio.microsoft.com/downloads/>.
2. Under **Visual Studio Community**, click **Free download**.
3. Run the installer.
4. On the **Workloads** screen, tick **Desktop development with C++**.
   Leave everything else as it is.
5. Click **Install**. This takes 20–40 minutes.
6. Restart the PC when it finishes.

## Step 4 — Download RetailPro

1. Open Command Prompt.
2. Type these lines, pressing Enter after each:

   ```
   cd C:\
   git clone https://github.com/tezerports-dot/CLASSY-CLOSET.git
   cd CLASSY-CLOSET
   ```

You now have the project in `C:\CLASSY-CLOSET`.

## Step 5 — Prepare the app

Still in Command Prompt, in the `C:\CLASSY-CLOSET` folder, run these three
commands one at a time. Wait for each to finish before starting the next.

```
flutter pub get
dart run build_runner build
flutter build windows --release
```

- The first downloads the pieces the app depends on.
- The second generates the database code. **If you skip this the app will not
  build.**
- The third builds the actual program. The first build takes several minutes.

When it finishes you will find the program at:

```
C:\CLASSY-CLOSET\build\windows\x64\runner\Release\classy_closet.exe
```

## Step 6 — Make it easy to open

1. Open that `Release` folder in File Explorer.
2. Right-click `classy_closet.exe` → **Show more options** → **Send to** →
   **Desktop (create shortcut)**.
3. Rename the shortcut on the desktop to `RetailPro`.

> Keep the whole `Release` folder together. The `.exe` needs the `.dll` files
> and the `data` folder next to it. Do not move the `.exe` on its own.

To have it open automatically when the PC starts: press
<kbd>Windows</kbd>+<kbd>R</kbd>, type `shell:startup`, press Enter, and copy
the shortcut into the folder that opens.

---

## Step 7 — First run

Double-click the RetailPro shortcut.

### 7a. Store setup

The first screen asks for your shop details. Fill in:

| Field | What to put |
| --- | --- |
| Store name | Your shop's name, as it should appear on bills |
| Address | Full address for the invoice header |
| Phone | Shop phone number |
| Currency symbol | `₹` |
| GSTIN | Your 15-character GST number |
| State | Your state — this decides CGST/SGST vs IGST |
| Invoice number prefix | Something short, e.g. `CC` |
| Receipt footer | e.g. "Thank you for shopping with us" |
| Logo | Click **Choose logo** and pick your shop's logo image |

**About the GSTIN:** enter it and bills print as a proper **TAX INVOICE** with
your GST number, the HSN code, and the tax split out. Leave it blank and bills
print as a plain receipt instead. The state is filled in automatically from the
first two digits of your GSTIN.

Click **Save store profile**.

### 7b. Log in

- Username: `admin`
- Password: `admin123`

> **Change this password before the shop opens.** Go to **Settings → Your
> password**, enter `admin123` as the current password and set your own.
> Anyone who knows the starter credentials can open your till.

### 7b-2. Add your employee

Go to **Staff → Add staff**.

1. **Full name** and a **username** they will type to sign in.
2. A **password** of at least 4 characters — tell them, and let them change it
   later under Settings.
3. **Role** — pick **Cashier** for a shop employee.

The dialog lists exactly what the chosen role can do before you save. The
**Staff** page also has a full table of every role against every permission.

**What a Cashier can and cannot do:**

| Can | Cannot |
| --- | --- |
| Ring up sales and print bills | See profit, margin or GST collected |
| Search and scan products | See stock value |
| See prices and stock levels | Add or change designs, stock or prices |
| Add and edit customers | Open Reports |
| See the day's takings, to count the drawer | Open Settings or change GST rates |
| | Manage staff or take backups |

They will not even see those menu items — and typing the address directly does
not get them in either, so there is no way around it.

> Use **Manager** instead if you want someone who runs the shop and sees the
> numbers, but still cannot change settings or add staff. Switch an account off
> with **Account is active** when someone leaves; their past sales stay intact.

### 7c. Set your GST rates

Go to **Settings → GST**. This is where you type in the rates your accountant
gives you — nothing is fixed in the program.

- **Charge GST on sales** — turn off if the shop is not GST registered.
- **Selling prices already include GST** — leave this **on** for normal Indian
  retail, where the tag price is what the customer pays and the tax is worked
  backwards out of it. Turn it off only if you add tax on top at the counter.
- **Default HSN code** — used when a design has no HSN of its own.
- **Rate bands** — each row says "up to this price for one piece → this rate".
  Leave the last row's price empty so it catches everything above.

The app starts with the current apparel bands (5% up to ₹2,500 a piece, 18%
above), but **check these with your accountant and change them if needed**. As
you type, the screen shows worked examples — ₹499 → 5%, ₹3,200 → 18% — so you
can see the effect before saving.

Click **Save GST settings**.

> The rate is decided by the price of **one piece**, not the bill total. Three
> ₹800 shirts are still taxed at the ₹800 band.

---

## Step 8 — Put your stock in

Go to **Products** and click **Add design**.

RetailPro is built for clothing, so you enter a **design** once and it creates
every size and colour underneath it automatically.

1. **Design code** — your own code, e.g. `KRT-001`.
2. **Design name** — e.g. `Cotton Kurta`.
3. **Category / Brand / Supplier** — start typing; it suggests ones you have
   used before and creates new ones as you type.
4. **Cost price** — what you paid per piece.
5. **Selling price (MRP)** — what the customer pays. A chip appears under the
   prices showing which GST rate that price falls into.
6. **HSN code** — `6109` for knitted (t-shirts), `6203`/`6204` for woven
   (shirts, trousers). Ask your accountant if you are unsure.
7. **Photo** — click **Add photo**. The picture is copied into the app's own
   folder, so you can move or delete the original afterwards.
8. **Sizes** — type them and press Enter. You can paste a whole run at once:
   `S,M,L,XL,XXL`.
9. **Colours** — the same, e.g. `Black,Navy,Maroon`.
10. **The grid** — colours run down, sizes across. Type how many pieces you
    have of each. Leave a cell at `0` if you will stock it later.

Click **Save design**. Every filled cell becomes its own sellable unit with its
own barcode.

> Barcodes are generated for you from the design code, colour and size. If your
> garments already have printed barcodes, type those in instead.

---

## Step 9 — Make a sale

Go to **POS**.

1. Click a product tile to add it to the cart.
2. Pick the customer, or leave it on **Walk-in Customer**.
3. Choose **Cash**, **Card**, **UPI** or **Split**.
4. For cash, type what the customer handed you — the change is worked out.
5. Choose the paper under **Print on**:
   - **Thermal 80 mm** — the usual counter receipt roll
   - **Thermal 58 mm** — the narrow roll
   - **A4 sheet** — a full tax invoice for a business customer
6. Click **Checkout and print receipt**.

Windows shows its print dialog. Pick your printer and print.

> **Tip:** in the print dialog, tick "Remember my choice" if your printer
> offers it, so you do not pick it every time.

---

## Connecting the hardware

### Barcode scanner

Plug it into a USB port. Windows recognises it as a keyboard — there is no
driver to install. Test it by opening Notepad and scanning something; the
number should appear.

### Thermal receipt printer

1. Plug in the USB cable and switch it on.
2. Install the driver from the CD or the maker's website (Epson, TVS, Retsol
   and similar all provide one).
3. Open **Settings → Bluetooth & devices → Printers & scanners** and check it
   appears.
4. Right-click it → **Printing preferences** → set the paper size to match
   your roll (80 mm or 58 mm).

### Cash drawer

The drawer plugs into the **RJ11 socket on the back of the receipt printer**,
not into the PC. It opens when the printer tells it to. Automatic drawer
opening is not wired up yet — see "What is not built yet" below.

---

## Looking after your data

### Where your data lives

Everything is in one file on this PC:

```
C:\Users\<your name>\AppData\Roaming\classy_closet\ClassyCloset\retailpro.sqlite
```

Product photos and your logo sit in the same `ClassyCloset` folder.

To get there quickly: press <kbd>Windows</kbd>+<kbd>R</kbd>, type
`%APPDATA%\classy_closet\ClassyCloset`, press Enter.

### Backing up

**Do this at the end of every trading day.** It takes ten seconds.

1. Go to **Settings → Backup & restore**.
2. Click **Back up now**.
3. Choose where to save it — a pen drive or an external disk, **not** this PC.
   A PC that dies takes its own backups with it.
4. The app suggests a dated filename like `retailpro-backup-2026-08-11-1930.zip`.
   Keep the last few weeks' worth.

The zip holds your database, the shop logo and every product photo. It is an
ordinary zip — you can open it in Windows Explorer to check it is not empty.

### Restoring

1. Go to **Settings → Backup & restore**.
2. Click **Restore from a backup** and choose the zip.
3. The app checks the file really is a RetailPro backup before doing anything.
4. Confirm. Your current data is copied aside first, so this can be undone.
5. **Close and reopen RetailPro** to finish.

> Restoring replaces everything currently in the app. Only do it if the
> current data is lost or wrong.

### Reaching the shop PC from home

You asked about this. The safe way is **Cloudflare Tunnel** — it lets you reach
the shop PC without opening any ports on the shop router:

1. Sign up free at <https://dash.cloudflare.com>.
2. Go to **Zero Trust → Networks → Tunnels → Create a tunnel**.
3. Choose **Cloudflared**, name it, and download the Windows installer it
   offers. It gives you a command to run — copy and run it on the shop PC.
4. Point the tunnel at the shop PC.

Note this gives you **remote access to the PC**, not a web version of
RetailPro. The app itself stays on the counter machine, which is what keeps it
working when the internet drops.

---

## When something goes wrong

| What you see | What to do |
| --- | --- |
| `flutter` is not recognised | Close Command Prompt, open a new one. If it still fails, redo Step 2.5 (the Path). |
| Build fails mentioning `app_database.g.dart` | You skipped `dart run build_runner build`. Run it and build again. |
| Build fails mentioning Visual Studio or CMake | The C++ workload in Step 3 is missing. Re-run the Visual Studio installer and tick **Desktop development with C++**. |
| The app opens then closes at once | Run the `.exe` from Command Prompt to see the error message. |
| Bills print but say RECEIPT, not TAX INVOICE | Your GSTIN is not saved. Settings → Store Profile → enter it. |
| The receipt is cut off at the sides | Wrong paper size. Change **Print on** in the POS screen, and check the printer's own paper setting. |
| Prices show `$` instead of `₹` | Settings → Store Profile → set the currency symbol to `₹` and save. |

### Updating to a newer version

```
cd C:\CLASSY-CLOSET
git pull
flutter pub get
dart run build_runner build
flutter build windows --release
```

Your data is untouched — it lives outside the project folder.

---

## Day-to-day: the other screens

Beyond billing, these are wired up and working:

| Screen | What it does |
| --- | --- |
| **Purchases** | Record a delivery against the supplier's invoice number. Stock goes up, the cost price follows the new invoice, and anything unpaid is added to what you owe that supplier. |
| **Returns** | Scan or type the bill number, pick what is coming back, and refund by cash, card, UPI or credit. Stock goes back on the shelf and a credit note is numbered. |
| **Till** | Open with a counted float, record cash paid in or out during the day, then close by counting the drawer. The difference is recorded against whoever was on the counter. |
| **Expenses** | Rent, wages, electricity. This is what turns gross margin into real net profit on the reports. |
| **Reports** | Sales register, GST by rate, HSN summary, best sellers and dead stock, for any date range. Every table exports to CSV for your accountant. |
| **Print labels** | On any design in Products. Barcode price labels for the whole size run, on A4 label sheets or a label roll. |

### Printing barcode labels

Go to **Products**, find the design, click **Print labels**.

1. Pick your label stock — 65, 24 or 12 labels per A4 sheet, or a 50 × 25 mm
   roll.
2. Choose what goes on the label: shop name, product name, size/colour, MRP.
3. Copies default to the stock you have, since usually a delivery has just
   arrived and every piece needs one.
4. Click **Preview** first — it costs nothing and saves wasting a sheet if the
   alignment is wrong.

Buy A4 label sheets that match one of the three layouts. The most common in
India is the 65-up (38 × 21 mm) sheet.

### Closing the day

1. **Till → Close the till.** Count the cash in the drawer, type the total.
   The app tells you if you are short or over.
2. **Settings → Backup & restore → Back up now.** To a pen drive.

That is the whole end-of-day routine.

---

## What is not built yet

Be aware of these before you rely on the app for everything:

- **Printing goes through the Windows print dialog.** Direct thermal ESC/POS
  printing and automatic cash-drawer opening are not wired up, so there is a
  print dialog on every sale. The drawer has to be opened by its key or by the
  printer's own button.
- **No physical stock count.** You can correct a count by editing the design's
  grid, but there is no scan-and-count session with a variance report.
- **No customer or supplier statement to print.** Balances are shown on screen
  but cannot be handed to someone as a document.
- **No loyalty points or promotions.**
- **No e-invoicing (IRN/QR).** Only relevant above a turnover threshold —
  check with your accountant whether it applies to you.
- **One shop only.** There is no multi-branch stock transfer.

Everything else described in this guide is finished and tested.

> **Set your GST rates before the first bill.** Go to **Settings → GST**. The
> app starts with the GST 2.0 apparel bands — 5% at or below ₹2,500 a piece,
> 18% above — but you should confirm those with your accountant and type in
> whatever they tell you. The screen shows worked examples as you type, so you
> can see the effect before saving. No new build is needed to change a rate.
