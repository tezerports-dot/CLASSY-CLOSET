import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/ui_kit.dart';

/// The first screen of the day.
///
/// Split down the middle: the shop's identity on the dark side, the sign-in on
/// the light one. On a narrow screen the brand panel folds away rather than
/// squeezing the form, because the form is the part that has to work.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _store = getIt<RetailStore>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  String? _error;
  bool _busy = false;
  bool _showPassword = false;

  /// True until someone has changed the seeded admin password. While it holds,
  /// the screen says so out loud instead of leaving a shop open on admin123.
  bool get _stillOnSeededPassword => _store.users.length <= 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _usernameFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.laptop;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          if (wide) Expanded(flex: 5, child: _brandPanel(context)),
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: _signInForm(context, compact: !wide),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- brand side

  Widget _brandPanel(BuildContext context) {
    final profile = _store.storeProfile;
    return Container(
      color: AppColors.brand,
      padding: const EdgeInsets.all(56),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClassyClosetPhotoMark(size: 128, path: profile?.logoPath),
          const SizedBox(height: AppSpacing.xxl),
          BrandWordmark(
            name: _store.displayStoreName.toUpperCase(),
            size: 30,
            tagline: (profile?.tagline.trim().isNotEmpty ?? false)
                ? profile!.tagline.toUpperCase()
                : null,
          ),
          const SizedBox(height: 40),
          Container(width: 56, height: 2, color: AppColors.gold),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Billing, stock and accounts for the counter.\n'
            'Everything is kept on this computer — it keeps\n'
            'working when the internet does not.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.brandInkSoft,
              height: 1.7,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: AppColors.brandInkFaint,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Offline · this machine only',
                style: AppTypography.microLabel.copyWith(
                  color: AppColors.brandInkFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- form side

  Widget _signInForm(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact) ...[
          Center(
            child: ClassyClosetPhotoMark(
              size: 78,
              path: _store.storeProfile?.logoPath,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: BrandWordmark(
              name: _store.displayStoreName.toUpperCase(),
              size: 20,
              color: AppColors.ink,
              subColor: AppColors.inkFaint,
              align: CrossAxisAlignment.center,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
        Text('Sign in', style: theme.textTheme.headlineLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Every bill is stamped with whoever is signed in.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 32),

        TextField(
          controller: _username,
          focusNode: _usernameFocus,
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
          ),
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: AppSpacing.base),
        TextField(
          controller: _password,
          focusNode: _passwordFocus,
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.key_outlined, size: 18),
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),

        if (_error != null) ...[
          const SizedBox(height: AppSpacing.base),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.md,
            ),
            decoration: const BoxDecoration(
              color: AppColors.dangerWash,
              borderRadius: AppRadii.inputBorder,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: AppColors.danger,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.xl),
        AccentButton(
          label: 'Sign in',
          icon: Icons.arrow_forward_rounded,
          tall: true,
          expand: true,
          busy: _busy,
          onPressed: _submit,
        ),

        if (_stillOnSeededPassword) ...[
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: AppColors.goldWash,
              borderRadius: AppRadii.inputBorder,
              border: Border.all(color: AppColors.goldWashBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: AppColors.goldDeep,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'First run',
                      style: AppTypography.microLabel.copyWith(
                        color: AppColors.goldDeep,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sign in as admin / admin123, then change that password '
                  'under Settings before the shop opens.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy ? null : _fillSeeded,
                    child: const Text('Fill it in for me'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _fillSeeded() {
    _username.text = 'admin';
    _password.text = 'admin123';
    _submit();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final user = _username.text.trim();
    if (user.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Type a username and a password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await _store.login(user, _password.text);
    if (!mounted) return;
    if (ok) {
      // The router is watching the store and moves us on; clearing the field
      // means the password is not left sitting in memory on a shared counter.
      _password.clear();
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = false;
      _error = 'That username and password do not match. Try again.';
      _password.clear();
    });
    _passwordFocus.requestFocus();
    HapticFeedback.lightImpact();
  }
}
