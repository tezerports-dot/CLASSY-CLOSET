import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/printer_service.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ui_kit.dart';
import 'widgets/backup_panel.dart';
import 'widgets/change_password_form.dart';
import 'widgets/gst_settings_form.dart';
import 'widgets/printer_settings_form.dart';
import 'widgets/store_profile_form.dart';

/// Everything about this shop that is not a sale.
///
/// The same build runs in more than one shop, so nothing here is baked into
/// the code — the name, the address, the GSTIN and every line that prints on a
/// bill are typed in on this screen.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

enum _Tab {
  shop('Shop', Icons.storefront_outlined),
  tax('GST', Icons.percent_rounded),
  printing('Printing', Icons.print_outlined),
  account('Your account', Icons.lock_outline_rounded),
  data('Backup', Icons.save_outlined);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _SettingsPageState extends State<SettingsPage> {
  final _store = getIt<RetailStore>();
  final _backup = getIt<BackupService>();
  final _printer = getIt<PrinterService>();

  _Tab _tab = _Tab.shop;

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppColors.brand),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final profile = _store.storeProfile;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Settings',
                subtitle: profile == null
                    ? 'This shop has not been set up yet.'
                    : '${profile.storeName}'
                          '${(profile.gstin ?? '').isEmpty ? '' : '  ·  GSTIN ${profile.gstin}'}',
                actions: [
                  if (_store.can(Permission.manageSettings))
                    SecondaryButton(
                      label: 'Hardware',
                      icon: Icons.print_rounded,
                      onPressed: () => context.go('/hardware'),
                    ),
                ],
              ),

              // A row of tabs rather than one very long scroll: the printing
              // settings are hunted for on their own, not read in sequence
              // after the GST rates.
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<_Tab>(
                  segments: [
                    for (final t in _Tab.values)
                      ButtonSegment(
                        value: t,
                        label: Text(t.label),
                        icon: Icon(t.icon, size: 15),
                      ),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              switch (_tab) {
                _Tab.shop => SectionCard(
                  title: 'Shop profile',
                  subtitle:
                      'The name, address and GSTIN printed at the top of every '
                      'bill, plus the lines printed at the bottom. Filled in '
                      'per shop — a second branch types over these.',
                  child: StoreProfileForm(
                    store: _store,
                    onSaved: () => _toast('Shop profile saved.'),
                  ),
                ),
                _Tab.tax => SectionCard(
                  title: 'GST rates',
                  subtitle:
                      'The rate each kind of garment is sold at, and whether '
                      'your prices already include the tax.',
                  child: GstSettingsForm(
                    store: _store,
                    onSaved: () => _toast('GST settings saved.'),
                  ),
                ),
                _Tab.printing => SectionCard(
                  title: 'Printing',
                  subtitle:
                      'Which printer the bill goes to and what it carries. Use '
                      'the Hardware screen to test the printer, the scanner '
                      'and the drawer.',
                  child: PrinterSettingsForm(store: _store, service: _printer),
                ),
                _Tab.account => SectionCard(
                  title: 'Your password',
                  subtitle:
                      'Change the password for the account you are signed in '
                      'as. Staff accounts are managed under Staff.',
                  child: ChangePasswordForm(store: _store),
                ),
                _Tab.data => SectionCard(
                  title: 'Backup and restore',
                  subtitle:
                      'Everything lives on this computer, so the backup is the '
                      'only copy. Take one onto a pen drive at the end of each '
                      'week.',
                  child: BackupPanel(service: _backup),
                ),
              },
            ],
          ),
        );
      },
    );
  }
}
