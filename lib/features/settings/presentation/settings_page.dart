import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/widgets/section_card.dart';
import 'widgets/backup_panel.dart';
import 'widgets/change_password_form.dart';
import 'widgets/gst_settings_form.dart';
import 'widgets/store_profile_form.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    final backup = getIt<BackupService>();

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
              title: 'Your password',
              child: ChangePasswordForm(store: store),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Backup & restore',
              child: BackupPanel(service: backup),
            ),
            const SizedBox(height: 16),
            const SectionCard(
              title: 'Still to come',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.print),
                    title: Text('Direct thermal printing'),
                    subtitle: Text(
                      'Bills currently print through the Windows print dialog. '
                      'Direct ESC/POS and cash-drawer opening are not wired up yet.',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.assignment_return),
                    title: Text('Returns and exchanges'),
                    subtitle: Text('Not built yet.'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.assessment),
                    title: Text('Detailed reports'),
                    subtitle: Text(
                      'GST return summaries and exports to Excel are not built '
                      'yet.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
