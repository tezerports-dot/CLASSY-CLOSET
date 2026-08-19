import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../settings/presentation/widgets/store_profile_form.dart';

/// The very first screen a new shop sees.
///
/// The form opens on the packaged defaults so the first shop can accept them
/// and get to the counter; a second shop types over every one of them. Nothing
/// here is baked into the code that prints the bill.
class StoreSetupPage extends StatelessWidget {
  const StoreSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = getIt<RetailStore>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The brand block, on the light ground rather than in a card,
                // so the setup screen reads as the front door of the software.
                Column(
                  children: [
                    const ClassyClosetPhotoMark(size: 84),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Set up your shop',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Text(
                        'These details print on every bill and appear across '
                        'the app. They are stored only on this computer, and '
                        'you can change any of them later under Settings.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.inkSoft,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                const OfflineNotice(
                  message:
                      'This software runs entirely on this PC. Nothing is sent '
                      'anywhere, and the till keeps working when the internet '
                      'does not.',
                ),
                const SizedBox(height: AppSpacing.xl),

                SectionCard(
                  title: 'Shop details',
                  subtitle:
                      'The name, address and GSTIN at the top of the bill, and '
                      'the terms at the bottom.',
                  child: StoreProfileForm(
                    store: store,
                    onSaved: () => context.go('/login'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
