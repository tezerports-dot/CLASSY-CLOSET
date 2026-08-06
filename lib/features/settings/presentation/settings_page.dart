import 'package:flutter/material.dart';

import '../../../core/widgets/section_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: SectionCard(
        title: 'Settings, Backup & Printing',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(leading: Icon(Icons.store), title: Text('Store profile'), subtitle: Text('Classy Closet Retail Store')),
            ListTile(leading: Icon(Icons.print), title: Text('Printer setup'), subtitle: Text('Thermal receipt and A4 invoice configuration placeholder')),
            ListTile(leading: Icon(Icons.backup), title: Text('Backup / Restore'), subtitle: Text('SQLite ZIP backup workflow placeholder')),
            ListTile(leading: Icon(Icons.security), title: Text('Roles & permissions'), subtitle: Text('Admin, Manager, Cashier, StoreKeeper, Sales')),
          ],
        ),
      ),
    );
  }
}
