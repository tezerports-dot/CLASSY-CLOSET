import 'package:flutter/material.dart';

import '../../../../core/services/retail_store.dart';

/// Lets whoever is signed in change their own password.
///
/// This is how the seeded `admin` / `admin123` credentials get retired, so it
/// sits on the settings page rather than being buried in staff management.
class ChangePasswordForm extends StatefulWidget {
  const ChangePasswordForm({required this.store, super.key});

  final RetailStore store;

  @override
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Signed in as ${widget.store.currentUser?.username ?? '—'}.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _current,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Enter your current password' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _next,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (v) => (v ?? '').trim().length < 4
                      ? 'At least 4 characters'
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Repeat new password',
                  ),
                  validator: (v) =>
                      v != _next.text ? 'The two do not match' : null,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_done) ...[
            const SizedBox(height: 8),
            Text(
              'Password changed.',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.lock_reset),
            label: const Text('Change password'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _done = false;
    });
    final problem = await widget.store.changeOwnPassword(
      _current.text,
      _next.text,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = problem;
      _done = problem == null;
    });
    if (problem == null) {
      _current.clear();
      _next.clear();
      _confirm.clear();
    }
  }
}
