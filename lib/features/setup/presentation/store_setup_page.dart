import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../settings/presentation/widgets/store_profile_form.dart';

class StoreSetupPage extends StatelessWidget {
  const StoreSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Set up your store', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    const Text('This profile is stored only in this local offline install and controls the app name, logo, receipts, and reports.'),
                    const SizedBox(height: 24),
                    StoreProfileForm(store: store, onSaved: () => context.go('/login')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
