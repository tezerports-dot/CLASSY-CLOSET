import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/printer_service.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/widgets/section_card.dart';
import 'widgets/backup_panel.dart';
import 'widgets/change_password_form.dart';
import 'widgets/gst_settings_form.dart';
import 'widgets/printer_settings_form.dart';
import 'widgets/store_profile_form.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    final backup = getIt<BackupService>();
    final printer = getIt<PrinterService>();

    void toast(String message) => ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SectionCard(
              title: 'Store profile',
              child: StoreProfileForm(
                store: store,
                onSaved: () => toast('Store profile saved'),
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'GST',
              child: GstSettingsForm(
                store: store,
                onSaved: () => toast('GST settings saved'),
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Printing',
              child: PrinterSettingsForm(store: store, service: printer),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Your password',
              child: ChangePasswordForm(store: store),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Backup & restore',
              child: BackupPanel(service: backup),
            ),
          ],
        ),
      ),
    );
  }
}
