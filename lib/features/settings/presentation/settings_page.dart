import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/widgets/section_card.dart';
import 'widgets/store_profile_form.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SectionCard(
              title: 'Store Profile',
              child: StoreProfileForm(
                store: store,
                onSaved: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Store profile saved')),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SectionCard(
              title: 'Settings, Backup & Printing',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: Icon(Icons.print),
                    title: Text('Printer setup'),
                    subtitle: Text(
                      'Thermal receipt and A4 invoice configuration placeholder',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.backup),
                    title: Text('Backup / Restore'),
                    subtitle: Text('SQLite ZIP backup workflow placeholder'),
                  ),
                  ListTile(
                    leading: Icon(Icons.security),
                    title: Text('Roles & permissions'),
                    subtitle: Text(
                      'Admin, Manager, Cashier, StoreKeeper, Sales',
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
