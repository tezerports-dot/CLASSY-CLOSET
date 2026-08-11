# Turning this project into a Windows installer

The goal here is one file — `RetailProSetup.exe` — that you can copy to a shop
PC on a pen drive. The shop machine then needs **no** Flutter, no Git, no
Visual Studio. Someone double-clicks the installer and gets a working till
with a Start-menu entry and a desktop icon.

You do this once on **your own** computer (the "build machine"). Repeat it
whenever you want to ship an update.

---

## Which approach to use

There are three ways to package a Flutter Windows app. For a shop till,
**Inno Setup is the right one.**

| | What you get | Good for you? |
| --- | --- | --- |
| **Plain folder** | Copy the `Release` folder to a pen drive | Works, but the shopkeeper sees 40 loose files and can move the `.exe` away from its DLLs and break it |
| **Inno Setup** | A single `.exe` installer, Start-menu entry, uninstaller | **Yes — use this** |
| **MSIX** | Microsoft Store format | Needs a signing certificate; direct installs show scary warnings unless you buy one |

MSIX is the modern format, but it wants a code-signing certificate for
installs outside the Store. Inno Setup avoids that, and has been the standard
way to ship Windows desktop software for twenty years.

---

## Part 1 — Set up the build machine

Do Steps 1–3 of [WINDOWS_SETUP.md](WINDOWS_SETUP.md) — Git, Flutter, and
Visual Studio with the C++ workload. Then also install Inno Setup:

1. Go to <https://jrsoftware.org/isdl.php>.
2. Download and run the latest **Inno Setup** installer.
3. Accept the defaults.

---

## Part 2 — Build the app

Open Command Prompt:

```
cd C:\CLASSY-CLOSET
git pull
flutter pub get
dart run build_runner build
flutter build windows --release
```

The finished program lands in:

```
C:\CLASSY-CLOSET\build\windows\x64\runner\Release\
```

Check that folder contains `classy_closet.exe`, several `.dll` files and a
`data` folder. **All of it** goes into the installer — the `.exe` alone will
not run.

---

## Part 3 — Set the app's name and icon

These are cosmetic but worth doing once, before you ship to a shop.

### The window title and taskbar name

Open `windows/runner/main.cpp` and find this line:

```cpp
if (!window.Create(L"classy_closet", origin, size)) {
```

Change the text to what the shopkeeper should see:

```cpp
if (!window.Create(L"RetailPro", origin, size)) {
```

### The file properties

Open `windows/runner/Runner.rc` and edit the `CompanyName`, `FileDescription`
and `ProductName` values. These show up when someone right-clicks the `.exe`
and picks Properties.

### The icon

Replace `windows/runner/resources/app_icon.ico` with your own `.ico` file,
keeping the same name. Use a real multi-size `.ico` (16, 32, 48, 256 pixels) —
a renamed `.png` will look wrong. <https://icoconvert.com> will make one.

Rebuild after any of these changes:

```
flutter build windows --release
```

---

## Part 4 — Write the installer script

Create a file called `installer.iss` in `C:\CLASSY-CLOSET` with this content.
Notepad is fine — save it as `installer.iss` with **Save as type: All Files**,
so it does not become `installer.iss.txt`.

```ini
; Inno Setup script for RetailPro
; Build with: iscc installer.iss

#define AppName        "RetailPro"
#define AppVersion     "1.0.0"
#define AppPublisher   "Classy Closet"
#define AppExeName     "classy_closet.exe"
#define BuildDir       "build\windows\x64\runner\Release"

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=installer
OutputBaseFilename=RetailProSetup
Compression=lzma2
SolidCompression=yes
; The app is 64-bit only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Ask for admin rights so it can install into Program Files.
PrivilegesRequired=admin
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; \
    GroupDescription: "Shortcuts:"
Name: "startupicon"; Description: "Start RetailPro when Windows starts"; \
    GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
; Takes the whole Release folder. The exe needs its DLLs and data folder,
; so never narrow this to just the exe.
Source: "{#BuildDir}\*"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";              Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}";    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";        Filename: "{app}\{#AppExeName}"; \
    Tasks: desktopicon
Name: "{userstartup}\{#AppName}";        Filename: "{app}\{#AppExeName}"; \
    Tasks: startupicon

[Run]
Filename: "{app}\{#AppExeName}"; \
    Description: "Open RetailPro now"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Leaves the shop's database alone on uninstall — it lives in AppData, not
; here. Removing it would delete every sale the shop has ever made.
Type: filesandordirs; Name: "{app}"
```

---

## Part 5 — Build the installer

In Command Prompt:

```
cd C:\CLASSY-CLOSET
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
```

Your installer appears at:

```
C:\CLASSY-CLOSET\installer\RetailProSetup.exe
```

That single file is what you copy to the shop.

> **Tip:** add `installer/` and `*.iss` to `.gitignore` if you do not want the
> built installer committed to the repository.

---

## Part 6 — Install it at the shop

1. Copy `RetailProSetup.exe` to a pen drive.
2. On the shop PC, double-click it.
3. Windows shows a blue **"Windows protected your PC"** box. This is expected
   for software that has not been code-signed. Click **More info** →
   **Run anyway**.
4. Follow the wizard. Tick the desktop shortcut, and the startup shortcut if
   you want it to open with the PC.
5. RetailPro opens. Continue from **Step 7 — First run** in
   [WINDOWS_SETUP.md](WINDOWS_SETUP.md).

### Getting rid of the warning

The blue warning appears because the installer is not signed. To remove it you
need an **OV or EV code-signing certificate** from a certificate authority —
around $200–500 a year. For a single shop it is not worth it; teach whoever
installs it to click **More info → Run anyway**.

---

## Shipping an update

The shop's data lives in `%APPDATA%\classy_closet\`, which the installer never
touches. So updating is safe:

1. On your build machine: `git pull`, then Part 2 again.
2. Bump `AppVersion` in `installer.iss` — e.g. `1.0.1`.
3. Re-run Part 5.
4. At the shop, run the new installer over the top. It replaces the program
   and leaves the database alone.

The app migrates its own database when the structure changes, so an older
shop database is upgraded automatically the first time the new version opens.

> Still take a copy of the `ClassyCloset` folder before installing an update.
> A migration that goes wrong is much easier to recover from with a backup.

---

## Quick reference

```
:: Build machine, from C:\CLASSY-CLOSET
git pull
flutter pub get
dart run build_runner build
flutter build windows --release
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss

:: Result
installer\RetailProSetup.exe
```
